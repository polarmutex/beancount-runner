# Plugin Protocol Specification

This document describes how to implement plugins for Beancount Runner in any programming language.

## Overview

Plugins communicate with the Zig orchestrator via Protocol Buffers over stdin/stdout. Messages are framed using a 4-byte length prefix.

## Stage Types

Each plugin must declare a `stage_type` in `pipeline.toml` to define its role:

### Parsing Stages (`stage_type = "parsing"`)

**Contract**:
- **Input**: Empty directive list
- **Output**: Parsed directives from source file
- **Ordering**: Must be first stage(s) in pipeline
- **Examples**: Beancount parser, CSV importer, OFX converter

### Transformation Stages (`stage_type = "transformation"`)

**Contract**:
- **Input**: Directive list from previous stages
- **Output**: Modified directive list (add/modify/remove directives)
- **Ordering**: After parsing, before validation
- **Examples**: auto-balance, price fetching, account renaming

### Validation Stages (`stage_type = "validation"`)

**Contract**:
- **Input**: Directive list from previous stages
- **Output**: Same directive list (unchanged) + errors
- **Ordering**: After transformation, before output
- **Examples**: balance checker, transaction validator, date ordering

### Output Stages (`stage_type = "output"`)

**Contract**:
- **Input**: Final directive list
- **Output**: Same directive list (side effect: write to file/database)
- **Ordering**: Must be final stage(s) in pipeline
- **Examples**: JSON writer, SQL exporter, report generator

**Stage Ordering**: The orchestrator enforces strict ordering (parsing → transformation → validation → output) and fails at startup if violated.

## Protocol Basics

### Message Framing

Each message consists of:
1. **Length prefix**: 4 bytes, little-endian unsigned integer
2. **Protobuf payload**: Serialized protobuf message

### Plugin Lifecycle

1. **Init**: Handshake and capability exchange
2. **Process**: Batch processing of directives (loop)
3. **Shutdown**: Graceful termination

## Message Specifications

### InitRequest/Response

Orchestrator sends initialization request, plugin responds with version and capabilities.

### ProcessRequest/Response

Orchestrator sends batch of directives, plugin returns modified batch and any errors.

**Directive Operations**:
- **Add**: Include new directives in response
- **Modify**: Change fields of existing directives
- **Delete**: Omit directives from response
- **Preserve**: Return unchanged directives

### ShutdownRequest/Response

Orchestrator signals termination, plugin acknowledges.

## Implementation Guide

### Python Example

```python
import sys
import struct
from proto import messages_pb2

def read_message(msg_class):
    """Read length-prefixed protobuf from stdin."""
    length_bytes = sys.stdin.buffer.read(4)
    if not length_bytes:
        return None
    length = struct.unpack('<I', length_bytes)[0]
    data = sys.stdin.buffer.read(length)
    msg = msg_class()
    msg.ParseFromString(data)
    return msg

def write_message(msg):
    """Write length-prefixed protobuf to stdout."""
    data = msg.SerializeToString()
    length = struct.pack('<I', len(data))
    sys.stdout.buffer.write(length + data)
    sys.stdout.buffer.flush()

# Handle init
init_req = read_message(messages_pb2.InitRequest)
init_resp = messages_pb2.InitResponse(success=True, plugin_version="0.1.0")
write_message(init_resp)

# Main processing loop
while True:
    req = read_message(messages_pb2.ProcessRequest)
    if req is None:
        break
    
    # Process directives
    result_directives = process(req.directives)
    
    resp = messages_pb2.ProcessResponse(directives=result_directives)
    write_message(resp)
```

### Rust Example

```rust
use std::io::{self, Read, Write};
use prost::Message;

fn read_message<T: Message + Default>() -> io::Result<T> {
    let mut len_buf = [0u8; 4];
    io::stdin().read_exact(&mut len_buf)?;
    let len = u32::from_le_bytes(len_buf) as usize;
    
    let mut buf = vec![0u8; len];
    io::stdin().read_exact(&mut buf)?;
    
    T::decode(&buf[..]).map_err(|e| 
        io::Error::new(io::ErrorKind::InvalidData, e))
}

fn write_message<T: Message>(msg: &T) -> io::Result<()> {
    let data = msg.encode_to_vec();
    let len = (data.len() as u32).to_le_bytes();
    
    io::stdout().write_all(&len)?;
    io::stdout().write_all(&data)?;
    io::stdout().flush()
}
```

## Configuration Examples

### Parsing Stage

```toml
[[pipeline.stages]]
name = "parser"
type = "external"
stage_type = "parsing"
executable = "./plugins/parser-lima/target/release/parser-lima"
language = "rust"
description = "Parse beancount file using lima parser"
```

### Transformation Stage

```toml
[[pipeline.stages]]
name = "auto-balance"
type = "external"
stage_type = "transformation"
executable = "python"
args = ["./plugins/auto-balance/auto_balance.py"]
language = "python"
description = "Automatically generate padding entries for balance assertions"
```

### Validation Stage

```toml
[[pipeline.stages]]
name = "validator"
type = "builtin"
stage_type = "validation"
function = "validate_all"
description = "Validate transactions balance, account usage, and date ordering"
```

### Output Stage

```toml
[[pipeline.stages]]
name = "json-writer"
type = "external"
stage_type = "output"
executable = "./plugins/json-writer/json-writer"
language = "zig"
description = "Write directives to JSON file"
```

## Best Practices

1. **Preserve Directive Order**: Maintain chronological ordering
2. **Use Proper Error Reporting**: Include helpful context and locations
3. **Handle Incomplete Data**: Plugins may receive incomplete directives
4. **Preserve Metadata**: Don't lose metadata when modifying directives
5. **Test Standalone**: Plugins should be testable independently

## Debugging Tips

1. **Log to stderr**: Stdout is reserved for protobuf
2. **Validate Protobuf**: Use `protoc --decode` to inspect messages
3. **Test Message Framing**: Verify length prefixes with hexdump
4. **Run in Verbose Mode**: Enable orchestrator verbose output

## Example Plugins

See `plugins/` directory for complete examples:
- `plugins/parser-lima/` - Rust parser plugin
- `plugins/auto-balance/` - Python transformation plugin

## Protocol Version

Current version: `1.0.0`
