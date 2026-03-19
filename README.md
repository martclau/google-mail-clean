# Cleaning up Gmail

Scripts for cleaning up Gmail using the [`gws`](https://github.com/googleworkspace/cli) CLI.

## Prerequisites

- [`gws`](https://github.com/googleworkspace/cli) installed and on `$PATH`
- [`jq`](https://jqlang.github.io/jq/) installed
- Authenticated: `gws auth login`

---

## Scripts

### `delete-old-emails.sh`

Permanently deletes (or trashes) Gmail messages older than a given number of years.

```bash
./delete-old-emails.sh [OPTIONS]
```

| Flag | Default | Description |
|------|---------|-------------|
| `--years N` | `10` | Delete emails older than N years |
| `--all` | — | No age limit; searches all folders (inbox, sent, drafts, trash, spam, labels) |
| `--all --years N` | — | Older than N years, across all folders |
| `--trash` | — | Move to trash instead of permanent delete |
| `--dry-run` | — | Preview count only, no deletions |

**Examples:**

```bash
# Preview how many emails would be deleted
./delete-old-emails.sh --dry-run

# Delete emails older than 10 years (inbox/sent/labels)
./delete-old-emails.sh

# Delete emails older than 5 years
./delete-old-emails.sh --years 5

# Delete ALL emails everywhere (no age limit)
./delete-old-emails.sh --all --dry-run
./delete-old-emails.sh --all

# Delete emails older than 5 years across all folders
./delete-old-emails.sh --all --years 5

# Move to trash instead of permanent delete
./delete-old-emails.sh --years 10 --trash
```

> **Warning:** Without `--trash`, deletion is permanent and cannot be undone. Always run with `--dry-run` first.

---

### `find-senders.sh`

Lists all unique sender email addresses in your mailbox, with an optional age filter.

```bash
./find-senders.sh [OPTIONS]
```

| Flag | Default | Description |
|------|---------|-------------|
| `--years N` | — | Only emails older than N years |
| `--all` | — | Include all folders (trash, spam, drafts, etc.) |
| `--count` | — | Show email count per sender, sorted by most frequent |
| `--parallel N` | `10` | Number of parallel API requests |

**Examples:**

```bash
# All senders in your mailbox
./find-senders.sh

# Senders of emails older than 10 years
./find-senders.sh --years 10

# With email count per sender
./find-senders.sh --years 10 --count

# All folders, older than 5 years, save to file
./find-senders.sh --all --years 5 --count > senders.txt

# Faster processing with more parallelism
./find-senders.sh --years 10 --parallel 20
```

**Tip:** Progress messages are printed to stderr, so you can pipe or redirect stdout cleanly:

```bash
./find-senders.sh --years 10 --count > senders.txt
```
