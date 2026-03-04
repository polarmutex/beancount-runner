# Development Guide

## Project Structure

```
beancount-runner/
├── flake.nix              # Nix flake configuration
├── build.zig              # Zig build configuration
├── pipeline.toml          # Default pipeline configuration
├── proto/                 # Protocol Buffer schemas
│   ├── common.proto       # Shared types (Date, Amount, Location, Error)
│   ├── directives.proto   # Beancount directive types
│   └── messages.proto     # Plugin protocol messages
├── src/                   # Zig core orchestrator
│   ├── main.zig           # CLI entry point and argument parsing
│   ├── orchestrator.zig   # Pipeline execution engine
│   ├── plugin_manager.zig # Subprocess spawning and management
│   ├── config.zig         # TOML configuration parsing
│   ├── validator.zig      # Built-in validation rules
│   ├── proto.zig          # Protobuf type definitions
│   ├── protobuf.zig       # Protobuf wire format encoder/decoder
│   └── output.zig         # JSON output formatting
├── plugins/
│   ├── parser-lima/       # Rust beancount parser plugin
│   │   ├── src/
│   │   │   ├── main.rs    # Plugin main loop
│   │   │   ├── plugin.rs  # Protocol handlers
│   │   │   ├── protocol.rs # Protobuf I/O
│   │   │   └── converter.rs # AST → protobuf conversion
│   │   └── tests/         # Rust unit tests
│   └── auto-balance/      # Python auto-balance plugin
│       ├── auto_balance.py # Main plugin implementation
│       └── test_*.py      # Python tests
├── examples/
│   └── sample.beancount   # Example input file
├── test/
│   └── integration_test.sh # End-to-end integration test
├── test_pipeline.sh       # Quick parser-only test
└── docs/
    ├── architecture.md    # System design documentation
    ├── plugin-protocol.md # Plugin development guide
    └── DEVELOPMENT.md     # This file
```

## Development Workflow

### Setting Up

```bash
# Clone the repository
git clone https://github.com/yourusername/beancount-runner.git
cd beancount-runner

# Enter Nix development shell (recommended)
nix develop

# Or install dependencies manually:
# - Zig 0.16+
# - Rust 1.70+
# - Python 3.11+
# - protoc 3.x+
```

### Building

```bash
# Generate protobuf code (automatically done in Nix shell)
protoc --python_out=generated/python --proto_path=proto proto/*.proto
protoc --rust_out=generated/rust --proto_path=proto proto/*.proto

# Build Zig orchestrator
zig build                    # Debug build
zig build -Doptimize=ReleaseFast  # Release build

# Build Rust parser plugin
cd plugins/parser-lima
cargo build --release
cd ../..

# Build outputs:
# - Zig: ./zig-out/bin/beancount-runner
# - Rust: ./plugins/parser-lima/target/release/parser-lima
```

### Running Tests

```bash
# Zig unit tests
zig build test

# Rust plugin tests
cd plugins/parser-lima
cargo test
cd ../..

# Python plugin tests
cd plugins/auto-balance
pytest
cd ../..

# Integration test (full pipeline)
./test/integration_test.sh

# Quick parser-only test
./test_pipeline.sh
```

### Running the Pipeline

```bash
# With default config (pipeline.toml)
./zig-out/bin/beancount-runner --input examples/sample.beancount

# With verbose output
./zig-out/bin/beancount-runner --input examples/sample.beancount --verbose

# With custom config
./zig-out/bin/beancount-runner --input mybooks.beancount --config my-pipeline.toml

# View help
./zig-out/bin/beancount-runner --help
```

## Adding a New Plugin

### 1. Create Plugin Directory

```bash
mkdir -p plugins/my-plugin
cd plugins/my-plugin
```

### 2. Implement Protocol

All plugins must implement the plugin protocol:

1. **Init Phase**: Receive `InitRequest`, respond with `InitResponse`
2. **Process Loop**: Receive `ProcessRequest`, respond with `ProcessResponse`
3. **Shutdown**: Handle EOF or `ShutdownRequest`

### 3. Message Format

Messages use length-prefixed protobuf encoding:

```
[4 bytes: length (little-endian u32)][N bytes: protobuf message]
```

### 4. Language-Specific Examples

#### Rust Plugin

```rust
use prost::Message;
use std::io::{Read, Write, stdin, stdout};

fn read_message<T: Message + Default, R: Read>(reader: &mut R) -> io::Result<T> {
    let mut len_buf = [0u8; 4];
    reader.read_exact(&mut len_buf)?;
    let len = u32::from_le_bytes(len_buf) as usize;

    let mut buf = vec![0u8; len];
    reader.read_exact(&mut buf)?;

    T::decode(&buf[..]).map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))
}

fn write_message<T: Message, W: Write>(writer: &mut W, msg: &T) -> io::Result<()> {
    let buf = msg.encode_to_vec();
    let len = (buf.len() as u32).to_le_bytes();
    writer.write_all(&len)?;
    writer.write_all(&buf)?;
    writer.flush()
}
```

#### Python Plugin

```python
import struct
import sys

def read_message(msg_class):
    length_bytes = sys.stdin.buffer.read(4)
    if not length_bytes:
        return None
    length = struct.unpack('<I', length_bytes)[0]
    data = sys.stdin.buffer.read(length)
    msg = msg_class()
    msg.ParseFromString(data)
    return msg

def write_message(msg):
    data = msg.SerializeToString()
    length = struct.pack('<I', len(data))
    sys.stdout.buffer.write(length)
    sys.stdout.buffer.write(data)
    sys.stdout.buffer.flush()
```

### 5. Add to Pipeline Config

```toml
[[pipeline.stages]]
name = "my-plugin"
type = "external"
executable = "./plugins/my-plugin/my-plugin"
language = "your-language"
description = "What your plugin does"
```

### 6. Test Standalone

Test your plugin independently before integration:

```bash
# Create test input
echo -n "..." > test_input.bin

# Run plugin
./plugins/my-plugin/my-plugin < test_input.bin
```

## Modifying Protobuf Schema

### 1. Edit Schema Files

```bash
# Edit proto/*.proto files
vim proto/directives.proto
```

### 2. Regenerate Code

```bash
# Python
protoc --python_out=generated/python --proto_path=proto proto/*.proto

# Rust (automatically done by build.rs)
cd plugins/parser-lima && cargo build
```

### 3. Update Zig Types

```bash
# Manually update src/proto.zig to match schema
vim src/proto.zig
```

### 4. Update Converters

Update conversion code in plugins:
- Rust: `plugins/parser-lima/src/converter.rs`
- Python: `plugins/auto-balance/auto_balance.py`

## Code Style

### Zig
- Use 4-space indentation
- Follow stdlib naming conventions
- Prefer explicit over implicit
- Use `try` for error propagation

### Rust
- Use `cargo fmt` for formatting
- Follow Rust API guidelines
- Use `cargo clippy` for linting

### Python
- Follow PEP 8
- Use type hints
- Use `pytest` for tests

## Debugging

### Enable Verbose Output

```bash
./zig-out/bin/beancount-runner --input file.beancount --verbose
```

### Plugin Stderr

Plugin stderr is visible in the terminal for debugging:

```rust
eprintln!("Debug: parsing file {}", path);
```

```python
print(f"Debug: processing {len(directives)} directives", file=sys.stderr)
```

### Integration Test Debugging

```bash
# Run integration test with verbose output
./test/integration_test.sh

# Check generated output
cat output.json | jq .
```

## Performance Tips

### Zig
- Use `ReleaseFast` for production
- Minimize allocations in hot paths
- Use ArenaAllocator for batch operations

### Rust
- Build with `--release`
- Use `cargo flamegraph` for profiling
- Consider parallel processing for large files

### Python
- Use generators for large directive streams
- Avoid unnecessary protobuf serialization/deserialization
- Profile with `cProfile` if needed

## Troubleshooting

### Build Errors

**Zig compilation fails:**
- Ensure Zig 0.16+ is installed
- Check that all imports are correct
- Verify protobuf types match schema

**Rust build fails:**
- Run `cargo clean && cargo build`
- Ensure protoc is installed
- Check proto files are in correct location

### Runtime Errors

**Plugin doesn't respond:**
- Check plugin is executable
- Verify stdin/stdout are not buffered
- Test plugin standalone first

**Protocol errors:**
- Verify protobuf message format
- Check length prefix is little-endian u32
- Ensure flush() is called after writing

**Integration test fails:**
- Rebuild all components
- Check file paths in config
- Run with --verbose for details

## Contributing

See [CONTRIBUTING.md](../CONTRIBUTING.md) for guidelines on:
- Code review process
- Commit message format
- Testing requirements
- Documentation standards
