#!/bin/bash
WALLDIR="$HOME/Pictures/wallpapers"
MON1="DP-3"
MON2="HDMI-A-1"

while true; do
    WALL1=$(find "$WALLDIR" -type f | shuf -n 1)
    WALL2=$(find "$WALLDIR" -type f | shuf -n 1)

    hyprctl hyprpaper unload all
    hyprctl hyprpaper preload "$WALL1"
    hyprctl hyprpaper preload "$WALL2"

    # Short pause to let preloads finish
    sleep 0.3

    hyprctl hyprpaper wallpaper "$MON1,$WALL1"
    hyprctl hyprpaper wallpaper "$MON2,$WALL2"

    sleep 900  # 15 minutes
done
