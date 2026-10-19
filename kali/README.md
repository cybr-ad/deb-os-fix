# Kali XFCE Minimal GUI

A lightweight script that strips unnecessary visual effects from Kali Linux's default XFCE desktop. It turns off animations, transparency, and the compositor to give you a fast, responsive GUI for essential work—especially useful on VMs or older hardware.

---

## What It Does

* **Disables the compositor:** Removes drop shadows, fade effects, and true transparency.
* **Disables window wireframe animations:** Stops box animations when moving or resizing windows.
* **Forces 100% window opacity:** Makes active, inactive, and moving windows completely solid.
* **Removes panel animations:** Sets the panel auto-hide popdown speed to instant (`0`).

> **Note:** Your desktop icons, themes, fonts, panels, and personal files are **not** modified.

---

## Requirements

* Kali Linux (or any Linux distribution running the **XFCE 4** desktop environment).
* Standard user account (do **not** run with `sudo` or as `root`).

---

## Quick Start

1. **Clone the repository:**
   ```bash
   git clone https://github.com/<your-username>/kali-xfce-minimal-gui.git
   cd kali-xfce-minimal-gui
   ```

2. **Make the script executable:**
   ```bash
   chmod +x kali-visual-effect-remove.sh
   ```

3. **Run the script (without `sudo`):**
   ```bash
   ./kali-visual-effect-remove.sh
   ```

4. **Apply changes:**
   Log out and log back in (or reboot) for all changes to take full effect.

---

## How to Undo / Restore Defaults

Because this script only updates per-user `xfconf` settings, you can revert the changes at any time using one of these methods:

### Option 1: Revert Only Script Changes (Recommended)
Run these commands in your terminal to turn the compositor and default animations back on:
```bash
xfconf-query -c xfwm4 -p /general/use_compositing -s true
xfconf-query -c xfce4-panel -p /panels/panel-1/popdown-speed -R
```
*(You can also adjust these manually in **Settings → Window Manager** and **Settings → Window Manager Tweaks**).*

### Option 2: Full XFCE Reset
To reset your entire XFCE desktop back to factory defaults (including panels and themes), back up your current config folder and log out:
```bash
mv ~/.config/xfce4 ~/.config/xfce4.bak
```
When you log back in, XFCE will generate a fresh default configuration.