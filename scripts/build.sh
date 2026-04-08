#!/bin/bash
set -euo pipefail

echo "Building reminders-sync..."
swift build -c release

echo "Signing with entitlements..."
codesign --force --sign - \
  --entitlements reminders-sync.entitlements \
  .build/release/reminders-sync

echo "Done. Binary at .build/release/reminders-sync"
echo ""
echo "To install:"
echo "  cp .build/release/reminders-sync /usr/local/bin/"
echo "  reminders-sync install"
