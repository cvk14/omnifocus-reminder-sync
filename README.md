# OmniFocus Reminders Sync

Bidirectional sync between Apple Reminders and OmniFocus for macOS. Designed for households where family members use Reminders and one person uses OmniFocus.

## What It Does

- Syncs tasks between configured Reminders lists and OmniFocus projects
- Bidirectional: creates, updates, and completes tasks in both directions
- Per-field merge: if you edit the title in OF and your spouse edits the due date in Reminders, both changes are preserved
- Soft-delete: when a reminder is deleted, the OF task is tagged `DELETED` instead of removed, so you can review it
- Runs as a background launchd service with a built-in watchdog
- Keeps OmniFocus running automatically

## Synced Fields

| Field | Direction |
|-------|-----------|
| Title | Bidirectional |
| Notes | Bidirectional |
| Due date | Bidirectional |
| Completion | Bidirectional |

OF-specific fields (tags, defer dates, etc.) and Reminders-specific fields (location, priority, etc.) are never touched.

## Requirements

- macOS 14+
- OmniFocus 4
- Swift 5.9+ / Xcode 15+

## Installation

### Build

```bash
swift build -c release
cp .build/release/reminders-sync /usr/local/bin/
```

### Configure

Create `~/.config/reminders-sync/config.json`:

```json
{
  "mappings": [
    { "reminders": "Inbox", "omnifocus": "Inbox" },
    { "reminders": "Family Groceries", "omnifocus": "Groceries" }
  ],
  "pollIntervalSeconds": 10,
  "logLevel": "info"
}
```

- **mappings** (required): pairs of Reminders list names and OmniFocus project names
- **pollIntervalSeconds** (optional, default 10): how often to check OmniFocus for changes
- **logLevel** (optional, default "info"): one of `debug`, `info`, `warn`, `error`

### Start

```bash
reminders-sync install
```

This installs and loads a launchd service that runs in the background. macOS will prompt you once to grant Reminders access.

### Other Commands

```bash
reminders-sync status     # Last sync time, task counts, watchdog health
reminders-sync sync       # Trigger an immediate sync
reminders-sync uninstall  # Stop and remove the background service
```

## How Sync Works

1. **New task in Reminders** — created in the mapped OmniFocus project
2. **New task in a mapped OF project** — created in the corresponding Reminders list
3. **Field changed on one side** — pushed to the other side
4. **Same field changed on both sides** — last write wins (by modification timestamp)
5. **Completed on either side** — marked complete on both
6. **Deleted in Reminders** — OF task title prepended with `DELETED`, tagged `DELETED` (not removed)
7. **Deleted in OF** — removed from Reminders

## Architecture

See [docs/plans/2026-04-07-sync-design.md](docs/plans/2026-04-07-sync-design.md) for the full design document.

## License

MIT License. See [LICENSE](LICENSE) for details.
