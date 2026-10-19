#!/usr/bin/env bash
# Enable direct root GUI login for LightDM on Parrot OS / Debian
set -Eeuo pipefail

if [[ "$EUID" -ne 0 ]]; then
  echo "[-] This script must be run as root. Run with: sudo $0" >&2
  exit 1
fi

echo "[*] Setting password for the root user..."
passwd root

echo "[*] Configuring LightDM for manual user entry..."
mkdir -p /etc/lightdm/lightdm.conf.d
cat << 'EOF' > /etc/lightdm/lightdm.conf.d/50-root-login.conf
[Seat:*]
greeter-show-manual-login=true
greeter-hide-users=false
allow-user-switching=true
EOF

echo "[*] Updating PAM configuration to permit root desktop sessions..."
if [[ -f /etc/pam.d/lightdm ]]; then
  sed -i 's/^auth.*pam_succeed_if.so user != root.*/#&/' /etc/pam.d/lightdm
fi

if [[ -f /etc/pam.d/lightdm-greeter ]]; then
  sed -i 's/^auth.*pam_succeed_if.so user != root.*/#&/' /etc/pam.d/lightdm-greeter
fi

echo "[+] Configuration applied successfully."
read -r -p "Restart LightDM now to apply changes? (This will close your current session) [y/N]: " choice
case "$choice" in
  y|Y|yes|YES)
    systemctl restart lightdm
    ;;
  *)
    echo "[*] Changes saved. Reboot or run 'sudo systemctl restart lightdm' manually."
    ;;
esac