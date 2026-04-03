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
    --help|-h)
      cat <<'EOF'
Usage: delete-old-emails.sh [OPTIONS]

Bulk-delete Gmail messages older than N years.

Options:
  --years N    Delete emails older than N years (default: 10)
  --all        Include all folders (trash, spam, drafts, labels);
               without --years, removes the age filter entirely
  --trash      Move to trash instead of permanently deleting
  --dry-run    Count matching emails without deleting
  --help, -h   Show this help message

Examples:
  ./delete-old-emails.sh                  # permanently delete emails >10 years old
  ./delete-old-emails.sh --years 5        # permanently delete emails >5 years old
  ./delete-old-emails.sh --all            # permanently delete ALL emails everywhere
  ./delete-old-emails.sh --trash --years 3  # trash emails >3 years old
  ./delete-old-emails.sh --dry-run        # preview count only
EOF
      exit 0 ;;
    *) echo "Unknown flag: $1"; exit 1 ;;
  esac
done

if [[ "$YEARS_SET" == "true" && ! "$YEARS" =~ ^[1-9][0-9]*$ ]]; then
  echo "Error: --years requires a positive integer (got: '$YEARS')"
  exit 1
fi

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
if [[ "$DRY_RUN" == "true" ]]; then
  echo "Counting emails (this may take a moment for large mailboxes)..."
else
  echo "Searching for $DESCRIPTION..."
  echo "Fetching message IDs..."
fi

LIST_PARAMS="{\"userId\": \"me\", \"q\": \"$QUERY\", \"maxResults\": 500"
[[ "$ALL" == "true" ]] && LIST_PARAMS="$LIST_PARAMS, \"includeSpamTrash\": true"
LIST_PARAMS="$LIST_PARAMS}"

LIST_STDERR=$(mktemp)
LIST_OUTPUT=$(
  gws gmail users messages list \
    --page-all \
    --page-limit 1000 \
    --params "$LIST_PARAMS" \
    2>"$LIST_STDERR"
) || { cat "$LIST_STDERR" >&2; echo "Error fetching messages."; rm -f "$LIST_STDERR"; exit 1; }
rm -f "$LIST_STDERR"

IDS=$(echo "$LIST_OUTPUT" | jq -r '.messages[]?.id' 2>/dev/null)

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
FAILED=0
BATCH=()

delete_batch() {
  local ids_json batch_output batch_size
  ids_json=$(printf '%s\n' "${BATCH[@]}" | jq -Rn '[inputs]')
  batch_size=${#BATCH[@]}

  local rc=0
  if [[ "$TRASH" == "true" ]]; then
    batch_output=$(gws gmail users messages batchModify \
      --params '{"userId": "me"}' \
      --json "{\"ids\": $ids_json, \"addLabelIds\": [\"TRASH\"], \"removeLabelIds\": [\"INBOX\"]}" \
      --format json 2>/dev/null) || rc=$?
  else
    # batchDelete: Gmail API documents a 1000-ID limit for batchModify;
    # batchDelete has no documented limit but we use the same cap to be safe.
    batch_output=$(gws gmail users messages batchDelete \
      --params '{"userId": "me"}' \
      --json "{\"ids\": $ids_json}" \
      --format json 2>/dev/null) || rc=$?
  fi

  if [[ $rc -ne 0 ]]; then
    echo "Warning: batch failed ($batch_size messages): $batch_output" >&2
    FAILED=$((FAILED + batch_size))
  else
    DELETED=$((DELETED + batch_size))
  fi

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
if [[ $FAILED -gt 0 ]]; then
  echo "Done. $DELETED emails $ACTION. $FAILED emails failed." >&2
  exit 1
else
  echo "Done. $DELETED emails $ACTION."
fi
