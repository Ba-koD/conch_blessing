#!/usr/bin/env sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
MOD_DIR="$SCRIPT_DIR"
MOD_NAME="conch_blessing"
SAVE_SLOT=1
INTERVAL_MS=350
DEBOUNCE_MS=450
ALSO_RESTART=0

usage() {
  cat <<'EOF'
Usage: ./watch.sh [options]

Options:
  --mod-dir <path>      Target mod directory (default: script directory)
  --mod-name <name>     Name used in `luamod <name>` (default: conch_blessing)
  --save-slot <1|2|3>   Save slot used by this mod (default: 1)
  --interval <seconds>  Poll interval in seconds (default: 0.35)
  --debounce <seconds>  Debounce time in seconds (default: 0.45)
  --also-restart        Enqueue `restart` after `luamod`
  -h, --help            Show this help
EOF
}

sec_to_ms() {
  awk -v s="$1" 'BEGIN { printf "%d\n", (s * 1000) }'
}

sanitize_line() {
  # Queue line format is single-line; normalize newlines and separators.
  printf '%s' "$1" | tr '\r\n|' '   '
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --mod-dir)
      [ "$#" -ge 2 ] || { echo "Missing value for --mod-dir" >&2; exit 1; }
      MOD_DIR="$2"
      shift 2
      ;;
    --mod-name)
      [ "$#" -ge 2 ] || { echo "Missing value for --mod-name" >&2; exit 1; }
      MOD_NAME="$2"
      shift 2
      ;;
    --save-slot)
      [ "$#" -ge 2 ] || { echo "Missing value for --save-slot" >&2; exit 1; }
      SAVE_SLOT="$2"
      shift 2
      ;;
    --interval)
      [ "$#" -ge 2 ] || { echo "Missing value for --interval" >&2; exit 1; }
      INTERVAL_MS="$(sec_to_ms "$2")"
      shift 2
      ;;
    --debounce)
      [ "$#" -ge 2 ] || { echo "Missing value for --debounce" >&2; exit 1; }
      DEBOUNCE_MS="$(sec_to_ms "$2")"
      shift 2
      ;;
    --also-restart)
      ALSO_RESTART=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

case "$SAVE_SLOT" in
  1|2|3) ;;
  *) echo "--save-slot must be 1, 2, or 3" >&2; exit 1 ;;
esac

MOD_DIR="$(cd "$MOD_DIR" && pwd)"
MODS_DIR="$(dirname "$MOD_DIR")"
DATA_DIR="$(dirname "$MODS_DIR")/data"
QUEUE_DIR="$DATA_DIR/$MOD_NAME"
QUEUE_FILE="$QUEUE_DIR/save${SAVE_SLOT}.dat"
QUEUE_PREFIX="__CBQ__"

mkdir -p "$QUEUE_DIR"
if [ ! -s "$QUEUE_FILE" ]; then
  printf '{}\n' > "$QUEUE_FILE"
fi

snapshot_hash() {
  files="$(
    find "$MOD_DIR" \
      -type f \
      \( -name '*.lua' -o -name '*.xml' \) \
      ! -path '*/.git/*' \
      -exec stat -c '%n|%Y|%s' {} + 2>/dev/null || true
  )"
  if [ -z "$files" ]; then
    printf '%s' "empty" | sha1sum | awk '{print $1}'
  else
    printf '%s\n' "$files" | LC_ALL=C sort | sha1sum | awk '{print $1}'
  fi
}

enqueue_reload() {
  safe_mod_name="$(sanitize_line "$MOD_NAME")"
  tmp="$QUEUE_FILE.tmp.$$"

  {
    if [ -f "$QUEUE_FILE" ]; then
      cat "$QUEUE_FILE"
    else
      printf '{}\n'
    fi
    printf '\n%sMSG|Lua change detected.\n' "$QUEUE_PREFIX"
    printf '%sCMD|luamod %s\n' "$QUEUE_PREFIX" "$safe_mod_name"
    printf '%sMSG|Reloaded mod: %s\n' "$QUEUE_PREFIX" "$safe_mod_name"
    if [ "$ALSO_RESTART" -eq 1 ]; then
      printf '%sCMD|restart\n' "$QUEUE_PREFIX"
    fi
  } > "$tmp"

  mv "$tmp" "$QUEUE_FILE"
}

stop() {
  printf '\n[watch] stopped.\n'
  exit 0
}

trap stop INT TERM

printf '[watch] mod dir   : %s\n' "$MOD_DIR"
printf '[watch] mod name  : %s\n' "$MOD_NAME"
printf '[watch] save slot : %s\n' "$SAVE_SLOT"
printf '[watch] queue file: %s\n' "$QUEUE_FILE"
printf '[watch] ext       : .lua, .xml\n'
printf '[watch] started. Press Ctrl+C to stop.\n'

last_hash="$(snapshot_hash)"
pending=0
changed_at_ms=0

while :; do
  now_hash="$(snapshot_hash)"
  now_ms="$(date +%s%3N)"

  if [ "$now_hash" != "$last_hash" ]; then
    pending=1
    changed_at_ms="$now_ms"
    last_hash="$now_hash"
  fi

  if [ "$pending" -eq 1 ]; then
    elapsed_ms=$((now_ms - changed_at_ms))
    if [ "$elapsed_ms" -ge "$DEBOUNCE_MS" ]; then
      enqueue_reload
      printf '[watch] reloaded\n'
      pending=0
    fi
  fi

  sleep "$(awk -v ms="$INTERVAL_MS" 'BEGIN { printf "%.3f\n", (ms / 1000) }')"
done
