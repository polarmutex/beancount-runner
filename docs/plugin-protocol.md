# Plugin Protocol Specification

This document describes how to implement plugins for Beancount Runner in any programming language.

## Overview

Plugins communicate with the Zig orchestrator via Protocol Buffers over stdin/stdout. Messages are framed using a 4-byte length prefix.

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
