#!/usr/bin/env bash
# =============================================================================
# Haku Pi — v1.2.0 (30/08/2026, base 27/08/2026)
# install.sh — installation complète et IDEMPOTENTE du Pi du bord (Haku).
#
# Usage :  sudo ./install.sh          (depuis le dossier du dépôt)
#          relançable autant de fois que nécessaire (mise à jour comprise).
#
# Cible : Raspberry Pi 4 Model B, Raspberry Pi OS Bookworm 64-bit
#         (Lite en mode headless — défaut v1.1.2+ —, Desktop si kiosk).
# Ce que fait ce script, étape par étape (chaque étape est une fonction) :
#   1. copie du dépôt vers /opt/haku
#   2. /etc/haku/haku.env (créé depuis config/haku.env.example si absent)
#   3. paquets requis (curl, jq, nftables, rsync, gnupg)
#   4. protection carte SD : journald en RAM, /var/log et /tmp en tmpfs,
#      swap désactivé
#   5. watchdog matériel (systemd RuntimeWatchdogSec=15)
#   6. vérification cmdline.txt (fsck.repair=yes, option HDMI forcé)
#   7. fuseau horaire (TZ de haku.env)
#   8. Node-RED (script officiel Raspberry Pi) + palette Dashboard 2.0
#   9. déploiement settings.js + flows.json
#  10. unités systemd (healthcheck, backup, reboot hebdo, kiosk, overrides)
#  11. pare-feu nftables (SSH + 1880 + 3001 : LAN du bord + Tailscale uniquement)
#  12. Tailscale (install + enrôlement si TS_AUTHKEY fourni + subnet router)
#  13. kiosk Chromium (autologin, écran jamais en veille, autostart labwc/wayfire)
#  14. (v1.2) InfluxDB 2 « SD light » (dépôt officiel arm64, org/bucket/token
#      automatisés, datadir INFLUX_DATA_DIR, rétention 30 j + downsampling 730 j)
#  15. (v1.2) Grafana port 3001 (provisioning datasource + 3 dashboards,
#      mot de passe admin généré, anonyme désactivé)
#  16. (v1.2) heartbeat dead-man (timer 10 min → HEALTHCHECK_URL)
#
# Les étapes 14-16 tolèrent l'absence d'internet (avertissement + relance
# ultérieure) : le cœur v1.1 du bord reste installable hors ligne.
# Journal complet de l'installation : voir la sortie console.
# =============================================================================
set -euo pipefail

# --- Constantes ---------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPT_DIR="/opt/haku"
ENV_FILE="/etc/haku/haku.env"
NODERED_INSTALLER_URL="https://github.com/node-red/linux-installers/releases/latest/download/install-update-nodered-deb"

log()  { printf '\n\033[1;36m== %s ==\033[0m\n' "$*"; }
info() { printf '   %s\n' "$*"; }
warn() { printf '\033[1;33m   ATTENTION : %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mERREUR : %s\033[0m\n' "$*" >&2; exit 1; }

# set_env_var NOM VALEUR — remplace (ou ajoute) NOM= dans /etc/haku/haku.env.
# v1.2 : utilisé pour les secrets GÉNÉRÉS à bord (INFLUX_TOKEN, mots de passe) —
# jamais de secret dans le dépôt. Valeurs sûres pour sed : hex / base64
# (pas de « & », « \ » ni « | » dans ces alphabets).
set_env_var() {
    local k="$1" v="$2"
    if grep -qE "^${k}=" "${ENV_FILE}"; then
        sed -i "s|^${k}=.*|${k}=${v}|" "${ENV_FILE}"
    else
        printf '%s=%s\n' "${k}" "${v}" >> "${ENV_FILE}"
    fi
    export "${k}=${v}"
}

# -----------------------------------------------------------------------------
require_root() {
    [[ "$(id -u)" -eq 0 ]] || die "lancer avec sudo : sudo ./install.sh"
}

# -----------------------------------------------------------------------------
detect_user() {
    # Utilisateur qui exécutera Node-RED et la session kiosk :
    # celui qui a lancé sudo, sinon le premier compte « humain » (uid 1000).
    HAKU_USER="${SUDO_USER:-}"
    if [[ -z "${HAKU_USER}" || "${HAKU_USER}" == "root" ]]; then
        HAKU_USER="$(awk -F: '$3 == 1000 { print $1; exit }' /etc/passwd || true)"
    fi
    [[ -n "${HAKU_USER}" ]] || die "impossible de déterminer l'utilisateur (créer un compte non-root)"
    USER_HOME="$(getent passwd "${HAKU_USER}" | cut -d: -f6)"
    [[ -d "${USER_HOME}" ]] || die "home de ${HAKU_USER} introuvable"
    log "Utilisateur du bord : ${HAKU_USER} (${USER_HOME})"
}

# -----------------------------------------------------------------------------
install_repo() {
    log "1/16 Copie du dépôt vers ${OPT_DIR}"
    if [[ "${SCRIPT_DIR}" != "${OPT_DIR}" ]]; then
        mkdir -p "${OPT_DIR}"
        rsync -a --delete --exclude '.git' "${SCRIPT_DIR}/" "${OPT_DIR}/"
        info "copié depuis ${SCRIPT_DIR}"
    else
        info "déjà exécuté depuis ${OPT_DIR}"
    fi
    chmod 755 "${OPT_DIR}"/scripts/*.sh "${OPT_DIR}/install.sh"
}

# -----------------------------------------------------------------------------
setup_env() {
    log "2/16 Configuration ${ENV_FILE}"
    mkdir -p /etc/haku
    if [[ ! -f "${ENV_FILE}" ]]; then
        cp "${OPT_DIR}/config/haku.env.example" "${ENV_FILE}"
        warn "haku.env créé depuis l'exemple : ÉDITER LES VALEURS CHANGEME_*"
        warn "   sudo nano ${ENV_FILE}   puis relancer ce script"
    else
        info "haku.env existant conservé"
    fi
    # HAKU_USER écrit/actualisé pour les scripts (backup, update…)
    if grep -qE '^#?HAKU_USER=' "${ENV_FILE}"; then
        sed -i "s|^#\?HAKU_USER=.*|HAKU_USER=${HAKU_USER}|" "${ENV_FILE}"
    else
        printf '\nHAKU_USER=%s\n' "${HAKU_USER}" >> "${ENV_FILE}"
    fi
    # Version (affichée dans /health)
    if [[ -f "${OPT_DIR}/VERSION" ]]; then
        HAKU_VERSION="$(head -1 "${OPT_DIR}/VERSION")"
        if grep -qE '^HAKU_VERSION=' "${ENV_FILE}"; then
            sed -i "s|^HAKU_VERSION=.*|HAKU_VERSION=${HAKU_VERSION}|" "${ENV_FILE}"
        else
            printf 'HAKU_VERSION=%s\n' "${HAKU_VERSION}" >> "${ENV_FILE}"
        fi
    fi
    # Secrets lisibles par root + le groupe de l'utilisateur uniquement
    chown "root:${HAKU_USER}" "${ENV_FILE}"
    chmod 640 "${ENV_FILE}"
    # Chargement pour la suite de l'installation
    set -a
    # shellcheck disable=SC1090
    source "${ENV_FILE}"
    set +a
}

# -----------------------------------------------------------------------------
apt_prereqs() {
    log "3/16 Paquets requis"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq curl jq rsync nftables ca-certificates gnupg > /dev/null
    info "curl, jq, rsync, nftables, gnupg installés"
    if [[ "${KIOSK_ENABLED:-1}" != "0" ]] \
        && ! command -v chromium-browser > /dev/null 2>&1 \
        && ! command -v chromium > /dev/null 2>&1; then
        warn "Chromium absent (image Lite ?) : le kiosk nécessite l'image Desktop"
        warn "   ou : sudo apt install chromium   (nom du paquet sur Bookworm)"
        warn "   (sans écran sur le Pi : mettre KIOSK_ENABLED=0 dans haku.env)"
    fi
}

# -----------------------------------------------------------------------------
sd_protection() {
    log "4/16 Protection de la carte SD"
    # 4a. journald en RAM (volatile)
    mkdir -p /etc/systemd/journald.conf.d
    cp "${OPT_DIR}/config/journald-haku.conf" /etc/systemd/journald.conf.d/10-haku-volatile.conf
    systemctl restart systemd-journald
    info "journald : Storage=volatile (32 Mo max en RAM)"

    # 4b. répertoires recréés à chaque boot (tmpfiles) + dossiers persistants
    sed "s|@HAKU_USER@|${HAKU_USER}|g" "${OPT_DIR}/config/tmpfiles-haku.conf" \
        > /etc/tmpfiles.d/haku.conf
    systemd-tmpfiles --create /etc/tmpfiles.d/haku.conf || true
    info "tmpfiles : /var/lib/haku, /var/log/*, /run/haku"

    # 4c. /var/log et /tmp en tmpfs (effectif au prochain reboot)
    if ! grep -qE '^tmpfs\s+/var/log\s' /etc/fstab; then
        echo 'tmpfs /var/log tmpfs defaults,noatime,nosuid,nodev,mode=0755,size=64m 0 0' >> /etc/fstab
        info "/var/log → tmpfs (fstab, actif au prochain reboot)"
    fi
    if ! grep -qE '^tmpfs\s+/tmp\s' /etc/fstab; then
        echo 'tmpfs /tmp tmpfs defaults,noatime,nosuid,nodev,mode=1777,size=256m 0 0' >> /etc/fstab
        info "/tmp → tmpfs (fstab, actif au prochain reboot)"
    fi

    # 4d. swap désactivé (usure SD ; le Pi 4 a assez de RAM pour cette charge)
    if systemctl list-unit-files dphys-swapfile.service > /dev/null 2>&1; then
        systemctl disable --now dphys-swapfile.service 2> /dev/null || true
        dphys-swapfile swapoff 2> /dev/null || true
        info "swap désactivé (dphys-swapfile)"
    fi
}

# -----------------------------------------------------------------------------
setup_watchdog() {
    log "5/16 Watchdog matériel"
    mkdir -p /etc/systemd/system.conf.d
    cp "${OPT_DIR}/config/watchdog-haku.conf" /etc/systemd/system.conf.d/10-haku-watchdog.conf
    systemctl daemon-reexec
    info "RuntimeWatchdogSec=15 (bcm2835_wdt) — le Pi redémarre seul en cas de gel"
}

# -----------------------------------------------------------------------------
check_cmdline() {
    log "6/16 cmdline.txt (fsck + HDMI)"
    local cmdline="/boot/firmware/cmdline.txt"
    [[ -f "${cmdline}" ]] || cmdline="/boot/cmdline.txt"
    if [[ ! -f "${cmdline}" ]]; then
        warn "cmdline.txt introuvable (environnement de test ?) — étape sautée"
        return 0
    fi
    if ! grep -q 'fsck.repair=yes' "${cmdline}"; then
        sed -i '1 s/$/ fsck.repair=yes/' "${cmdline}"
        info "fsck.repair=yes ajouté (fsck auto au boot)"
    else
        info "fsck.repair=yes déjà présent"
    fi
    if [[ "${KIOSK_FORCE_HDMI:-0}" == "1" ]] && ! grep -q 'video=HDMI' "${cmdline}"; then
        # TODO-VERIFIER-A-BORD : syntaxe KMS video= (voir README « Écran HDMI »)
        sed -i "1 s/$/ video=HDMI-A-1:${KIOSK_HDMI_MODE:-1920x1080M@60D}/" "${cmdline}"
        info "sortie HDMI forcée : video=HDMI-A-1:${KIOSK_HDMI_MODE:-1920x1080M@60D}"
    fi
}

# -----------------------------------------------------------------------------
setup_timezone() {
    log "7/16 Fuseau horaire"
    if [[ -n "${TZ:-}" ]]; then
        timedatectl set-timezone "${TZ}" || warn "fuseau ${TZ} invalide ?"
        info "fuseau : ${TZ}"
    fi
}

# -----------------------------------------------------------------------------
install_nodered() {
    log "8/16 Node-RED + palette Dashboard 2.0"
    if ! command -v node-red > /dev/null 2>&1; then
        info "installation par le script officiel Node-RED (quelques minutes)…"
        # Script officiel : https://nodered.org/docs/getting-started/raspberrypi
        # Lancé EN TANT QUE ${HAKU_USER} (sudo interne du script, NOPASSWD par
        # défaut sur Pi OS) et SANS --confirm-root : certaines versions de
        # l'installeur forcent NODERED_USER=root quand il tourne en root, ce
        # qui écraserait --nodered-user. Ceinture + bretelles : le drop-in
        # systemd (setup_systemd_units) impose de toute façon User=${HAKU_USER}.
        curl -fsSL "${NODERED_INSTALLER_URL}" -o /tmp/nodered-installer.sh
        chmod 644 /tmp/nodered-installer.sh
        sudo -u "${HAKU_USER}" bash /tmp/nodered-installer.sh \
            --confirm-install --confirm-pi --no-init --node22 \
            --nodered-user="${HAKU_USER}"
        rm -f /tmp/nodered-installer.sh
    else
        info "Node-RED déjà installé ($(node-red --help 2>/dev/null | head -1 || echo 'version inconnue'))"
    fi
    systemctl enable nodered.service > /dev/null

    # Palette : Dashboard 2.0 (dans le userDir de l'utilisateur)
    local nr_dir="${USER_HOME}/.node-red"
    sudo -u "${HAKU_USER}" mkdir -p "${nr_dir}"
    if [[ ! -f "${nr_dir}/package.json" ]]; then
        sudo -u "${HAKU_USER}" bash -c \
            "printf '{\n  \"name\": \"haku-node-red\",\n  \"private\": true\n}\n' > '${nr_dir}/package.json'"
    fi
    if [[ ! -d "${nr_dir}/node_modules/@flowfuse/node-red-dashboard" ]]; then
        info "installation @flowfuse/node-red-dashboard…"
        sudo -u "${HAKU_USER}" bash -c \
            "cd '${nr_dir}' && npm install --no-audit --no-fund --loglevel=error @flowfuse/node-red-dashboard"
    else
        info "palette Dashboard 2.0 déjà présente"
    fi
}

# -----------------------------------------------------------------------------
deploy_nodered_files() {
    log "9/16 Déploiement settings.js + flows.json"
    local nr_dir="${USER_HOME}/.node-red"
    sudo -u "${HAKU_USER}" mkdir -p "${nr_dir}"

    # settings.js : sauvegarde unique de l'original s'il diffère
    if [[ -f "${nr_dir}/settings.js" ]] && ! cmp -s "${OPT_DIR}/config/settings.js" "${nr_dir}/settings.js"; then
        cp "${nr_dir}/settings.js" "${nr_dir}/settings.js.avant-haku.$(date +%Y%m%d-%H%M%S)"
    fi
    cp "${OPT_DIR}/config/settings.js" "${nr_dir}/settings.js"

    # flows.json : import automatique, MAIS sans écraser des flux modifiés
    # localement par le propriétaire (édités dans l'éditeur Node-RED).
    # On mémorise le hash de la dernière version déployée par install.sh :
    #  - flux local == dernier déployé  → mise à jour normale (avec backup) ;
    #  - flux local  != dernier déployé → modifs locales : ON N'ÉCRASE PAS.
    local hash_file="/etc/haku/flows.deployed.sha256"
    local repo_hash local_hash last_deployed
    repo_hash="$(sha256sum "${OPT_DIR}/node-red/flows.json" | cut -d' ' -f1)"
    if [[ -f "${nr_dir}/flows.json" ]]; then
        local_hash="$(sha256sum "${nr_dir}/flows.json" | cut -d' ' -f1)"
        last_deployed="$(cat "${hash_file}" 2>/dev/null || true)"
        if [[ "${local_hash}" == "${repo_hash}" ]]; then
            info "flows.json déjà à jour"
        elif [[ -n "${last_deployed}" && "${local_hash}" != "${last_deployed}" ]]; then
            warn "flows locaux modifiés depuis le dernier déploiement : NON écrasés"
            warn "   (vos éditions dans l'éditeur Node-RED sont préservées)"
            warn "   pour forcer la version du dépôt : supprimer ${nr_dir}/flows.json"
            warn "   puis relancer install.sh — l'ancienne version restera dans"
            warn "   flows.json.avant-haku.* et dans les sauvegardes /boot/firmware"
        else
            cp "${nr_dir}/flows.json" "${nr_dir}/flows.json.avant-haku.$(date +%Y%m%d-%H%M%S)"
            cp "${OPT_DIR}/node-red/flows.json" "${nr_dir}/flows.json"
            echo "${repo_hash}" > "${hash_file}"
            info "flows mis à jour (ancien sauvegardé en flows.json.avant-haku.*)"
        fi
    else
        cp "${OPT_DIR}/node-red/flows.json" "${nr_dir}/flows.json"
        echo "${repo_hash}" > "${hash_file}"
        info "flows importés automatiquement (${nr_dir}/flows.json)"
    fi
    chown -R "${HAKU_USER}:${HAKU_USER}" "${nr_dir}"
}

# -----------------------------------------------------------------------------
setup_systemd_units() {
    log "10/16 Unités systemd"
    # Drop-in nodered : rendu des placeholders puis installation.
    # C'est LUI qui garantit User/Group/WorkingDirectory = utilisateur du bord
    # (verrou contre l'installeur officiel qui peut forcer root), en plus de
    # EnvironmentFile + Restart=always.
    mkdir -p /etc/systemd/system/nodered.service.d
    sed -e "s|@HAKU_USER@|${HAKU_USER}|g" -e "s|@USER_HOME@|${USER_HOME}|g" \
        "${OPT_DIR}/systemd/nodered-override.conf" \
        > /etc/systemd/system/nodered.service.d/haku.conf

    # Unités système
    cp "${OPT_DIR}/systemd/haku-healthcheck.service" /etc/systemd/system/
    cp "${OPT_DIR}/systemd/haku-healthcheck.timer"   /etc/systemd/system/
    cp "${OPT_DIR}/systemd/haku-backup.service"      /etc/systemd/system/
    cp "${OPT_DIR}/systemd/haku-backup.timer"        /etc/systemd/system/
    cp "${OPT_DIR}/systemd/haku-reboot.service"      /etc/systemd/system/
    cp "${OPT_DIR}/systemd/haku-reboot.timer"        /etc/systemd/system/

    # Unité utilisateur (kiosk), démarrée par l'autostart labwc/wayfire
    mkdir -p /etc/systemd/user
    cp "${OPT_DIR}/systemd/haku-kiosk.service" /etc/systemd/user/

    systemctl daemon-reload
    systemctl enable --now haku-healthcheck.timer > /dev/null
    systemctl enable --now haku-backup.timer > /dev/null
    systemctl enable --now haku-reboot.timer > /dev/null
    info "healthcheck (2 min), backup (04:10), reboot hebdo (dim 04:30 — désactivable)"
}

# -----------------------------------------------------------------------------
setup_firewall() {
    log "11/16 Pare-feu nftables"
    local subnet="${SUBNET_BORD:-192.168.8.0/24}"
    local rendered="/tmp/haku-nftables.conf"
    sed "s|@SUBNET_BORD@|${subnet}|g" "${OPT_DIR}/config/nftables.conf" > "${rendered}"
    if ! nft -c -f "${rendered}"; then
        die "règles nftables invalides (SUBNET_BORD=${subnet} ?) — pare-feu inchangé"
    fi
    if [[ -f /etc/nftables.conf && ! -f /etc/nftables.conf.avant-haku ]]; then
        cp /etc/nftables.conf /etc/nftables.conf.avant-haku
    fi
    cp "${rendered}" /etc/nftables.conf
    rm -f "${rendered}"
    systemctl enable nftables.service > /dev/null
    nft -f /etc/nftables.conf
    info "SSH + Node-RED accessibles depuis ${subnet} et tailscale0 uniquement"

    # Garde-fou anti-verrouillage : l'IP du Pi doit appartenir à SUBNET_BORD,
    # sinon les règles ci-dessus bloquent SSH/dashboard depuis le LAN.
    local pi_ip
    pi_ip="$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1 || true)"
    if [[ -n "${pi_ip}" ]] && ! python3 -c "import ipaddress,sys; sys.exit(0 if ipaddress.ip_address('${pi_ip}') in ipaddress.ip_network('${subnet}', strict=False) else 1)" 2>/dev/null; then
        warn "l'IP du Pi (${pi_ip}) n'est PAS dans SUBNET_BORD (${subnet}) !"
        warn "   SSH/dashboard seraient bloqués depuis le LAN : corriger SUBNET_BORD"
        warn "   dans ${ENV_FILE} puis relancer install.sh (secours : ip6 link-local"
        warn "   fe80::/10 et tailscale0 restent autorisés)"
    fi
}

# -----------------------------------------------------------------------------
setup_tailscale() {
    log "12/16 Tailscale (accès distant à travers le CGNAT Starlink)"
    if ! command -v tailscale > /dev/null 2>&1; then
        info "installation par le script officiel…"
        curl -fsSL https://tailscale.com/install.sh | sh
    else
        info "tailscale déjà installé ($(tailscale version | head -1))"
    fi
    systemctl enable --now tailscaled > /dev/null

    # Subnet router : le noyau doit router entre tailscale0 et le LAN du bord
    cat > /etc/sysctl.d/99-haku-tailscale.conf <<'SYSCTL'
# Haku Pi — subnet router Tailscale (accès Cerbo depuis l'extérieur)
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
SYSCTL
    sysctl -p /etc/sysctl.d/99-haku-tailscale.conf > /dev/null

    local state
    state="$(tailscale status --json 2>/dev/null | jq -r '.BackendState' || echo 'Inconnu')"
    if [[ "${state}" == "Running" ]]; then
        info "déjà enrôlé (BackendState=Running) — « tailscale up » non relancé"
        info "pour changer les routes : voir README, section Tailscale"
        return 0
    fi
    if [[ -z "${TS_AUTHKEY:-}" || "${TS_AUTHKEY}" == CHANGEME* ]]; then
        warn "TS_AUTHKEY non renseigné dans ${ENV_FILE}"
        warn "   enrôlement manuel : sudo tailscale up --hostname=haku --accept-dns=false"
        return 0
    fi
    local args=(up --authkey="${TS_AUTHKEY}" --hostname=haku --accept-dns=false)
    if [[ "${TS_ADVERTISE_ROUTES:-1}" == "1" ]]; then
        args+=(--advertise-routes="${SUBNET_BORD:-192.168.8.0/24}")
    fi
    if tailscale "${args[@]}"; then
        info "enrôlé. Approuver la route ${SUBNET_BORD:-} dans la console admin Tailscale."
    else
        warn "tailscale up a échoué (clé expirée ? pas d'Internet ?) — relancer install.sh plus tard"
    fi
}

# -----------------------------------------------------------------------------
setup_kiosk() {
    log "13/16 Kiosk Chromium (écran du carré)"

    # Mode headless (v1.1.2) : pas d'écran sur le Pi — consultation smartphone/PC
    # via LAN + Tailscale. Ni autologin, ni autostart, ni Chromium.
    if [[ "${KIOSK_ENABLED:-1}" == "0" ]]; then
        info "KIOSK_ENABLED=0 : mode headless — kiosk et autologin ignorés"
        return 0
    fi

    # 13a. autologin bureau (B4 = Desktop Autologin) — nécessite l'image Desktop
    if command -v raspi-config > /dev/null 2>&1; then
        if raspi-config nonint do_boot_behaviour B4; then
            info "autologin bureau activé (raspi-config B4)"
        else
            warn "autologin impossible (image Lite ?)"
        fi
        # 13b. veille écran désactivée (nonint : 1 = blanking désactivé)
        if raspi-config nonint do_blanking 1; then
            info "veille écran désactivée"
        else
            warn "do_blanking indisponible"
        fi
    else
        warn "raspi-config absent : autologin et veille écran à régler à la main"
    fi

    # 13c. ligne d'autostart : importe l'environnement Wayland dans systemd --user
    #      puis démarre l'unité supervisée haku-kiosk.service.
    local astart_cmd="/usr/bin/systemctl --user import-environment WAYLAND_DISPLAY XDG_RUNTIME_DIR DISPLAY 2>/dev/null; /usr/bin/systemctl --user restart haku-kiosk.service"

    # labwc (Pi OS Bookworm depuis fin 2024) : ~/.config/labwc/autostart
    local labwc_dir="${USER_HOME}/.config/labwc"
    mkdir -p "${labwc_dir}"
    touch "${labwc_dir}/autostart"
    if ! grep -q 'haku-kiosk' "${labwc_dir}/autostart"; then
        printf '\n# HAKU-KIOSK (ajouté par install.sh — ne pas dupliquer)\n%s &\n' \
            "${astart_cmd}" >> "${labwc_dir}/autostart"
        info "autostart labwc : ${labwc_dir}/autostart"
    else
        info "autostart labwc déjà en place"
    fi

    # wayfire (premières images Bookworm) : section [autostart] de wayfire.ini.
    # NB : la réécriture par configparser ne préserve pas les COMMENTAIRES du
    # wayfire.ini (les réglages, eux, sont conservés) — signalé dans le README.
    local wayfire_ini="${USER_HOME}/.config/wayfire.ini"
    if [[ -f "${wayfire_ini}" ]] || command -v wayfire > /dev/null 2>&1; then
        HAKU_ASTART="${astart_cmd}" python3 - "${wayfire_ini}" <<'PYEOF'
import configparser
import os
import sys

path = sys.argv[1]
cmd = os.environ["HAKU_ASTART"]
cp = configparser.ConfigParser(interpolation=None)
if os.path.exists(path):
    cp.read(path)
if not cp.has_section("autostart"):
    cp.add_section("autostart")
if cp.get("autostart", "haku_kiosk", fallback="") != cmd:
    cp.set("autostart", "haku_kiosk", cmd)
    with open(path, "w", encoding="utf-8") as fh:
        cp.write(fh)
    print("   autostart wayfire mis à jour :", path)
else:
    print("   autostart wayfire déjà en place")
PYEOF
        chown "${HAKU_USER}:${HAKU_USER}" "${wayfire_ini}" 2> /dev/null || true
    fi
    chown -R "${HAKU_USER}:${HAKU_USER}" "${USER_HOME}/.config"

    info "URL kiosk : ${KIOSK_URL:-http://127.0.0.1:1880/dashboard/haku}"
    info "(le curseur n'apparaît pas si aucune souris n'est branchée — voir README)"
}

# -----------------------------------------------------------------------------
setup_influxdb() {
    log "14/16 InfluxDB 2 « SD light » (traceur + historique long)"
    if [[ "${INFLUX_ENABLED:-1}" != "1" ]]; then
        info "INFLUX_ENABLED=0 : étape sautée"
        if systemctl is-enabled influxdb > /dev/null 2>&1; then
            systemctl disable --now influxdb 2> /dev/null || true
            info "service influxdb existant arrêté et désactivé"
        fi
        return 0
    fi

    # 14a. dépôt officiel InfluxData (arm64, PAS de Docker) — idempotent,
    #      tolérant à l'absence d'internet (relancer install.sh plus tard).
    local key="/etc/apt/keyrings/influxdata-archive.gpg"
    if [[ ! -f "${key}" ]]; then
        mkdir -p /etc/apt/keyrings
        if ! curl -fsSL https://repos.influxdata.com/influxdata-archive.key \
                | gpg --dearmor -o "${key}" 2> /dev/null; then
            rm -f "${key}"
            warn "clé du dépôt InfluxData injoignable (pas d'internet ?) — étape sautée,"
            warn "   relancer install.sh quand Starlink est le WAN actif"
            return 0
        fi
    fi
    if [[ ! -f /etc/apt/sources.list.d/influxdata.list ]]; then
        echo "deb [signed-by=${key}] https://repos.influxdata.com/debian stable main" \
            > /etc/apt/sources.list.d/influxdata.list
        apt-get update -qq || true
    fi
    if ! command -v influxd > /dev/null 2>&1; then
        info "installation influxdb2 (quelques minutes, ~100 Mo)…"
        if ! apt-get install -y -qq influxdb2 > /dev/null; then
            warn "installation influxdb2 impossible (internet ?) — étape sautée"
            return 0
        fi
    fi
    # CLI « influx » : paquet séparé depuis la 2.1
    if ! command -v influx > /dev/null 2>&1; then
        apt-get install -y -qq influxdb2-cli > /dev/null 2>&1 || true
    fi
    command -v influx > /dev/null 2>&1 || {
        warn "CLI influx introuvable : setup org/bucket/token impossible — étape sautée"
        return 0
    }

    # 14b. datadir (SD aujourd'hui ; SSD demain : changer INFLUX_DATA_DIR
    #      dans haku.env + rsync -a de l'ancien dossier, puis relancer ici).
    local ddir="${INFLUX_DATA_DIR:-/var/lib/haku/influx}"
    mkdir -p "${ddir}"
    chown -R influxdb:influxdb "${ddir}"

    # 14c. drop-in systemd : datadir + bind 127.0.0.1 + MemoryHigh=700M
    #      (protège Node-RED — la limite douce ralentit influxd avant l'OOM).
    mkdir -p /etc/systemd/system/influxdb.service.d
    sed "s|@INFLUX_DATA_DIR@|${ddir}|g" "${OPT_DIR}/config/influxdb-override.conf" \
        > /etc/systemd/system/influxdb.service.d/haku.conf
    systemctl daemon-reload
    systemctl enable influxdb > /dev/null 2>&1 || true
    systemctl restart influxdb

    # 14d. attendre l'API locale (premier démarrage : quelques secondes)
    local up=0
    for _ in $(seq 1 30); do
        if curl -fs --max-time 2 http://127.0.0.1:8086/health > /dev/null 2>&1; then
            up=1
            break
        fi
        sleep 2
    done
    if [[ "${up}" != "1" ]]; then
        warn "influxd ne répond pas sur 127.0.0.1:8086 — journalctl -u influxdb"
        return 0
    fi

    # 14e. setup initial UNE SEULE FOIS : org/bucket/rétention 30 j + token
    #      généré ici et écrit dans haku.env (jamais en dur dans le dépôt).
    local org="${INFLUX_ORG:-haku}" bucket="${INFLUX_BUCKET:-haku_raw}"
    local bagg="${INFLUX_BUCKET_AGG:-haku_agg}"
    local allowed
    allowed="$(curl -fs http://127.0.0.1:8086/api/v2/setup 2>/dev/null | jq -r '.allowed' || echo 'error')"
    if [[ "${allowed}" == "true" ]]; then
        # valeurs pré-remplies dans haku.env honorées, sinon générées ici
        local tok pw
        tok="${INFLUX_TOKEN:-}"
        [[ -n "${tok}" ]] || tok="$(openssl rand -hex 32)"
        pw="${INFLUX_ADMIN_PASS:-}"
        [[ -n "${pw}" ]] || pw="$(openssl rand -base64 15)"
        if influx setup --force --host http://127.0.0.1:8086 \
                --org "${org}" --bucket "${bucket}" --retention 30d \
                --username admin --password "${pw}" --token "${tok}" > /dev/null; then
            set_env_var INFLUX_TOKEN "${tok}"
            set_env_var INFLUX_ADMIN_PASS "${pw}"
            info "InfluxDB initialisé : org=${org}, bucket=${bucket} (30 j)"
            info "token API + mot de passe admin écrits dans ${ENV_FILE}"
        else
            warn "influx setup a échoué — journalctl -u influxdb"
            return 0
        fi
    else
        info "InfluxDB déjà initialisé"
        if ! grep -qE '^INFLUX_TOKEN=.+' "${ENV_FILE}"; then
            warn "INFLUX_TOKEN absent de haku.env alors qu'Influx est initialisé :"
            warn "   créer un token (influx auth create --all-access) et le coller"
            warn "   dans ${ENV_FILE}, puis relancer install.sh"
            return 0
        fi
    fi

    # 14f. bucket agrégé 730 j + tâche de downsampling 10 min (« SD light »)
    local tok2="${INFLUX_TOKEN:-}"
    tok2="$(grep -E '^INFLUX_TOKEN=' "${ENV_FILE}" | tail -1 | cut -d= -f2-)"
    [[ -n "${tok2}" ]] || { warn "INFLUX_TOKEN vide : buckets/tâche non vérifiés"; return 0; }
    local iargs=(--host http://127.0.0.1:8086 --token "${tok2}" --org "${org}")
    if ! influx bucket list "${iargs[@]}" 2> /dev/null | grep -q "	${bagg}	\|[[:space:]]${bagg}[[:space:]]"; then
        if influx bucket create "${iargs[@]}" --name "${bagg}" --retention 730d > /dev/null 2>&1; then
            info "bucket agrégé ${bagg} créé (rétention 730 j)"
        else
            warn "création du bucket ${bagg} impossible (token ? droits ?)"
        fi
    else
        info "bucket agrégé ${bagg} déjà présent"
    fi
    if ! influx task list "${iargs[@]}" 2> /dev/null | grep -q 'haku-downsample-10m'; then
        local flux="/tmp/haku-downsample.flux"
        sed -e "s|@INFLUX_BUCKET@|${bucket}|g" -e "s|@INFLUX_BUCKET_AGG@|${bagg}|g" \
            "${OPT_DIR}/config/influx-downsample.flux" > "${flux}"
        if influx task create "${iargs[@]}" --file "${flux}" > /dev/null 2>&1; then
            info "tâche de downsampling 10 min → ${bagg} créée"
        else
            warn "création de la tâche de downsampling impossible"
        fi
        rm -f "${flux}"
    else
        info "tâche de downsampling déjà présente"
    fi
    info "API : 127.0.0.1:8086 (local uniquement) — données : ${ddir}"
}

# -----------------------------------------------------------------------------
setup_grafana() {
    log "15/16 Grafana (port ${GRAFANA_PORT:-3001} — Traceur / Météo / Électrique)"
    if [[ "${GRAFANA_ENABLED:-1}" != "1" ]]; then
        info "GRAFANA_ENABLED=0 : étape sautée"
        if systemctl is-enabled grafana-server > /dev/null 2>&1; then
            systemctl disable --now grafana-server 2> /dev/null || true
            info "service grafana-server existant arrêté et désactivé"
        fi
        return 0
    fi

    # 15a. dépôt officiel Grafana (arm64) — idempotent, tolérant hors-ligne
    local key="/etc/apt/keyrings/grafana.gpg"
    if [[ ! -f "${key}" ]]; then
        mkdir -p /etc/apt/keyrings
        if ! curl -fsSL https://apt.grafana.com/gpg.key | gpg --dearmor -o "${key}" 2> /dev/null; then
            rm -f "${key}"
            warn "clé du dépôt Grafana injoignable (pas d'internet ?) — étape sautée"
            return 0
        fi
    fi
    if [[ ! -f /etc/apt/sources.list.d/grafana.list ]]; then
        echo "deb [signed-by=${key}] https://apt.grafana.com stable main" \
            > /etc/apt/sources.list.d/grafana.list
        apt-get update -qq || true
    fi
    if ! command -v grafana-server > /dev/null 2>&1; then
        info "installation grafana (quelques minutes, ~120 Mo)…"
        if ! apt-get install -y -qq grafana > /dev/null; then
            warn "installation grafana impossible (internet ?) — étape sautée"
            return 0
        fi
    fi

    # 15b. drop-in systemd : port 3001, anonyme désactivé, MemoryHigh=300M
    mkdir -p /etc/systemd/system/grafana-server.service.d
    sed "s|@GRAFANA_PORT@|${GRAFANA_PORT:-3001}|g" "${OPT_DIR}/config/grafana-override.conf" \
        > /etc/systemd/system/grafana-server.service.d/haku.conf

    # 15c. provisioning : datasource Influx (token depuis haku.env, rendu ici —
    #      aucun secret dans le dépôt) + les 3 dashboards JSON du dépôt.
    local tok
    tok="$(grep -E '^INFLUX_TOKEN=' "${ENV_FILE}" | tail -1 | cut -d= -f2- || true)"
    mkdir -p /etc/grafana/provisioning/datasources /etc/grafana/provisioning/dashboards
    if [[ -n "${tok}" ]]; then
        local dsrc="/etc/grafana/provisioning/datasources/haku.yaml"
        local tmp="/tmp/haku-grafana-dsrc.yaml"
        sed -e "s|@INFLUX_ORG@|${INFLUX_ORG:-haku}|g" \
            -e "s|@INFLUX_BUCKET@|${INFLUX_BUCKET:-haku_raw}|g" \
            -e "s|@INFLUX_TOKEN@|${tok}|g" \
            "${OPT_DIR}/config/grafana-datasource.yaml" > "${tmp}"
        if ! cmp -s "${tmp}" "${dsrc}"; then
            cp "${tmp}" "${dsrc}"
            info "datasource InfluxDB provisionnée (jeton depuis haku.env)"
        fi
        rm -f "${tmp}"
        chown root:grafana "${dsrc}"
        chmod 640 "${dsrc}"
    else
        warn "INFLUX_TOKEN vide : datasource non provisionnée (relancer après l'étape 14)"
    fi
    cp "${OPT_DIR}/config/grafana-dashboards.yaml" /etc/grafana/provisioning/dashboards/haku.yaml
    info "dashboards provisionnés depuis ${OPT_DIR}/grafana/dashboards (Traceur, Météo bord, Électrique)"

    systemctl daemon-reload
    systemctl enable grafana-server > /dev/null 2>&1 || true
    systemctl restart grafana-server

    # 15d. mot de passe admin : généré UNE fois (pattern gen-adminauth.sh —
    #      changement manuel : sudo /opt/haku/scripts/gen-grafana-pass.sh)
    local pass
    pass="$(grep -E '^GRAFANA_ADMIN_PASS=' "${ENV_FILE}" | tail -1 | cut -d= -f2- || true)"
    if [[ -z "${pass}" ]]; then
        pass="$(openssl rand -base64 15)"
        for _ in $(seq 1 30); do
            if curl -fs --max-time 2 "http://127.0.0.1:${GRAFANA_PORT:-3001}/api/health" > /dev/null 2>&1; then
                break
            fi
            sleep 2
        done
        systemctl stop grafana-server
        if grafana-cli --homepath /usr/share/grafana --config /etc/grafana/grafana.ini \
                admin reset-admin-password "${pass}" > /dev/null 2>&1; then
            set_env_var GRAFANA_ADMIN_PASS "${pass}"
            info "mot de passe admin généré et écrit dans ${ENV_FILE}"
        else
            warn "reset-admin-password a échoué — mot de passe par défaut NON changé :"
            warn "   lancer : sudo ${OPT_DIR}/scripts/gen-grafana-pass.sh"
        fi
        systemctl start grafana-server
    else
        info "mot de passe admin déjà en place (GRAFANA_ADMIN_PASS)"
    fi
    info "Grafana : http://haku.local:${GRAFANA_PORT:-3001} (admin / GRAFANA_ADMIN_PASS de haku.env)"
    info "pare-feu : 3001 ouvert UNIQUEMENT depuis ${SUBNET_BORD:-192.168.8.0/24} et tailscale0"
}

# -----------------------------------------------------------------------------
setup_heartbeat() {
    log "16/16 Heartbeat dead-man (HEALTHCHECK_URL)"
    cp "${OPT_DIR}/systemd/haku-heartbeat.service" /etc/systemd/system/
    cp "${OPT_DIR}/systemd/haku-heartbeat.timer"   /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable --now haku-heartbeat.timer > /dev/null
    if [[ -z "${HEALTHCHECK_URL:-}" || "${HEALTHCHECK_URL:-}" == CHANGEME* ]]; then
        info "HEALTHCHECK_URL vide : timer en place mais inactif (aucun ping)"
        info "recommandé : compte gratuit healthchecks.io → coller l'URL du check"
        info "dans ${ENV_FILE} (period 10 min, grace 15 min) — voir README"
    else
        info "ping toutes les 10 min vers ${HEALTHCHECK_URL} (si /health répond)"
        info "le SILENCE déclenche l'alerte côté service externe"
    fi
}

# -----------------------------------------------------------------------------
finish() {
    log "Redémarrage de Node-RED avec la configuration Haku"
    systemctl restart nodered
    sleep 5
    if curl --silent --fail --max-time 10 http://127.0.0.1:1880/health > /dev/null; then
        info "Node-RED répond sur /health — installation opérationnelle"
    else
        warn "Node-RED ne répond pas encore (démarrage en cours ?) :"
        warn "   journalctl -u nodered -f"
    fi

    log "INSTALLATION TERMINÉE — reste à faire (voir README)"
    cat <<FIN
   1. Éditer ${ENV_FILE} (CERBO_HOST, LAT/LON, SMTP, TS_AUTHKEY, SUBNET_BORD)
      puis :  sudo systemctl restart nodered
   2. Mot de passe éditeur :  sudo ${OPT_DIR}/scripts/gen-adminauth.sh
   3. Sur le Cerbo GX : Settings > Services > MQTT on LAN (SSL+plain) = ON
      et Settings > Relay > Function (Relay 1) = Manual
   4. Câbler le relais 1 du Cerbo vers le feu de mouillage (À CÂBLER À BORD,
      schéma dans le README) puis vérifier RELAY_DBUS_INDEX avec MQTT Explorer.
   5. SSH par clé uniquement (procédure README, section Sécurité).
   6. Reboot conseillé pour activer tmpfs + watchdog :  sudo reboot
   Dashboard : http://haku.local:1880/dashboard  (page Surveillance par défaut)
   Page Bord : http://haku.local:1880/dashboard/haku
   Carte     : http://haku.local:1880/dashboard/navigations   (v1.1)
   Grafana   : http://haku.local:${GRAFANA_PORT:-3001}  (v1.2 — admin / GRAFANA_ADMIN_PASS)
   v1.1 : patch journal du Cerbo (cerbo/PATCH_Journal_vers_Pi.md), import de
   l'historique (scripts/import-journal.py), instances flotteurs DIGITAL_IN_*
   dans ${ENV_FILE} apres cablage.
   v1.2 : heartbeat (HEALTHCHECK_URL, healthchecks.io) ; module Waveshare :
   suivre FICHE_CABLAGE_Waveshare_Haku.md puis WAVESHARE_ENABLED=1 + WAVESHARE_HOST.
FIN
}

# -----------------------------------------------------------------------------
main() {
    require_root
    detect_user
    install_repo
    setup_env
    apt_prereqs
    sd_protection
    setup_watchdog
    check_cmdline
    setup_timezone
    install_nodered
    deploy_nodered_files
    setup_systemd_units
    setup_firewall
    setup_tailscale
    setup_kiosk
    setup_influxdb
    setup_grafana
    setup_heartbeat
    finish
}

main "$@"
