#!/bin/bash

# bash tests/cli.test.sh
#
# Exercises the parts of bin/screensaver-manager that do not need a running
# Hyprland: config, effects, custom commands and the menu/CLI integration. It
# runs against a throwaway HOME, so nothing of the real user's is touched.

set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CLI="$ROOT/bin/screensaver-manager"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export XDG_CONFIG_HOME="$HOME/.config"
export SSM_FROM_PANEL=1
unset SSM_CONFIG
mkdir -p "$HOME"

pass=0
fail=0

check() {
  local name=$1
  shift
  if "$@"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $name" >&2
  fi
}

refute() {
  local name=$1
  shift
  if "$@"; then
    fail=$((fail + 1))
    echo "FAIL: $name" >&2
  else
    pass=$((pass + 1))
  fi
}

json() { "$CLI" status --json | jq -r "$1"; }
config() { jq -r "$1" "$XDG_CONFIG_HOME/omarchy/screensaver-manager.json"; }

# Defaults: the stock screensaver, nothing managed.
check "default selection" [ "$(json .selected)" = omarchy ]
refute "stock setup is not managed" "$CLI" managed
check "effects come from ttfx" [ "$(json .effectsTotal)" -gt 10 ]
check "all effects on by default" [ "$(json .effectsEnabled)" = "$(json .effectsTotal)" ]

# Effects.
"$CLI" effects off matrix beams
check "effects off" [ "$(config '.disabledEffects | join(",")')" = "beams,matrix" ]
check "a disabled effect makes it managed" "$CLI" managed
"$CLI" effects toggle beams
check "effects toggle" [ "$(config '.disabledEffects | join(",")')" = "matrix" ]
"$CLI" effects only wipe
check "effects only" [ "$(json .effectsEnabled)" = 1 ]
check "the one left is wipe" [ "$("$CLI" effects --json | jq -r 'map(select(.enabled)) | .[0].name')" = wipe ]
"$CLI" effects none
check "effects none leaves one on" [ "$(json .effectsEnabled)" = 1 ]
"$CLI" effects all
check "effects all" [ "$(json .effectsEnabled)" = "$(json .effectsTotal)" ]
refute "unknown effect is refused" "$CLI" effects off not-an-effect 2>/dev/null

# Frame rate.
"$CLI" framerate 60
check "frame rate" [ "$(json .frameRate)" = 60 ]
check "frame rate makes it managed" "$CLI" managed
refute "silly frame rate is refused" "$CLI" framerate 5000 2>/dev/null
"$CLI" framerate 120

# Custom commands.
id=$("$CLI" custom add "Big Clock" "tty-clock -c")
check "custom add returns its id" [ "$id" = "custom:big-clock" ]
id2=$("$CLI" custom add "Big Clock" "tty-clock -s")
check "custom ids stay unique" [ "$id2" = "custom:big-clock-2" ]
"$CLI" select custom:big-clock
check "select custom" [ "$(json .selected)" = custom:big-clock ]
check "custom selection is managed" "$CLI" managed
"$CLI" custom remove big-clock
check "removing the selected custom falls back to omarchy" [ "$(json .selected)" = omarchy ]
check "only the other custom is left" [ "$(config '.custom | map(.id) | join(",")')" = "big-clock-2" ]

# Selection rules.
refute "unknown saver is refused" "$CLI" select nope 2>/dev/null
missing=$("$CLI" list --json | jq -r 'map(select(.installed | not)) | .[0].id // empty')
if [[ -n $missing ]]; then
  refute "uninstalled saver is refused" "$CLI" select "$missing" 2>/dev/null
fi

# A broken config file reads as defaults rather than failing.
echo "not json" >"$XDG_CONFIG_HOME/omarchy/screensaver-manager.json"
check "broken config reads as defaults" [ "$(json .selected)" = omarchy ]

# Omarchy menu entries go in and come out cleanly, keeping the user's own.
menu="$XDG_CONFIG_HOME/omarchy/extensions/omarchy-menu.jsonc"
mkdir -p "$(dirname "$menu")"
printf '{\n  // mine\n  "personal": {"icon":"x","label":"Personal"},\n}\n' >"$menu"
before=$(cat "$menu")
"$CLI" menu install >/dev/null
check "menu installed" [ "$(json .menuInstalled)" = true ]
check "menu file is still valid JSONC" bash -c "sed 's|^ *//.*||' '$menu' | tr -d '\n' | sed 's/,\s*}/}/g' | jq -e . >/dev/null"
check "menu keeps the user's rows" grep -q '"personal"' "$menu"
"$CLI" menu install >/dev/null
check "menu install is idempotent" [ "$(grep -c screensaver-manager "$menu")" -le 4 ]
"$CLI" menu remove >/dev/null
check "menu removal restores the file" [ "$(cat "$menu")" = "$before" ]

# The CLI wrapper.
"$CLI" cli install >/dev/null
check "cli installed" [ -x "$HOME/.local/bin/screensaver-manager" ]
check "cli reported" [ "$(json .cliInstalled)" = true ]
"$CLI" cli remove >/dev/null
check "cli removed" [ ! -e "$HOME/.local/bin/screensaver-manager" ]
echo "#!/bin/bash" >"$HOME/.local/bin/screensaver-manager"
refute "cli install leaves a stranger's file alone" "$CLI" cli install 2>/dev/null

echo "cli tests: $pass passed, $fail failed"
((fail == 0))
