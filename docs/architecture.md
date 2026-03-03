# Beancount Runner Architecture

## System Overview

Beancount Runner is a modular pipeline system for processing Beancount accounting files. It separates concerns into three main components:

1. **Zig Core Orchestrator**: Manages pipeline execution and plugin lifecycle
2. **External Plugins**: Language-agnostic processing stages (parser, transformers)
3. **Protobuf Protocol**: Language-neutral serialization for IPC

## Design Principles

### 1. Language Agnosticism

Plugins can be written in any language that supports:
- Stdin/stdout communication
- Protocol Buffer serialization
- Length-prefixed message framing

This enables:
- Leveraging existing parsers (Rust beancount_parser_lima)
- Python plugins for rapid development
- Performance-critical plugins in Zig/Rust
- Future expansion to Go, Clojure, etc.

### 2. Process Isolation

Each plugin runs as a separate subprocess, providing:
- **Safety**: Plugin crashes don't affect orchestrator
- **Language Freedom**: No FFI compatibility constraints
- **Simplicity**: Standard stdin/stdout communication
- **Debuggability**: Can inspect/test plugins independently

### 3. Stateless Pipeline

Following Beancount's design, the pipeline is stateless:
- Each stage receives directive list, returns directive list
- No shared mutable state between plugins
- Functional transformation model
- Reproducible results

## Core Components

### Zig Orchestrator

The orchestrator coordinates the pipeline:

1. Load Configuration (pipeline.toml)
2. Initialize Empty Directive List
3. For Each Stage:
   - Spawn Plugin Subprocess
   - Send InitRequest
   - Send ProcessRequest
   - Receive ProcessResponse
   - Update Directive List
   - Accumulate Errors
   - Send ShutdownRequest
4. Return Final Results

### Validator

Built-in validation stage with 4 core validations:

1. **Transaction Balance**: All transactions balance within tolerance
2. **Account Usage**: Accounts opened before usage
3. **Balance Assertions**: Positioned correctly, values match
4. **Date Ordering**: Directives sorted by date (then line number)

## Protocol Specification

See [plugin-protocol.md](plugin-protocol.md) for complete details.

## Future Directions

1. **Streaming mode**: Process directives incrementally
2. **Parallel plugins**: Run independent plugins concurrently
3. **Process pool**: Reuse plugin subprocesses
4. **Shared memory**: Zero-copy for large batches
5. **FFI**: Native bindings for Zig/Rust plugins

## References

- [Beancount Design Doc](https://beancount.github.io/docs/beancount_design_doc.html)
- [Protocol Buffers](https://protobuf.dev/)
- [Zig Documentation](https://ziglang.org/documentation/)
