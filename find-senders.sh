#!/usr/bin/env bash
# find-senders.sh
# Lists all unique sender email addresses, with optional age filter.
#
# Usage:
#   ./find-senders.sh                  # all senders in inbox/sent/labels
#   ./find-senders.sh --years 10       # senders of emails older than 10 years
#   ./find-senders.sh --all            # include trash, spam, drafts, all folders
#   ./find-senders.sh --all --years 5  # older than 5 years, all folders
#   ./find-senders.sh --count          # show email count per sender (sorted)
#   ./find-senders.sh --parallel 20    # number of parallel API requests (default: 10)

set -euo pipefail

# ── Defaults ────────────────────────────────────────────────────────────────
YEARS=""
YEARS_SET=false
ALL=false
COUNT=false
PARALLEL=10

# ── Argument parsing ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --years)    YEARS="$2"; YEARS_SET=true; shift 2 ;;
    --all)      ALL=true; shift ;;
    --count)    COUNT=true; shift ;;
    --parallel) PARALLEL="$2"; shift 2 ;;
    *) echo "Unknown flag: $1"; exit 1 ;;
  esac
done

# ── Build search query ───────────────────────────────────────────────────────
QUERY=""
if [[ "$YEARS_SET" == "true" ]]; then
  CUTOFF=$(date -d "$YEARS years ago" +%Y/%m/%d)
  QUERY="before:$CUTOFF"
fi
[[ "$ALL" == "true" ]] && QUERY="${QUERY:+$QUERY }in:anywhere"

# ── Fetch all message IDs ────────────────────────────────────────────────────
PARAMS="{\"userId\": \"me\", \"maxResults\": 500"
[[ -n "$QUERY" ]] && PARAMS="$PARAMS, \"q\": \"$QUERY\""
PARAMS="$PARAMS}"

>&2 echo "Fetching message IDs..."
IDS=$(
  gws gmail users messages list \
    --page-all \
    --page-limit 1000 \
    --params "$PARAMS" \
    2>/dev/null \
  | jq -r '.messages[]?.id' 2>/dev/null
)

TOTAL=$(echo "$IDS" | grep -c . || true)

if [[ $TOTAL -eq 0 ]]; then
  echo "No emails found."
  exit 0
fi

>&2 echo "Found $TOTAL emails. Fetching sender headers (parallel=$PARALLEL)..."

# ── Fetch From header for each message in parallel ───────────────────────────
fetch_sender() {
  local id="$1"
  gws gmail users messages get \
    --params "{\"userId\": \"me\", \"id\": \"$id\", \"format\": \"metadata\", \"metadataHeaders\": \"From\"}" \
    2>/dev/null \
  | jq -r '.payload.headers[]? | select(.name == "From") | .value' 2>/dev/null
}

export -f fetch_sender

SENDERS=$(echo "$IDS" | xargs -P "$PARALLEL" -I{} bash -c 'fetch_sender "$@"' _ {})

# ── Extract email addresses and deduplicate ───────────────────────────────────
# Handle both "Name <email>" and bare "email" formats
EMAILS=$(echo "$SENDERS" | grep -oP '<\K[^>]+' || echo "$SENDERS" | grep -oP '\S+@\S+')

if [[ "$COUNT" == "true" ]]; then
  echo "$EMAILS" | tr '[:upper:]' '[:lower:]' | sort | uniq -c | sort -rn | awk '{print $1, $2}'
else
  echo "$EMAILS" | tr '[:upper:]' '[:lower:]' | sort -u
fi
