#!/usr/bin/env bash
# delete-old-emails.sh
# Deletes Gmail messages older than N years (default: 10).
# Uses batchDelete (permanent, irreversible) unless --trash is passed.
#
# Usage:
#   ./delete-old-emails.sh                  # delete emails older than 10 years (inbox/sent/labels)
#   ./delete-old-emails.sh --years 5        # delete emails older than 5 years
#   ./delete-old-emails.sh --all            # delete ALL emails everywhere (no age limit)
#   ./delete-old-emails.sh --all --years 5  # delete all emails >5 years, everywhere
#   ./delete-old-emails.sh --trash          # move to trash instead of permanent delete
#   ./delete-old-emails.sh --dry-run        # preview only, no deletions

set -euo pipefail

# ── Defaults ────────────────────────────────────────────────────────────────
YEARS=10
YEARS_SET=false
TRASH=false
DRY_RUN=false
ALL=false
BATCH_SIZE=1000   # Gmail batchDelete max

# ── Argument parsing ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --years)   YEARS="$2"; YEARS_SET=true; shift 2 ;;
    --trash)   TRASH=true; shift ;;
    --all)     ALL=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown flag: $1"; exit 1 ;;
  esac
done

# ── Build search query ───────────────────────────────────────────────────────
# --all without --years: no age restriction, search everywhere
# --all with --years: age restriction + search everywhere
# default: age restriction, inbox/sent/labels only
if [[ "$ALL" == "true" && "$YEARS_SET" == "false" ]]; then
  QUERY="in:anywhere"
  DESCRIPTION="all emails in all folders (inbox, sent, drafts, trash, spam, labels)"
elif [[ "$ALL" == "true" ]]; then
  CUTOFF=$(date -d "$YEARS years ago" +%Y/%m/%d)
  QUERY="before:$CUTOFF in:anywhere"
  DESCRIPTION="emails older than $YEARS years (before $CUTOFF) in all folders"
else
  CUTOFF=$(date -d "$YEARS years ago" +%Y/%m/%d)
  QUERY="before:$CUTOFF"
  DESCRIPTION="emails older than $YEARS years (before $CUTOFF)"
fi

# ── Fetch all matching message IDs ───────────────────────────────────────────
if [[ "$DRY_RUN" == "false" ]]; then
  echo "Searching for $DESCRIPTION..."
  echo "Fetching message IDs..."
fi

IDS=$(
  gws gmail users messages list \
    --page-all \
    --page-limit 1000 \
    --params "{\"userId\": \"me\", \"q\": \"$QUERY\", \"maxResults\": 500}" \
    2>/dev/null \
  | jq -r '.messages[]?.id' 2>/dev/null
)

TOTAL=$(echo "$IDS" | grep -c . || true)

if [[ "$TRASH" == "true" ]]; then
  ACTION="moved to trash"
else
  ACTION="PERMANENTLY DELETED (cannot be undone)"
fi

if [[ $TOTAL -eq 0 ]]; then
  echo "No emails found."
  exit 0
fi

if [[ "$DRY_RUN" == "true" ]]; then
  echo "$TOTAL emails would be deleted ($DESCRIPTION)."
  exit 0
fi

echo "Found $TOTAL emails."
echo ""
echo "These $TOTAL emails will be $ACTION."
read -r -p "Type YES to confirm: " CONFIRM
if [[ "$CONFIRM" != "YES" ]]; then
  echo "Aborted."
  exit 0
fi

# ── Delete in batches ────────────────────────────────────────────────────────
DELETED=0
BATCH=()

delete_batch() {
  local ids_json
  ids_json=$(printf '%s\n' "${BATCH[@]}" | jq -Rn '[inputs]')

  if [[ "$TRASH" == "true" ]]; then
    for id in "${BATCH[@]}"; do
      gws gmail users messages trash \
        --params "{\"userId\": \"me\", \"id\": \"$id\"}" \
        --format json > /dev/null 2>&1
    done
  else
    gws gmail users messages batchDelete \
      --params '{"userId": "me"}' \
      --json "{\"ids\": $ids_json}" \
      --format json > /dev/null 2>&1
  fi

  DELETED=$((DELETED + ${#BATCH[@]}))
  echo "Progress: $DELETED / $TOTAL deleted..."
  BATCH=()
}

while IFS= read -r id; do
  [[ -z "$id" ]] && continue
  BATCH+=("$id")
  if [[ ${#BATCH[@]} -ge $BATCH_SIZE ]]; then
    delete_batch
  fi
done <<< "$IDS"

if [[ ${#BATCH[@]} -gt 0 ]]; then
  delete_batch
fi

echo ""
echo "Done. $DELETED emails $ACTION."
