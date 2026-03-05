# Justfile for beancount-runner development

# Default recipe lists available commands
default:
    @just --list

# Build all components
build-all: build-core build-plugins
    @echo "✅ All components built successfully"

# Build Zig core
build-core:
    @echo "🔨 Building Zig core..."
    nix develop --command zig build

# Build all plugins
build-plugins: build-parser build-auto-balance
    @echo "✅ All plugins built"

# Build parser plugin (Rust)
build-parser:
    @echo "🔨 Building parser-lima plugin..."
    cd plugins/parser-lima && nix develop --command cargo build --release
    @echo "✅ Parser plugin built: plugins/parser-lima/target/release/parser-lima"

# Build auto-balance plugin (Python - no build needed)
build-auto-balance:
    @echo "✅ Auto-balance plugin ready: plugins/auto-balance/auto_balance.py"

# Run tests
test:
    @echo "🧪 Running tests..."
    nix develop --command zig build test

# Run sample file through complete pipeline
run-sample: build-all
    @echo "🚀 Running sample file through pipeline..."
    nix develop --command zig build run -- --input examples/sample.beancount --verbose

# Run sample with text output
run-sample-text: build-all
    @echo "🚀 Running sample file with text output..."
    nix develop --command zig build run -- --input examples/sample.beancount --verbose --config pipeline-text.toml

# Run a specific beancount file
run file: build-all
    @echo "🚀 Running {{file}}..."
    nix develop --command zig build run -- --input {{file}} --verbose

# Clean build artifacts
clean:
    @echo "🧹 Cleaning build artifacts..."
    rm -rf zig-cache zig-out .zig-cache
    cd plugins/parser-lima && cargo clean
    @echo "✅ Clean complete"

# Run balance validation tests
test-balance:
    @echo "🧪 Running balance validation tests..."
    nix develop --command bash -c "zig build test 2>&1 | grep -A 5 'balance assertion'"

# Format code
fmt:
    @echo "🎨 Formatting Zig code..."
    nix develop --command zig fmt src/*.zig

# Check if all tools are available
check-tools:
    @echo "🔍 Checking required tools..."
    @command -v zig >/dev/null 2>&1 || echo "❌ zig not found"
    @command -v cargo >/dev/null 2>&1 || echo "❌ cargo not found"
    @command -v python3 >/dev/null 2>&1 || echo "❌ python3 not found"
    @command -v nix >/dev/null 2>&1 && echo "✅ nix found" || echo "❌ nix not found"
    @echo "✅ Tool check complete"
