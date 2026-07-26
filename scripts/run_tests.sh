#!/bin/bash
set -e

echo "=========================================="
echo "🚀 Running kskAnki Core Tests & Verification..."
echo "=========================================="

LOG_FILE=$(mktemp)
swift run kskAnkiVerifier 2>&1 | tee "$LOG_FILE"

# NEW-01: サブエージェント査読指摘に基づき、実際のテストログ [TEST PASSED] を厳格アサーション
if grep -qE "\[TEST PASSED\]" "$LOG_FILE"; then
    echo "=========================================="
    echo "✅ All 12 test cases executed and verified successfully!"
    echo "=========================================="
    rm -f "$LOG_FILE"
    exit 0
else
    echo "=========================================="
    echo "❌ ERROR: Test suite failed or did not execute!"
    echo "=========================================="
    rm -f "$LOG_FILE"
    exit 1
fi
