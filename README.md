# Beancount Runner

A high-performance, multi-language plugin pipeline system for processing [Beancount](https://beancount.github.io/) accounting files.

## Overview

Beancount Runner reimagines the Beancount processing pipeline as a modular, language-agnostic system. The core orchestrator is written in Zig for performance and explicit control, while plugins can be written in any language (Rust, Python, Clojure, Zig, etc.) and communicate via Protocol Buffers.

### Key Features

- **Multi-Language Plugins**: Write plugins in your preferred language
- **Protobuf Communication**: Language-agnostic serialization for plugin IPC
- **3-Stage Pipeline**: Parser → Plugins → Validator (matching Beancount's design)
- **Nix Flakes**: Reproducible builds and development environments
- **Extensible Architecture**: Easy to add custom processing logic

## Architecture

```
Input File (.beancount)
    ↓
┌─────────────────────────────────────┐
│ Zig Core Orchestrator               │
│  • Load configuration               │
│  • Spawn plugin subprocesses        │
│  • Route protobuf messages          │
│  • Collect errors & results         │
└─────────────────────────────────────┘
    ↓              ↓              ↓
[Parser]      [Plugins]      [Validator]
    ↓              ↓              ↓
  Rust          Python           Zig
 (lima)      (auto-balance)   (builtin)

Output: directives + errors + options
```

## Quick Start

### Prerequisites

- [Nix](https://nixos.org/) with flakes enabled

### Development Environment

```bash
# Enter development shell
nix develop

# Generate protobuf code
protoc --python_out=generated/python --proto_path=proto proto/*.proto

# Build Zig core (when ready)
zig build-exe src/main.zig -O ReleaseFast

# Run pipeline
./beancount-runner --input examples/sample.beancount --verbose
```

### Using the Flake

```bash
# Run directly from flake
nix run . -- --input mybooks.beancount

# Build the package
nix build .

# Enter dev shell with all tools
nix develop
```

## Configuration

The pipeline is configured via `pipeline.toml`:

```toml
[pipeline]
input = "examples/sample.beancount"
output_format = "json"

[[pipeline.stages]]
name = "parser"
type = "external"
executable = "./plugins/parser-lima/target/release/parser-lima"
language = "rust"

[[pipeline.stages]]
name = "auto-balance"
type = "external"
executable = "python"
args = ["./plugins/auto-balance/auto_balance.py"]
language = "python"

[[pipeline.stages]]
name = "validator"
type = "builtin"
function = "validate_all"

[options]
operating_currency = "USD"
tolerance_default = "0.005"
```

## Plugin Development

Plugins communicate with the Zig orchestrator via Protocol Buffers over stdin/stdout using length-prefixed messages.

### Protocol Flow

1. **Init**: Orchestrator sends `InitRequest`, plugin responds with version/capabilities
2. **Process**: Orchestrator sends `ProcessRequest` with directive batch
3. **Response**: Plugin returns `ProcessResponse` with modified directives + errors
4. **Shutdown**: Orchestrator sends `ShutdownRequest`, plugin terminates

### Example Python Plugin

```python
import sys
from proto import messages_pb2

def read_message(msg_class):
    length = int.from_bytes(sys.stdin.buffer.read(4), 'little')
    data = sys.stdin.buffer.read(length)
    msg = msg_class()
    msg.ParseFromString(data)
    return msg

def write_message(msg):
    data = msg.SerializeToString()
    length = len(data).to_bytes(4, 'little')
    sys.stdout.buffer.write(length + data)
    sys.stdout.buffer.flush()

# Handle init
init_req = read_message(messages_pb2.InitRequest)
init_resp = messages_pb2.InitResponse(success=True, plugin_version="0.1.0")
write_message(init_resp)

# Process loop
while True:
    req = read_message(messages_pb2.ProcessRequest)
    # Process directives...
    resp = messages_pb2.ProcessResponse(directives=modified_directives)
    write_message(resp)
```

See [docs/plugin-protocol.md](docs/plugin-protocol.md) for complete specification.

## Project Structure

```
beancount-runner/
├── flake.nix              # Nix flake configuration
├── pipeline.toml          # Pipeline configuration
├── proto/                 # Protobuf schemas
│   ├── common.proto       # Shared types (Date, Amount, etc.)
│   ├── directives.proto   # Beancount directive types
│   └── messages.proto     # Plugin protocol messages
├── src/                   # Zig core orchestrator
│   ├── main.zig           # CLI entry point
│   ├── orchestrator.zig   # Pipeline execution
│   ├── plugin_manager.zig # Subprocess management
│   ├── config.zig         # Configuration parsing
│   └── validator.zig      # Built-in validation
├── plugins/
│   ├── parser-lima/       # Rust beancount parser
│   └── auto-balance/      # Python auto-balance plugin
├── examples/
│   └── sample.beancount   # Example input file
└── docs/
    ├── architecture.md    # System design
    └── plugin-protocol.md # Plugin development guide
```

## Roadmap

### Phase 1: Foundation ✅
- [x] Protobuf schemas (all directive types)
- [x] Nix flake with dependencies
- [x] Zig core orchestrator skeleton
- [x] Pipeline configuration format

### Phase 2: Rust Parser (In Progress)
- [ ] Fork beancount_parser_lima
- [ ] Add protobuf support
- [ ] Implement plugin protocol
- [ ] AST → protobuf conversion

### Phase 3: Python Plugin
- [ ] Auto-balance logic
- [ ] Protobuf message handling
- [ ] Protocol compliance

### Phase 4: Zig Validator
- [ ] Transaction balancing
- [ ] Account validation
- [ ] Balance assertions
- [ ] Date ordering

### Phase 5: Integration
- [ ] End-to-end testing
- [ ] Performance benchmarking
- [ ] Documentation
- [ ] Example files

## Contributing

Contributions welcome! Areas of interest:

- **Plugin Development**: Create plugins in various languages
- **Parser Implementation**: Complete Rust parser integration
- **Validator Logic**: Implement validation rules
- **TOML Parser**: Replace hardcoded config with proper parser
- **Output Formats**: JSON, protobuf, human-readable text

## Documentation

- [Architecture Overview](docs/architecture.md) - System design and data flow
- [Plugin Protocol](docs/plugin-protocol.md) - How to write plugins
- [Beancount Design Doc](https://beancount.github.io/docs/beancount_design_doc.html) - Original design reference

## License

MIT License - See LICENSE file

## References

- [Beancount](https://beancount.github.io/) - Original accounting system
- [beancount_parser_lima](https://crates.io/crates/beancount_parser_lima) - Rust parser
- [Protocol Buffers](https://protobuf.dev/) - Serialization format
- [Zig](https://ziglang.org/) - Core language
