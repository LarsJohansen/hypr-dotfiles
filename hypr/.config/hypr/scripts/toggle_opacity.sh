
#!/bin/bash

TRANSPARENT=0.8
OPAQUE=1.0
STATE_DIR="/tmp/hypr-opacity-toggle"
mkdir -p "$STATE_DIR"

# Get active window class
CLASS=$(hyprctl activewindow -j | jq -r '.class')
STATE_FILE="$STATE_DIR/$CLASS"

if [[ -f "$STATE_FILE" ]]; then
  hyprctl keyword windowrule "opacity $OPAQUE,class:^($CLASS)$"
  rm "$STATE_FILE"
else
  hyprctl keyword windowrule "opacity $TRANSPARENT,class:^($CLASS)$"
  touch "$STATE_FILE"
fi
