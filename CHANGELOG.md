# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-03-03

### Added

#### Core Infrastructure
- Zig core orchestrator with plugin lifecycle management
- Multi-language plugin support (Rust, Python, Zig)
- Protocol Buffers communication protocol
- Length-prefixed protobuf wire format encoding/decoding
- TOML-based pipeline configuration system
- Nix flake for reproducible builds and development environments

#### Protobuf Schemas
- Comprehensive protobuf schemas for all Beancount directive types
- `common.proto`: Date, Amount, Location, Error types
- `directives.proto`: Transaction, Balance, Open, Close, Pad, Note, Document, etc.
- `messages.proto`: Plugin protocol messages (InitRequest, ProcessRequest, etc.)

#### Rust Parser Plugin
- `parser-lima` plugin using beancount_parser_lima library
- Protobuf message I/O with length-prefixed wire format
- Plugin protocol handlers (Init/Process/Shutdown)
- Beancount AST to protobuf conversion for all directive types
- Comprehensive unit tests

#### Python Auto-Balance Plugin
- Auto-balance plugin for generating Pad directives
- Protobuf message handling in Python
- Configurable pad account
- Date-based pad directive generation
- Unit tests for protocol and logic

#### Zig Validator
- Built-in validation system
- Transaction balance validation
- Account usage validation
- Date ordering validation
- Balance assertion checking
- Configurable tolerance for balance checks

#### Output & Testing
- JSON output formatting for directives and errors
- Integration test suite
- Parser-only pipeline testing
- End-to-end pipeline verification

### Core Features

- **3-Stage Pipeline Architecture**: Parser → Plugins → Validator
- **Language-Agnostic Plugins**: Write plugins in any language with protobuf support
- **Protobuf IPC**: Efficient binary communication between orchestrator and plugins
- **Subprocess Management**: Safe plugin spawning and lifecycle management
- **Error Collection**: Aggregate errors from all pipeline stages
- **Extensible Configuration**: TOML-based pipeline and plugin configuration

### Technical Details

#### Protobuf Protocol
- Length-prefixed message framing (4-byte little-endian length + message)
- Init/Process/Shutdown lifecycle
- Streaming directive processing
- Error propagation from all stages

#### Validation Rules
- Transaction balancing (per-currency)
- Account must be opened before use
- Chronological ordering of directives
- Balance assertions checked

#### Supported Directive Types
- Transaction (with postings, tags, links, metadata)
- Balance (account balance assertions)
- Open (account opening declarations)
- Close (account closing declarations)
- Pad (padding entries for auto-balance)
- Note, Document, Price, Event, Query, Commodity, Custom

### Known Limitations

- Protobuf deserialization returns directive counts but not full directive data (MVP)
- Multi-stage pipeline (parser + plugin + validator) needs more testing
- Text and protobuf output formats not yet implemented
- TOML parser is basic (production should use proper TOML library)

### Performance

- Zig orchestrator provides low-latency plugin management
- Rust parser leverages beancount_parser_lima performance
- Streaming directive processing for memory efficiency

### Dependencies

- Zig 0.16+ (core orchestrator)
- Rust 1.70+ (parser plugin)
- Python 3.11+ (auto-balance plugin)
- Protocol Buffers 3.x+ (code generation)
- Nix (for reproducible builds)

### Documentation

- README with quick start and architecture overview
- DEVELOPMENT.md with detailed development guide
- Plugin protocol documentation
- Integration test examples

### Testing

- Zig unit tests for core components
- Rust unit tests for parser plugin
- Python unit tests for auto-balance plugin
- Integration test suite for end-to-end validation
- Sample beancount file for testing

---

## [Unreleased]

### Planned Features

- Full protobuf deserialization for directive data
- Complete multi-stage pipeline integration
- Additional output formats (text, protobuf)
- Performance benchmarking suite
- More validation rules
- Additional plugin examples
- Comprehensive documentation

### Future Enhancements

- Parallel plugin execution
- Plugin dependency management
- Hot-reloading of configuration
- Web-based pipeline visualization
- Metrics and observability

---

[0.1.0]: https://github.com/yourusername/beancount-runner/releases/tag/v0.1.0
