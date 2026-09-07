#!/usr/bin/env bash
#
# update.sh - Automated updater for an existing deploy.sh-managed Jagger
# install.
#
# Backs up the database, config files, and app code, redeploys fresh code
# (same source deploy.sh would use - a local checkout if run from one,
# otherwise a fresh clone of Edugate/Jagger), then lets you choose whether
# to restore your exact old config or regenerate from the updated code's
# own defaults (your FQDN/DB settings, encryption key, and sync password
# are preserved either way - this never rotates those), and finally
# migrates the database schema.
#
# Usage:
#   sudo ./update.sh                    # interactive
#   sudo ./update.sh -y                 # non-interactive (defaults to old config)
#   sudo ./update.sh -y --config=new    # non-interactive, regenerate config
#   sudo ./update.sh --help
#
# Must be run as root, next to deploy.sh, on a host deploy.sh already set up.
#
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_SH="${SCRIPT_DIR}/deploy.sh"
[[ -f "$DEPLOY_SH" ]] || { echo "deploy.sh not found at ${DEPLOY_SH} - update.sh must live next to it." >&2; exit 1; }

# Reuse deploy.sh's helpers and step_* functions (colors, glyphs, banner,
# ask/confirm, run_step/spinner, step_install_jagger, step_configure_jagger,
# step_php_compat) instead of duplicating them - everything before its
# "# Main" marker is just function/variable definitions, nothing runs yet.
# shellcheck disable=SC1090
source <(awk '/^# Main$/{exit} {print}' "$DEPLOY_SH")

# The source above clobbers SCRIPT_DIR (process substitution has no real
# path of its own) and deploy.sh's own step count/weights - reset for this
# script's own 6-step flow.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/jagger-update-$(date +%Y%m%d-%H%M%S).log"
STEP_TOTAL=6
STEP_CURRENT=0
STEP_TIMES=()
STEP_WEIGHTS=(30 90 10 10 15 5)
ASSUME_YES=0
SECONDS=0
CONFIG_MODE=""

# ----------------------------------------------------------------------------
# Update-specific steps
# ----------------------------------------------------------------------------
step_backup() {
    mkdir -p "$BACKUP_DIR/config" "$BACKUP_DIR/images"

    local dbcnf
    dbcnf=$(mktemp)
    chmod 600 "$dbcnf"
    cat >"$dbcnf" <<EOF
[client]
user=${DB_USER}
password=${DB_PASS}
host=127.0.0.1
EOF
    mysqldump --defaults-extra-file="$dbcnf" "$DB_NAME" | gzip >"$BACKUP_DIR/db.sql.gz"
    rm -f "$dbcnf"

    cp -a "$CONFIG_DIR/." "$BACKUP_DIR/config/"
    [[ -d /opt/rr3/images ]] && cp -a /opt/rr3/images/. "$BACKUP_DIR/images/" 2>/dev/null

    local need_kb avail_kb
    need_kb=$(du -sk /opt/rr3 2>/dev/null | awk '{print $1}')
    avail_kb=$(df -k /var/backups 2>/dev/null | awk 'NR==2{print $4}')
    if [[ -n "$need_kb" && -n "$avail_kb" && "$avail_kb" -gt $(( need_kb * 2 )) ]]; then
        tar -czf "$BACKUP_DIR/app.tar.gz" -C /opt rr3
    else
        echo "Skipping full /opt/rr3 code snapshot (not enough free space under /var/backups)."
        echo "The database, config, and images backups above are still complete."
    fi

    mkdir -p /var/backups/jagger
    echo "$BACKUP_DIR" >/var/backups/jagger/.last-backup
}

step_apply_config() {
    if [[ "$CONFIG_MODE" == "new" ]]; then
        LOGO_PATH=""
        step_configure_jagger
        # step_configure_jagger generates fresh secrets - put the originals
        # back so existing sessions/encrypted data aren't invalidated by a
        # routine update.
        [[ -n "$OLD_ENCRYPTION_KEY" ]] && sed -i "s#^\\\$config\['encryption_key'\]\s*=.*#\\\$config['encryption_key'] = '${OLD_ENCRYPTION_KEY}';#" "$CONFIG_DIR/config.php"
        [[ -n "$OLD_SYNCPASS" ]] && sed -i "s#^\\\$config\['syncpass'\]\s*=.*#\\\$config['syncpass'] = '${OLD_SYNCPASS}';#" "$CONFIG_DIR/config_rr.php"
    else
        mkdir -p /var/log/rr3
        chown -R www-data:www-data /var/log/rr3
        mkdir -p /opt/rr3/application/models/Proxies
        cp "$BACKUP_DIR/config/config.php" "$CONFIG_DIR/config.php"
        cp "$BACKUP_DIR/config/config_rr.php" "$CONFIG_DIR/config_rr.php"
        cp "$BACKUP_DIR/config/database.php" "$CONFIG_DIR/database.php"
        cp "$BACKUP_DIR/config/email.php" "$CONFIG_DIR/email.php"
        cp "$BACKUP_DIR/config/memcached.php" "$CONFIG_DIR/memcached.php"
        chown www-data:www-data "$CONFIG_DIR"/config.php "$CONFIG_DIR"/config_rr.php "$CONFIG_DIR"/database.php "$CONFIG_DIR"/email.php "$CONFIG_DIR"/memcached.php
        chown -R www-data:www-data /opt/rr3/application
    fi

    # Restore any custom logo/assets regardless of which config was chosen -
    # these aren't affected by config schema changes between releases.
    if [[ -d "$BACKUP_DIR/images" ]]; then
        cp -a "$BACKUP_DIR/images/." /opt/rr3/images/ 2>/dev/null
    fi
}

step_schema_update() {
    cd /opt/rr3/application
    chmod +x doctrine
    ./doctrine orm:schema-tool:update --force
    ./doctrine orm:generate-proxies
    chown -R www-data:www-data /opt/rr3/application/models/Proxies
}

step_restart_verify() {
    systemctl restart apache2
    sleep 2
    local code
    code=$(curl -sk -o /dev/null -w '%{http_code}' "https://${FQDN}/rr3/" || echo "000")
    echo "HTTP status for https://${FQDN}/rr3/ => ${code}"
    [[ "$code" != "000" ]]
}

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------
for arg in "$@"; do
    case "$arg" in
        -y|--yes) ASSUME_YES=1 ;;
        --config=old) CONFIG_MODE="old" ;;
        --config=new) CONFIG_MODE="new" ;;
        -h|--help)
            sed -n '2,21p' "${BASH_SOURCE[0]}"
            exit 0
            ;;
        *) die "Unknown option: ${arg} (use --help)" ;;
    esac
done

trap 'echo; echo "${YELLOW}Interrupted.${RESET}"; exit 130' INT

clear 2>/dev/null || true
banner
require_root

[[ -d /opt/rr3 ]] || die "No existing Jagger install found at /opt/rr3. Run deploy.sh first."

CONFIG_DIR="/opt/rr3/application/config"
[[ -f "$CONFIG_DIR/config.php" && -f "$CONFIG_DIR/database.php" && -f "$CONFIG_DIR/config_rr.php" ]] \
    || die "/opt/rr3 exists but its config isn't set up (missing config.php/config_rr.php/database.php). Is this a deploy.sh-managed install?"

# --- Detect the existing deployment's settings so we don't have to ask -----
FQDN=$(grep -oP "base_url'\]\s*=\s*'https://\K[^/]+" "$CONFIG_DIR/config.php" || true)
DB_NAME=$(grep -oP "\['database'\]\s*=\s*'\K[^']+" "$CONFIG_DIR/database.php" || true)
DB_USER=$(grep -oP "\['username'\]\s*=\s*'\K[^']+" "$CONFIG_DIR/database.php" || true)
DB_PASS=$(grep -oP "\['password'\]\s*=\s*'\K[^']+" "$CONFIG_DIR/database.php" || true)
OLD_ENCRYPTION_KEY=$(grep -oP "encryption_key'\]\s*=\s*'\K[^']+" "$CONFIG_DIR/config.php" || true)
OLD_SYNCPASS=$(grep -oP "syncpass'\]\s*=\s*'\K[^']+" "$CONFIG_DIR/config_rr.php" || true)

[[ -n "$FQDN" && -n "$DB_NAME" && -n "$DB_USER" ]] \
    || die "Couldn't detect FQDN/DB settings from the existing config files. Is this a deploy.sh-managed install?"

echo "${BOLD}Detected existing install${RESET}"
hr
print_kv "FQDN" "$FQDN"
print_kv "Database" "${DB_NAME} (user: ${DB_USER})"
hr
echo

USE_LOCAL_CHECKOUT=0
[[ -f "${SCRIPT_DIR}/install.sh" && -d "${SCRIPT_DIR}/application/config" ]] && USE_LOCAL_CHECKOUT=1
if [[ "$USE_LOCAL_CHECKOUT" -eq 1 ]]; then
    echo "${DIM}Running from inside a Jagger checkout - this exact copy will replace /opt/rr3.${RESET}"
    echo
fi

if [[ -z "$CONFIG_MODE" ]]; then
    if [[ "$ASSUME_YES" -eq 1 ]]; then
        CONFIG_MODE="old"
    else
        echo "${BOLD}After the fresh redeploy, which configuration should be applied?${RESET}"
        echo "  ${DIM}old - restore your exact backed-up config.php/config_rr.php/database.php as-is.${RESET}"
        echo "  ${DIM}new - regenerate from the updated code's own defaults, with your FQDN, DB${RESET}"
        echo "  ${DIM}      settings, and logo filled back in. Use this if the new release added${RESET}"
        echo "  ${DIM}      config keys the old file doesn't have.${RESET}"
        echo "  ${DIM}Either way your encryption key and sync password are kept as-is - this${RESET}"
        echo "  ${DIM}never rotates those.${RESET}"
        if confirm "Use the NEW default config? (No keeps your OLD config)" N; then
            CONFIG_MODE="new"
        else
            CONFIG_MODE="old"
        fi
    fi
fi

BACKUP_DIR="/var/backups/jagger/$(date +%Y%m%d-%H%M%S)"

echo
echo "${BOLD}Summary${RESET}"
hr
print_kv "Backup to"           "$BACKUP_DIR"
print_kv "Config after update" "$CONFIG_MODE"
print_kv "Source"              "$([[ $USE_LOCAL_CHECKOUT -eq 1 ]] && echo "local checkout (${SCRIPT_DIR})" || echo "github.com/Edugate/Jagger")"
print_kv "Log file"            "$LOG_FILE"
hr
echo

confirm "Start the update now?" Y || { echo "Aborted."; exit 0; }

: >"$LOG_FILE"
chmod 600 "$LOG_FILE"

run_step "Back up database, config, and app code" step_backup
run_step "Fetch latest Jagger code (fresh)"        step_install_jagger
run_step "Apply PHP 8.4 compatibility fixes"       step_php_compat
run_step "Apply ${CONFIG_MODE} configuration"      step_apply_config
run_step "Update database schema (Doctrine)"       step_schema_update
run_step "Restart Apache & verify"                 step_restart_verify

# --- Summary -------------------------------------------------------------
TOTAL_TIME=$SECONDS
echo
hr
echo "${GREEN}${BOLD}${CHECK} Jagger update finished in $(format_hms "$TOTAL_TIME")${RESET}"
hr
for entry in "${STEP_TIMES[@]}"; do
    IFS='|' read -r name dur <<<"$entry"
    printf "  ${DIM}%-46s %s${RESET}\n" "$name" "$(format_hms "$dur")"
done
hr
echo
echo "${BOLD}Next step (manual - cannot be automated):${RESET}"
echo "  Sign in and trigger the app's own upgrade routine by visiting:"
echo "      ${CYAN}https://${FQDN}/rr3/update/upgrade${RESET}"
echo
if [[ "$CONFIG_MODE" == "old" ]]; then
    echo "${YELLOW}Note:${RESET} you kept your old config as-is. If this release added new"
    echo "  config keys, diff it against the fresh defaults to catch anything missing:"
    echo "      diff ${CONFIG_DIR}/config_rr.php ${CONFIG_DIR}/config_rr-default.php"
    echo
fi
echo "${BOLD}If anything looks wrong, your pre-update snapshot is here:${RESET}"
echo "  ${CYAN}${BACKUP_DIR}${RESET}"
echo "  Restore DB     : gunzip -c ${BACKUP_DIR}/db.sql.gz | mysql --user=${DB_USER} -p --host=127.0.0.1 ${DB_NAME}"
echo "  Restore code   : rm -rf /opt/rr3 && tar -xzf ${BACKUP_DIR}/app.tar.gz -C /opt   (if it was created - check disk space above)"
echo "  Restore config : cp ${BACKUP_DIR}/config/*.php ${CONFIG_DIR}/"
echo
echo "${DIM}Full log: ${LOG_FILE}${RESET}"
