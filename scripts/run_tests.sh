#!/bin/bash
set -e

echo "=========================================="
echo "🚀 Running kskAnki Core Tests & Verification..."
echo "=========================================="

swift test --enable-code-coverage

echo "=========================================="
echo "✅ All tests passed successfully!"
echo "=========================================="
