
#!/bin/bash

TRANSPARENT=0.8
OPAQUE=1.0
STATE_DIR="/tmp/hypr-opacity-toggle"
mkdir -p "$STATE_DIR"

# Get active window class
CLASS=$(hyprctl activewindow -j | jq -r '.class')
STATE_FILE="$STATE_DIR/$CLASS"

if [[ -f "$STATE_FILE" ]]; then
  echo "Toggling opacity to $OPAQUE for $CLASS"
  notify-send "Opacity" "Toggling opacity to $OPAQUE for $CLASS"
  hyprctl keyword windowrule "opacity $OPAQUE override 0.85 override,class:^($CLASS)$"
  rm "$STATE_FILE"
else
  echo "Toggling opacity to $TRANSPARENT for $CLASS"
  notify-send "Opacity" "Toggling opacity to $TRANSPARENT for $CLASS"
  hyprctl keyword windowrule "opacity $TRANSPARENT override,class:^($CLASS)$"
  touch "$STATE_FILE"
fi
