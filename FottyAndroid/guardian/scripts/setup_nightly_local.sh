#!/bin/bash

# Fotty Code Guardian: Local Nightly Setup
# This script adds a cron job to run the Guardian every night at midnight.

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GUARDIAN_RUN_SH="$PROJECT_ROOT/guardian/run.sh"
LOG_FILE="$PROJECT_ROOT/guardian/reports/nightly_log.txt"

# 1. Ensure run.sh is executable
chmod +x "$GUARDIAN_RUN_SH"

# 2. Create the cron command
# Run at 00:00 every day
CRON_CMD="0 0 * * * /bin/bash $GUARDIAN_RUN_SH >> $LOG_FILE 2>&1"

# 3. Add to crontab if not already present
(crontab -l 2>/dev/null | grep -v "$GUARDIAN_RUN_SH"; echo "$CRON_CMD") | crontab -

echo "----------------------------------------"
echo "🛡️  LOCAL NIGHTLY GUARDIAN CONFIGURED"
echo "----------------------------------------"
echo "Schedule: Every night at 00:00"
echo "Command: $GUARDIAN_RUN_SH"
echo "Logs: $LOG_FILE"
echo "----------------------------------------"
echo "Note: Ensure your machine is awake at midnight for this to run."
