#!/usr/bin/env bash
# test/integration_test.sh

set -euo pipefail

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🧪 Beancount Runner Integration Test"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Build everything
echo "📦 Building components..."
echo "  • Zig orchestrator..."
zig build

echo "  • Rust parser plugin..."
cd plugins/parser-lima && cargo build --release 2>&1 | grep -E "Finished|error" && cd ../..

echo ""
echo "✅ Build complete"
echo ""

# Test parser-only pipeline
echo "🧪 Test 1: Parser-only pipeline"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

OUTPUT=$(./zig-out/bin/beancount-runner \
  --config pipeline-parser-only.toml \
  --input examples/sample.beancount \
  --verbose 2>&1)

echo "$OUTPUT" | tail -10

# Extract directive count from plugin output
DIRECTIVE_COUNT=$(echo "$OUTPUT" | grep "📊 Plugin returned" | awk '{print $4}')

if [ -z "$DIRECTIVE_COUNT" ]; then
    echo "❌ FAIL: Could not find directive count in output"
    exit 1
fi

if [ "$DIRECTIVE_COUNT" -gt 0 ]; then
    echo "✅ PASS: Parser plugin returned $DIRECTIVE_COUNT directives"
else
    echo "❌ FAIL: Expected directives but got $DIRECTIVE_COUNT"
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ All integration tests passed!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
