#!/usr/bin/env bash
# ==============================================================================
# All-In-One VirtualBox Integration & Performance Fix for Parrot OS
# ==============================================================================
# Resolves:
#   1. Mouse auto-grab / ungrab (seamless mouse pointer integration)
#   2. Bidirectional copy/paste (shared clipboard) for BOTH user and root sessions
#   3. Dynamic screen resolution & auto-resizing guest display
#   4. Drag & drop support
#   5. Shared folder access permissions (vboxsf group)
#   6. Desktop animation lag reduction (MATE, KDE, XFCE, GNOME)
#   7. Root GUI session persistence (LightDM/PAM compatibility)
# ==============================================================================

set -Eeuo pipefail

log_info()    { echo -e "\e[34m[*] $*\e[0m"; }
log_success() { echo -e "\e[32m[+] $*\e[0m"; }
log_warn()    { echo -e "\e[33m[!] $*\e[0m"; }
log_error()   { echo -e "\e[31m[-] $*\e[0m" >&2; }

if [[ "$EUID" -ne 0 ]]; then
  log_error "This script must be run as root. Run with: sudo bash $0"
  exit 1
fi

echo "==================================================================="
echo "     Parrot OS VirtualBox Complete Integration & Performance Fix"
echo "==================================================================="

# ---------------------------------------------------------------------------
# 1. Hypervisor Detection
# ---------------------------------------------------------------------------
log_info "Step 1: Checking hypervisor..."
VIRT_TYPE="$(systemd-detect-virt --vm 2>/dev/null || true)"
DMI_INFO="$(cat /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/product_name 2>/dev/null || true)"

if [[ "$VIRT_TYPE" =~ (oracle|virtualbox) ]] || [[ "$DMI_INFO" =~ [Vv]irtual[Bb]ox|[Ii]nnotek ]]; then
  log_success "VirtualBox hypervisor verified."
else
  log_warn "Hypervisor not explicitly detected as VirtualBox (detected: ${VIRT_TYPE:-unknown})."
  log_warn "Proceeding with VirtualBox guest integrations installation..."
fi

# ---------------------------------------------------------------------------
# 2. Package Installation & Kernel Headers
# ---------------------------------------------------------------------------
log_info "Step 2: Installing VirtualBox Guest Additions and required drivers..."
apt-get update -qq

KERNEL_VER="$(uname -r)"
REQUIRED_PKGS=(
  build-essential
  dkms
  virtualbox-guest-x11
  virtualbox-guest-utils
  xclip
  xsel
  x11-xserver-utils
)

log_info "Installing kernel headers and Guest Additions packages..."
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  "linux-headers-${KERNEL_VER}" 2>/dev/null || \
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends linux-headers-amd64 || true

DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${REQUIRED_PKGS[@]}"
log_success "All required VirtualBox packages are installed."

# ---------------------------------------------------------------------------
# 3. System Daemon Configuration
# ---------------------------------------------------------------------------
log_info "Step 3: Enabling VirtualBox guest system services..."
systemctl unmask virtualbox-guest-utils.service 2>/dev/null || true
systemctl enable virtualbox-guest-utils.service 2>/dev/null || true
systemctl restart virtualbox-guest-utils.service 2>/dev/null || true
log_success "virtualbox-guest-utils service is enabled."

# ---------------------------------------------------------------------------
# 4. User Group Permissions (vboxsf for Shared Folders)
# ---------------------------------------------------------------------------
log_info "Step 4: Granting shared folder access permissions (vboxsf)..."
groupadd -f vboxsf
usermod -aG vboxsf root

while IFS=: read -r username _ uid _ _ home shell; do
  if (( uid >= 1000 && uid <= 60000 )) && [[ -d "$home" ]] && [[ "$shell" != *"nologin"* ]]; then
    usermod -aG vboxsf "$username" 2>/dev/null || true
    log_info "  -> Added user '$username' to vboxsf group"
  fi
done < /etc/passwd

# ---------------------------------------------------------------------------
# 5. Multi-Layer Autostart Persistence (Root + User Sessions)
# ---------------------------------------------------------------------------
log_info "Step 5: Configuring persistent autostart hooks for VBoxClient..."

# Layer A: Global X11 session hook (starts early before desktop manager)
mkdir -p /etc/X11/Xsession.d
cat << 'EOF' > /etc/X11/Xsession.d/98vboxclient
if [ -x /usr/bin/VBoxClient-all ]; then
    /usr/bin/VBoxClient-all &
elif [ -x /usr/bin/VBoxClient ]; then
    /usr/bin/VBoxClient --clipboard &
    /usr/bin/VBoxClient --checkhostversion &
    /usr/bin/VBoxClient --seamless &
    /usr/bin/VBoxClient --draganddrop &
    /usr/bin/VBoxClient --vmsvga 2>/dev/null || /usr/bin/VBoxClient --display 2>/dev/null &
fi
EOF
chmod 644 /etc/X11/Xsession.d/98vboxclient

# Layer B: XDG Autostart desktop file (for root & standard users)
mkdir -p /etc/xdg/autostart
cat << 'EOF' > /etc/xdg/autostart/vboxclient.desktop
[Desktop Entry]
Type=Application
Encoding=UTF-8
Version=1.0
Name=VirtualBox Guest Services
Comment=Starts VirtualBox guest clipboard, mouse integration, and screen auto-resize
Exec=/usr/bin/VBoxClient-all
Terminal=false
NoDisplay=true
X-GNOME-Autostart-Phase=Initialization
X-KDE-autostart-phase=1
EOF
chmod 644 /etc/xdg/autostart/vboxclient.desktop

# Layer C: Per-user autostart and .xsessionrc fallback injection (Crucial for root logins!)
USER_HOMES=("/root")
while IFS=: read -r _ _ uid _ _ home shell; do
  if (( uid >= 1000 && uid <= 60000 )) && [[ -d "$home" ]] && [[ "$shell" != *"nologin"* ]]; then
    USER_HOMES+=("$home")
  fi
done < /etc/passwd

INJECTION_CMD='pgrep -f "VBoxClient.*clipboard" >/dev/null || (/usr/bin/VBoxClient-all 2>/dev/null || (/usr/bin/VBoxClient --clipboard & /usr/bin/VBoxClient --vmsvga 2>/dev/null &))'

for u_home in "${USER_HOMES[@]}"; do
  mkdir -p "$u_home/.config/autostart"
  cp -f /etc/xdg/autostart/vboxclient.desktop "$u_home/.config/autostart/" 2>/dev/null || true
  
  if [[ -f "$u_home/.xsessionrc" ]]; then
    grep -qxF "$INJECTION_CMD" "$u_home/.xsessionrc" 2>/dev/null || echo "$INJECTION_CMD" >> "$u_home/.xsessionrc"
  else
    echo "$INJECTION_CMD" > "$u_home/.xsessionrc"
  fi
  chown -R "$(stat -c '%u:%g' "$u_home")" "$u_home/.xsessionrc" "$u_home/.config" 2>/dev/null || true
done
log_success "Autostart persistence configured across X11, XDG, and user profiles."

# ---------------------------------------------------------------------------
# 6. Ensure Root GUI Login Support (LightDM & PAM)
# ---------------------------------------------------------------------------
log_info "Step 6: Ensuring LightDM and PAM permit root GUI logins..."
if [[ -d /etc/lightdm ]]; then
  mkdir -p /etc/lightdm/lightdm.conf.d
  cat << 'EOF' > /etc/lightdm/lightdm.conf.d/50-root-login.conf
[Seat:*]
greeter-show-manual-login=true
greeter-hide-users=false
allow-user-switching=true
EOF
  if [[ -f /etc/pam.d/lightdm ]]; then
    sed -i 's/^auth.*pam_succeed_if.so user != root.*/#&/' /etc/pam.d/lightdm
  fi
  if [[ -f /etc/pam.d/lightdm-greeter ]]; then
    sed -i 's/^auth.*pam_succeed_if.so user != root.*/#&/' /etc/pam.d/lightdm-greeter
  fi
  log_success "LightDM and PAM configured for root desktop access."
fi

# ---------------------------------------------------------------------------
# 7. Quick Clipboard & Display Fix Utility
# ---------------------------------------------------------------------------
cat << 'EOF' > /usr/local/bin/fix-vbox-clipboard
#!/usr/bin/env bash
echo "[*] Restarting VirtualBox guest daemons..."
killall VBoxClient 2>/dev/null || true
sleep 1
if command -v VBoxClient-all >/dev/null 2>&1; then
  VBoxClient-all &
else
  VBoxClient --clipboard &
  VBoxClient --checkhostversion &
  VBoxClient --seamless &
  VBoxClient --draganddrop &
  VBoxClient --vmsvga 2>/dev/null || VBoxClient --display 2>/dev/null &
fi
echo "[+] VirtualBox clipboard & integration restarted!"
EOF
chmod +x /usr/local/bin/fix-vbox-clipboard
log_success "Created emergency helper command: 'fix-vbox-clipboard'"

# ---------------------------------------------------------------------------
# 7. Desktop Animation & Performance Optimization (Prevent VM Stutter)
# ---------------------------------------------------------------------------
log_info "Step 6: Optimizing desktop effects for VM performance..."

# MATE Desktop (Default in Parrot OS)
if command -v gsettings >/dev/null 2>&1; then
  gsettings set org.mate.interface enable-animations false 2>/dev/null || true
  gsettings set org.mate.Marco.general compositing-manager false 2>/dev/null || true
  gsettings set org.gnome.desktop.interface enable-animations false 2>/dev/null || true
fi

# XFCE
if command -v xfconf-query >/dev/null 2>&1; then
  xfconf-query -c xfwm4 -p /general/use_compositing -s false 2>/dev/null || true
fi

# KDE Plasma
if command -v kwriteconfig6 >/dev/null 2>&1; then
  kwriteconfig6 --file kdeglobals --group KDE --key AnimationDurationFactor 0 2>/dev/null || true
elif command -v kwriteconfig5 >/dev/null 2>&1; then
  kwriteconfig5 --file kdeglobals --group KDE --key AnimationDurationFactor 0 2>/dev/null || true
fi
log_success "Desktop rendering optimized for VirtualBox."

# ---------------------------------------------------------------------------
# 8. Live Runtime Daemon Attachment
# ---------------------------------------------------------------------------
log_info "Step 7: Activating VBoxClient daemons for the current session..."
ACTIVE_DISPLAY="$(ls /tmp/.X11-unix/X* 2>/dev/null | head -n1 | sed 's|/tmp/.X11-unix/X|:|' || true)"
export DISPLAY="${ACTIVE_DISPLAY:-:0}"

if command -v VBoxClient-all >/dev/null 2>&1; then
  VBoxClient-all 2>/dev/null || true
fi

if ! pgrep -f "VBoxClient.*clipboard" >/dev/null 2>&1; then
  VBoxClient --clipboard 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Summary & Host Reminders
# ---------------------------------------------------------------------------
echo ""
echo "==================================================================="
log_success "VirtualBox Integration Complete!"
echo "==================================================================="
echo ""
echo "IMPORTANT: In the VirtualBox host window menu, ensure:"
echo "  1. Devices -> Shared Clipboard -> Select 'Bidirectional'"
echo "  2. Devices -> Drag and Drop   -> Select 'Bidirectional'"
echo "  3. Input   -> Mouse Integration -> Make sure it is CHECKED"
echo "  4. View    -> Auto-resize Guest Display -> CHECKED"
echo ""
echo "TIP: If clipboard ever stops syncing in the future, run: fix-vbox-clipboard"
echo "TIP: In terminal, paste with Ctrl+Shift+V or Right-Click -> Paste"
echo ""

read -r -p "Reboot VM now to initialize all kernel modules and drivers? [y/N]: " choice
case "$choice" in
  y|Y|yes|YES)
    log_info "Rebooting..."
    reboot
    ;;
  *)
    log_info "All configurations applied! Please reboot the VM when convenient."
    ;;
esac
