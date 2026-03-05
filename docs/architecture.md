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

### Stage Types

The pipeline supports four distinct stage types that execute in strict order:

1. **Parsing** (`parsing`): Convert input files to directive streams
   - Must be first stage(s) in pipeline
   - Receive empty directive list, return parsed directives
   - Examples: Beancount parser, CSV importer, OFX converter

2. **Transformation** (`transformation`): Modify directive streams
   - Execute after parsing, before validation
   - May add, modify, or remove directives
   - Examples: auto-balance, price fetching, account renaming

3. **Validation** (`validation`): Check correctness without modification
   - Execute after transformation
   - Return errors but preserve directive list unchanged
   - Examples: balance checker, account validator, date ordering

4. **Output** (`output`): Write results to files or databases
   - Must be final stage(s) in pipeline
   - Examples: JSON writer, SQL exporter, report generator

**Ordering Rules**:
- Stages execute in declared order within `pipeline.toml`
- Stage types must follow the sequence: parsing → transformation → validation → output
- Multiple stages of the same type are allowed (e.g., multiple transformations)
- The orchestrator validates this ordering at startup and fails fast on violations

### Zig Orchestrator

The orchestrator coordinates the pipeline:

1. Load Configuration (pipeline.toml)
2. Validate Stage Type Ordering
3. Initialize Empty Directive List
4. For Each Stage:
   - Spawn Plugin Subprocess
   - Send InitRequest
   - Send ProcessRequest
   - Receive ProcessResponse
   - Update Directive List
   - Accumulate Errors
   - Send ShutdownRequest
5. Return Final Results

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
