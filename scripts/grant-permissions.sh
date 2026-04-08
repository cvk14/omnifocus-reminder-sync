#!/bin/bash
set -euo pipefail

echo "Granting Reminders TCC permissions (requires sudo)..."

DB="/Library/Application Support/com.apple.TCC/TCC.db"

sudo sqlite3 "$DB" "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, indirect_object_identifier, boot_uuid, last_reminded) VALUES ('kTCCServiceReminders', '/usr/local/bin/reminders-sync', 1, 2, 3, 1, 'UNUSED', 'UNUSED', 0);"

echo "Done. Try: reminders-sync check"
echo "Note: On modern macOS, this script may fail due to SIP. If so, grant permission via System Settings or by running reminders-sync check from a local Terminal session."
