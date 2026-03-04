#!/usr/bin/env bash
# Test script to verify pipeline produces directives from sample.beancount

set -euo pipefail

echo "Testing beancount-runner pipeline..."

# Run pipeline with parser-only config (for MVP)
OUTPUT=$(./zig-out/bin/beancount-runner --config pipeline-parser-only.toml --input examples/sample.beancount --verbose 2>&1)

echo "$OUTPUT"

# Extract directive count from plugin output (MVP: parser returns count)
DIRECTIVE_COUNT=$(echo "$OUTPUT" | grep "📊 Plugin returned" | awk '{print $4}')

echo ""
echo "Directive count: $DIRECTIVE_COUNT"

if [ "$DIRECTIVE_COUNT" -eq 0 ]; then
    echo "❌ FAIL: Expected directives but got 0"
    exit 1
fi

echo "✅ PASS: Pipeline produced $DIRECTIVE_COUNT directives"
exit 0
