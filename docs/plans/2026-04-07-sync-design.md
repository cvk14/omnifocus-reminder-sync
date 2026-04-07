# OmniFocus Reminders Sync — Design

## Overview

A Swift command-line tool that runs as a macOS launchd service, providing bidirectional sync between Apple Reminders and OmniFocus. Designed for a household where family members use Reminders and one person uses OmniFocus.

## Sync Scope

### What syncs
- **Title**
- **Notes/body**
- **Due date**
- **Completion status**

### What doesn't sync
- OF-specific fields (defer dates, tags, projects, contexts) are left untouched
- Reminders-specific fields (location triggers, URLs, priority) are left untouched
- Sync only touches shared fields — a merge, not a replace

### Direction
- **Creation**: bidirectional. New Reminders appear in OF; new tasks in mapped OF projects appear in Reminders.
- **Updates**: bidirectional with per-field merge. If different fields changed on each side, both changes are preserved. If the same field changed on both sides, last-write-wins by modification date.
- **Completion**: bidirectional. Completing in either app marks it done in both.
- **Deletion from Reminders**: soft-delete in OF — title is prepended with `DELETED` and a `DELETED` tag is added. The task is not removed from OF.
- **Deletion from OF**: hard-delete from Reminders.

## Architecture

### Components

1. **Sync Engine** — core logic for diffing, merging, and applying changes
2. **Reminders Adapter** — reads/writes via EventKit framework
3. **OmniFocus Adapter** — reads/writes via Omni Automation (JavaScript scripts executed through `osascript`)
4. **Sync Database** — local SQLite store tracking last-synced state
5. **Watchdog** — monitors sync loop health, restarts if stalled
6. **OmniFocus Keepalive** — ensures OF is running before each sync cycle
7. **Launchd Service** — process lifecycle management

### Sync Database Schema

SQLite database at `~/.config/reminders-sync/sync.db`:

| Column | Type | Purpose |
|--------|------|---------|
| `id` | INTEGER PRIMARY KEY | Internal sync ID |
| `reminders_id` | TEXT | EventKit calendar item ID |
| `omnifocus_id` | TEXT | OF task ID from Omni Automation |
| `title` | TEXT | Last-synced title |
| `notes` | TEXT | Last-synced notes |
| `due_date` | TEXT | Last-synced due date (ISO 8601) |
| `completed` | INTEGER | Last-synced completion state (0/1) |
| `reminders_modified` | TEXT | Last-known Reminders modification date |
| `omnifocus_modified` | TEXT | Last-known OF modification date |

### Sync Cycle Logic

1. Fetch current state from both Reminders and OF for mapped lists/projects
2. For each task in the sync DB, compare current state against last-synced state:
   - **New in Reminders, not in DB** — create in OF, add to sync DB
   - **New in OF (in mapped project), not in DB** — create in Reminders, add to sync DB
   - **Changed fields on one side only** — push change to the other side, update sync DB
   - **Changed same field on both sides** — last-write-wins by modification date, update both + sync DB
   - **Deleted in Reminders** — soft-delete in OF (prepend `DELETED`, add `DELETED` tag), update sync DB
   - **Deleted in OF** — delete from Reminders, remove from sync DB

### OmniFocus Integration

Communicates via Omni Automation — small JavaScript scripts executed through `Process` calling `osascript -l JavaScript`.

Operations:
- **Read tasks**: query all tasks in a mapped project, return JSON with ID, title, notes, due date, completion, modification date
- **Create task**: add a new task to the mapped project
- **Update task**: modify specific fields by task ID
- **Soft-delete**: prepend title with `DELETED`, add `DELETED` tag

If OmniFocus is not running, the app launches it silently via `NSWorkspace` and waits for it to be ready.

## Process Lifecycle

### Launchd Service

Installed at `~/Library/LaunchAgents/com.reminders-sync.plist`:
- `KeepAlive: true` — restarts on crash
- `RunAtLoad: true` — starts on login
- Logs to `~/.config/reminders-sync/logs/`

### Startup Sequence

1. Load config file
2. Open sync database (create if first run)
3. Ensure OmniFocus is running (launch if needed)
4. Register EventKit change observer
5. Run initial full sync
6. Enter event loop:
   - EventKit notifications trigger immediate Reminders-side sync
   - 10-second polling interval catches OF-side changes
7. Watchdog timer starts

### Watchdog

- Sync loop writes a timestamp to `~/.config/reminders-sync/heartbeat` every cycle
- A `DispatchSourceTimer` checks heartbeat staleness every 60 seconds
- If heartbeat is >60s stale: tears down EventKit observers, re-registers them, resets the sync loop
- All watchdog events are logged (no user notifications)

### OmniFocus Keepalive

- Each sync cycle checks if OF is running via `NSRunningApplication`
- If not running, launches silently via `NSWorkspace.shared.openApplication(at:)`
- Waits for OF to be ready before executing Omni Automation scripts
- Logged silently

## Configuration

Config file at `~/.config/reminders-sync/config.json`:

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

- `mappings` (required): array of Reminders list name to OmniFocus project name pairs
- `pollIntervalSeconds` (optional, default 10): how often to poll OF for changes
- `logLevel` (optional, default "info"): logging verbosity (debug, info, warn, error)

## CLI Commands

- `reminders-sync install` — copies launchd plist and loads the service
- `reminders-sync uninstall` — unloads and removes the launchd plist
- `reminders-sync status` — shows last sync time, task counts, watchdog health
- `reminders-sync sync` — triggers an immediate manual sync

## First Run

1. Build the Swift project
2. Create config file at `~/.config/reminders-sync/config.json`
3. Run `reminders-sync install`
4. Grant Reminders access when macOS prompts (EventKit permission)
5. Initial full sync runs automatically

## License

MIT
