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
    --help|-h)
      cat <<'EOF'
Usage: find-senders.sh [OPTIONS]

List unique sender email addresses from Gmail messages.

Options:
  --years N      Only include emails older than N years
  --all          Include all folders (trash, spam, drafts, labels)
  --count        Show occurrence count per sender, sorted by frequency
  --parallel N   Number of parallel API requests (default: 10)
  --help, -h     Show this help message

Examples:
  ./find-senders.sh                        # unique senders in inbox/sent/labels
  ./find-senders.sh --count                # senders ranked by email count
  ./find-senders.sh --years 5 --all        # senders of emails >5 years old, all folders
  ./find-senders.sh --count --parallel 20  # faster fetching with 20 parallel requests
EOF
      exit 0 ;;
    *) echo "Unknown flag: $1"; exit 1 ;;
  esac
done

if [[ ! "$PARALLEL" =~ ^[1-9][0-9]*$ ]]; then
  echo "Error: --parallel requires a positive integer (got: '$PARALLEL')"
  exit 1
fi

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
[[ "$ALL" == "true" ]] && PARAMS="$PARAMS, \"includeSpamTrash\": true"
PARAMS="$PARAMS}"

>&2 echo "Fetching message IDs..."
LIST_STDERR=$(mktemp)
LIST_OUTPUT=$(
  gws gmail users messages list \
    --page-all \
    --page-limit 1000 \
    --params "$PARAMS" \
    2>"$LIST_STDERR"
) || { cat "$LIST_STDERR" >&2; echo "Error fetching messages." >&2; rm -f "$LIST_STDERR"; exit 1; }
rm -f "$LIST_STDERR"

IDS=$(echo "$LIST_OUTPUT" | jq -r '.messages[]?.id' 2>/dev/null)

TOTAL=$(echo "$IDS" | grep -c . || true)

if [[ $TOTAL -eq 0 ]]; then
  echo "No emails found."
  exit 0
fi

>&2 echo "Found $TOTAL emails. Fetching sender headers (parallel=$PARALLEL)..."

# ── Fetch From header for each message in parallel ───────────────────────────
PROGRESS_FILE=$(mktemp)
trap 'rm -f "$PROGRESS_FILE"' EXIT

fetch_sender() {
  local id="$1" total="$2" progress_file="$3" output count
  local rc=0
  output=$(gws gmail users messages get \
    --params "{\"userId\": \"me\", \"id\": \"$id\", \"format\": \"metadata\", \"metadataHeaders\": \"From\"}" \
    2>/dev/null) || rc=$?
  if [[ $rc -ne 0 ]]; then
    >&2 echo "Warning: failed to fetch message $id"
    return
  fi
  echo "$output" | jq -r '.payload.headers[]? | select(.name == "From") | .value' 2>/dev/null

  # Append a line per completion; wc -l counts total across all processes
  echo . >> "$progress_file"
  count=$(wc -l < "$progress_file")
  if (( count % 100 == 0 )); then
    >&2 echo "Progress: $count / $total fetched..."
  fi
}

export -f fetch_sender

SENDERS=$(echo "$IDS" | xargs -P "$PARALLEL" -I{} bash -c 'fetch_sender "$@"' _ {} "$TOTAL" "$PROGRESS_FILE")
>&2 echo "Fetched all $TOTAL sender headers."

# ── Extract email addresses and deduplicate ───────────────────────────────────
# Handle both "Name <email>" and bare "email@domain" formats per-line
EMAILS=$(echo "$SENDERS" | sed -n 's/.*<\([^>]*\)>.*/\1/p; t; s/.*\(\S\+@\S\+\).*/\1/p')

if [[ "$COUNT" == "true" ]]; then
  echo "$EMAILS" | tr '[:upper:]' '[:lower:]' | sort | uniq -c | sort -rn | awk '{print $1, $2}'
else
  echo "$EMAILS" | tr '[:upper:]' '[:lower:]' | sort -u
fi
