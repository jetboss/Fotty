#!/bin/bash

# Fotty Code Guardian Runner
# Phase 1: Report-Only Mode

# Ensure we are in the guardian directory
cd "$(dirname "$0")"

echo "----------------------------------------"
echo "🛡️  FOTTY CODE GUARDIAN: PHASE 1 STARTING"
echo "----------------------------------------"

# 1. Environment Check
if ! command -v python3 &> /dev/null
then
    echo "❌ Error: python3 is not installed."
    exit 1
fi

# 2. Run Analyzer
python3 scripts/analyzer.py

echo "----------------------------------------"
echo "✅ GUARDIAN RUN COMPLETE"
echo "Report available at: guardian/reports/latest.md"
echo "----------------------------------------"
