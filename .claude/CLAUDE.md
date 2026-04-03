# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# google-mail-clean

Bash scripts for cleaning up Gmail using the [`gws`](https://github.com/googleworkspace/cli) CLI.

## Dependencies

- `gws` — Google Workspace CLI, must be on `$PATH` and authenticated (`gws auth login`)
- `jq` — JSON processor used for parsing API responses

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

## Gmail API Notes

- `messages.list` searches inbox/sent/labels by default; add `in:anywhere` **and** `includeSpamTrash: true` to include trash and spam
- `messages.batchDelete` permanently deletes up to 1000 messages per call — irreversible
- `messages.batchModify` moves up to 1000 messages to trash per call (add `TRASH`, remove `INBOX`)
- `format=metadata&metadataHeaders=From` is the efficient way to fetch only the From header
- Pagination: use `--page-all --page-limit 1000` to retrieve all results
