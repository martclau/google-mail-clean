# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# google-mail-clean

Bash scripts for cleaning up Gmail using the [`gws`](https://github.com/googleworkspace/cli) CLI.

## Dependencies

- `gws` — Google Workspace CLI, must be on `$PATH` and authenticated (`gws auth login`)
- `jq` — JSON processor used for parsing API responses

## Running

```bash
# No build step — scripts run directly
./delete-old-emails.sh [OPTIONS]
./find-senders.sh [OPTIONS]

# Check syntax without executing
bash -n delete-old-emails.sh
bash -n find-senders.sh
```

No test suite exists. Test manually with `--dry-run` (delete script) or small queries.

## Scripts

### `delete-old-emails.sh`
Bulk-deletes Gmail messages older than N years using `batchDelete` (up to 1000 IDs per request).
- Default: emails older than 10 years, inbox/sent/labels only
- `--all` removes the age filter, adds `in:anywhere`, and sets `includeSpamTrash: true`
- `--trash` uses `messages.batchModify` (adds `TRASH` label, removes `INBOX`; up to 1000 per call)
- `--years` validates input is a positive integer; exits with error otherwise
- `--dry-run` prints "Counting emails..." while fetching IDs (can be slow for large mailboxes)
- Always requires typing `YES` to confirm before deleting (skipped with `--dry-run`)

### `find-senders.sh`
Audits unique sender addresses by fetching only the `From` header (`format=metadata`) for each message.
- Uses `xargs -P` for parallel API requests (default: 10); override with `--parallel N`
- Supports `--years` and `--all` flags (same semantics as `delete-old-emails.sh`)
- Progress output goes to stderr so stdout can be piped/redirected
- `--count` outputs `<count> <email>` sorted by frequency

## Shared Patterns

Both scripts follow the same structure: argument parsing → query building → `messages.list` with pagination → process IDs. When adding a new script or flag:

- **Argument parsing**: `while [[ $# -gt 0 ]]; case` pattern with `shift 2` for valued flags
- **Query building**: `--all` adds `in:anywhere` to the query string and `includeSpamTrash: true` to params; `--years` adds `before:YYYY/MM/DD` via `date -d "$YEARS years ago" +%Y/%m/%d`
- **ID fetching**: Both capture stderr to a temp file to surface `gws` errors cleanly, then extract IDs with `jq -r '.messages[]?.id'`
- **All scripts use `set -euo pipefail`**

## `gws` CLI Conventions

The `gws` CLI wraps Google Workspace REST APIs. Key invocation patterns:

```bash
# General form
gws gmail users messages <method> --params '<JSON>' [--json '<body>'] [--format json]

# Pagination (fetches all pages, 1000 results per page)
gws gmail users messages list --page-all --page-limit 1000 --params '<JSON>'

# Single message fetch
gws gmail users messages get --params '{"userId": "me", "id": "<id>", ...}'
```

- `--params` takes a JSON string with query parameters (userId, q, maxResults, includeSpamTrash, format, metadataHeaders)
- `--json` takes a JSON request body (used by batchDelete, batchModify)
- `--format json` requests JSON output from the CLI itself

## Gmail API Notes

- `messages.list` searches inbox/sent/labels by default; add `in:anywhere` **and** `includeSpamTrash: true` to include trash and spam
- `messages.batchDelete` permanently deletes up to 1000 messages per call — irreversible
- `messages.batchModify` moves up to 1000 messages to trash per call (add `TRASH`, remove `INBOX`)
- `format=metadata&metadataHeaders=From` is the efficient way to fetch only the From header
- Pagination: use `--page-all --page-limit 1000` to retrieve all results
