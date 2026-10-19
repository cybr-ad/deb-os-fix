#!/bin/bash

# ==============================================================================
# Kali Linux (XFCE) - Minimal GUI Script
# Disables animations, compositing, and transparency effects only.
# Run as your normal desktop user, NOT with sudo/root.
# ==============================================================================

echo "Starting GUI minimization..."

# 1. Disable compositor: removes shadows, true transparency, most effects
xfconf-query -c xfwm4 -p /general/use_compositing -s false

# 2. Disable window move/resize wireframe animations
xfconf-query -c xfwm4 -p /general/box_move -s false
xfconf-query -c xfwm4 -p /general/box_resize -s false

# 3. Force opaque windows: no transparency at all
xfconf-query -c xfwm4 -p /general/frame_opacity -s 100
xfconf-query -c xfwm4 -p /general/inactive_opacity -s 100
xfconf-query -c xfwm4 -p /general/move_opacity -s 100

# 4. Disable panel autohide animation
xfconf-query -c xfce4-panel -p /panels/panel-1/popdown-speed -s 0

echo "Done: animations, compositing, and transparency disabled."
echo "Desktop icons were NOT changed."
echo "Log out and log back in, or reboot, for full effect."