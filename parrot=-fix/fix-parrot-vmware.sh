#!/usr/bin/env bash
# ==============================================================================
# All-In-One VMware Integration & Performance Fix for Parrot OS
# ==============================================================================
# Resolves:
#   1. Mouse auto-grab / ungrab (pointer trapping / release without Ctrl+Alt)
#   2. Bidirectional copy/paste (clipboard) for BOTH user and root sessions
#   3. Dynamic screen resolution & auto-fit guest display
#   4. Drag & drop file transfers (vmblock-fuse)
#   5. Desktop animation lag reduction (MATE, KDE, XFCE, GNOME)
#   6. Root GUI session persistence (LightDM/PAM compatibility)
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
echo "       Parrot OS VMware Complete Integration & Performance Fix"
echo "==================================================================="

# ---------------------------------------------------------------------------
# 1. Hypervisor Detection
# ---------------------------------------------------------------------------
log_info "Step 1: Checking hypervisor..."
VIRT_TYPE="$(systemd-detect-virt --vm 2>/dev/null || true)"
DMI_VENDOR="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)"

if [[ "$VIRT_TYPE" == "vmware" ]] || [[ "$DMI_VENDOR" =~ [Vv][Mm]ware ]]; then
  log_success "VMware hypervisor confirmed."
else
  log_warn "Hypervisor not explicitly detected as VMware (detected: ${VIRT_TYPE:-unknown})."
  log_warn "Proceeding with VMware open-vm-tools installation..."
fi

# ---------------------------------------------------------------------------
# 2. Package Installation & Dependencies
# ---------------------------------------------------------------------------
log_info "Step 2: Installing open-vm-tools and desktop integration drivers..."
apt-get update -qq

REQUIRED_PKGS=(
  open-vm-tools
  open-vm-tools-desktop
  fuse3
  x11-xserver-utils
  xclip
  xsel
  libinput-bin
)

DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${REQUIRED_PKGS[@]}"
log_success "All required VMware packages are installed."

# ---------------------------------------------------------------------------
# 3. System Daemon Configuration & FUSE Mount
# ---------------------------------------------------------------------------
log_info "Step 3: Configuring open-vm-tools system daemon..."
systemctl unmask open-vm-tools.service 2>/dev/null || true
systemctl enable open-vm-tools.service 2>/dev/null || true
systemctl restart open-vm-tools.service

# Setup vmblock-fuse filesystem for file drag-and-drop & clipboard
mkdir -p /run/vmblock-fuse
if ! grep -qs '/run/vmblock-fuse' /proc/mounts; then
  if command -v vmware-vmblock-fuse >/dev/null 2>&1; then
    vmware-vmblock-fuse -o subtype=vmware-vmblock,default_permissions,allow_other /run/vmblock-fuse 2>/dev/null || true
  fi
fi

if systemctl is-active --quiet open-vm-tools; then
  log_success "open-vm-tools system service is active."
else
  log_warn "open-vm-tools service warning. Check: journalctl -u open-vm-tools -n 20"
fi

# ---------------------------------------------------------------------------
# 4. Multi-Layer Autostart Persistence (Root + User Sessions)
# ---------------------------------------------------------------------------
log_info "Step 4: Installing autostart hooks across X11, XDG, and user profiles..."

# Layer A: Global X11 session hook (starts before window manager)
mkdir -p /etc/X11/Xsession.d
cat << 'EOF' > /etc/X11/Xsession.d/99vmware-user
if [ -x /usr/bin/vmware-user-suid-wrapper ]; then
    /usr/bin/vmware-user-suid-wrapper &
elif [ -x /usr/bin/vmtoolsd ]; then
    /usr/bin/vmtoolsd -n vmusr &
fi
EOF
chmod 644 /etc/X11/Xsession.d/99vmware-user

# Layer B: XDG Autostart desktop file
mkdir -p /etc/xdg/autostart
cat << 'EOF' > /etc/xdg/autostart/vmware-user.desktop
[Desktop Entry]
Type=Application
Encoding=UTF-8
Version=1.0
Name=VMware User Agent
Comment=Auto-ungrab mouse, bidirectional clipboard, and auto-screen resize
Exec=/usr/bin/vmware-user-suid-wrapper
Terminal=false
NoDisplay=true
X-GNOME-Autostart-Phase=Initialization
X-KDE-autostart-phase=1
EOF
chmod 644 /etc/xdg/autostart/vmware-user.desktop

# Layer C: Per-user autostart and .xsessionrc injection (Crucial for root logins!)
USER_HOMES=("/root")
while IFS=: read -r _ _ uid _ _ home shell; do
  if (( uid >= 1000 && uid <= 60000 )) && [[ -d "$home" ]] && [[ "$shell" != *"nologin"* ]]; then
    USER_HOMES+=("$home")
  fi
done < /etc/passwd

INJECTION_CMD='pgrep -f "vmtoolsd.*vmusr|vmware-user" >/dev/null || (/usr/bin/vmware-user-suid-wrapper 2>/dev/null || /usr/bin/vmtoolsd -n vmusr 2>/dev/null &)'

for u_home in "${USER_HOMES[@]}"; do
  mkdir -p "$u_home/.config/autostart"
  cp -f /etc/xdg/autostart/vmware-user.desktop "$u_home/.config/autostart/" 2>/dev/null || true

  if [[ -f "$u_home/.xsessionrc" ]]; then
    grep -qxF "$INJECTION_CMD" "$u_home/.xsessionrc" 2>/dev/null || echo "$INJECTION_CMD" >> "$u_home/.xsessionrc"
  else
    echo "$INJECTION_CMD" > "$u_home/.xsessionrc"
  fi
  chown -R "$(stat -c '%u:%g' "$u_home")" "$u_home/.xsessionrc" "$u_home/.config" 2>/dev/null || true
done
log_success "Autostart persistence configured across X11, XDG, and user profiles."

# ---------------------------------------------------------------------------
# 5. Ensure Root GUI Login Support (LightDM & PAM)
# ---------------------------------------------------------------------------
log_info "Step 5: Ensuring LightDM and PAM permit root GUI logins..."
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
# 6. Quick Clipboard & Integration Fix Utility
# ---------------------------------------------------------------------------
cat << 'EOF' > /usr/local/bin/fix-vmware-clipboard
#!/usr/bin/env bash
echo "[*] Restarting VMware user agent daemons..."
pkill -f "vmtoolsd.*vmusr" 2>/dev/null || true
pkill -f "vmware-user-suid-wrapper" 2>/dev/null || true
sleep 1
if [ -x /usr/bin/vmware-user-suid-wrapper ]; then
  /usr/bin/vmware-user-suid-wrapper &
elif [ -x /usr/bin/vmtoolsd ]; then
  /usr/bin/vmtoolsd -n vmusr &
fi
echo "[+] VMware clipboard and mouse integration restarted!"
EOF
chmod +x /usr/local/bin/fix-vmware-clipboard
log_success "Created emergency helper command: 'fix-vmware-clipboard'"

# ---------------------------------------------------------------------------
# 6. Desktop Animation & Performance Optimization (Smooth Rendering)
# ---------------------------------------------------------------------------
log_info "Step 5: Optimizing desktop effects for VM performance..."

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
log_success "Desktop rendering optimized for VMware."

# ---------------------------------------------------------------------------
# 7. Live Runtime Daemon Attachment & Diagnostic Verification
# ---------------------------------------------------------------------------
log_info "Step 6: Attaching live session agent..."
ACTIVE_DISPLAY="$(ls /tmp/.X11-unix/X* 2>/dev/null | head -n1 | sed 's|/tmp/.X11-unix/X|:|' || true)"
export DISPLAY="${ACTIVE_DISPLAY:-:0}"

if [ -x /usr/bin/vmware-user-suid-wrapper ]; then
  /usr/bin/vmware-user-suid-wrapper 2>/dev/null || true
elif [ -x /usr/bin/vmtoolsd ]; then
  /usr/bin/vmtoolsd -n vmusr 2>/dev/null || true
fi

sleep 1

echo ""
echo "--- Runtime Verification ---"
if pgrep -f "vmusr|vmware-user" >/dev/null 2>&1; then
  log_success "Guest session agent (vmusr): ACTIVE"
else
  log_warn "Guest session agent (vmusr): Not attached to current shell (will start on desktop login/reboot)."
fi

if systemctl is-active --quiet open-vm-tools; then
  log_success "System background service (vmtoolsd): ACTIVE"
fi

# ---------------------------------------------------------------------------
# Summary & Host Reminders
# ---------------------------------------------------------------------------
echo ""
echo "==================================================================="
log_success "VMware Integration Complete!"
echo "==================================================================="
echo ""
echo "IMPORTANT: In VMware Workstation / Player settings for this VM:"
echo "  1. VM Settings -> Options -> Guest Isolation -> Check 'Enable drag and drop'"
echo "  2. VM Settings -> Options -> Guest Isolation -> Check 'Enable copy and paste'"
echo "  3. View Menu -> Autofit Guest (makes screen resize automatically)"
echo ""
echo "TIP: If clipboard ever stops syncing in the future, run: fix-vmware-clipboard"
echo "TIP: In terminal, paste with Ctrl+Shift+V or Right-Click -> Paste"
echo ""

read -r -p "Reboot VM now to initialize all changes? [y/N]: " choice
case "$choice" in
  y|Y|yes|YES)
    log_info "Rebooting..."
    reboot
    ;;
  *)
    log_info "All configurations applied! Please reboot the VM when convenient."
    ;;
esac
