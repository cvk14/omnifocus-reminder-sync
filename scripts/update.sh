#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh
sudo cp .build/release/reminders-sync /usr/local/bin/
echo "Updated. Running sync..."
reminders-sync sync
