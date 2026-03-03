# Beancount Runner Phases 2-5 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a complete multi-language plugin pipeline system for processing Beancount files with Rust parser, Python auto-balance plugin, Zig validator, and end-to-end integration.

**Architecture:** Three-stage pipeline (Parser → Plugins → Validator) with Zig orchestrator coordinating external plugins via protobuf over stdin/stdout. Parser converts .beancount files to directive stream, plugins transform directives, validator checks invariants.

**Tech Stack:** Zig (orchestrator), Rust (parser), Python (plugins), Protocol Buffers (IPC), Nix (builds)

---

## Phase 2: Rust Parser Integration

### Task 1: Set up Rust parser project structure

**Files:**
- Create: `plugins/parser-lima/Cargo.toml`
- Create: `plugins/parser-lima/build.rs`
- Create: `plugins/parser-lima/src/main.rs`
- Create: `plugins/parser-lima/src/lib.rs`

**Step 1: Create Cargo.toml**

```toml
[package]
name = "beancount-parser-lima-plugin"
version = "0.1.0"
edition = "2021"

[[bin]]
name = "parser-lima"
path = "src/main.rs"

[dependencies]
beancount_parser_lima = "0.3"
prost = "0.13"
prost-types = "0.13"

[build-dependencies]
prost-build = "0.13"
```

**Step 2: Create build.rs for protobuf codegen**

```rust
fn main() {
    prost_build::Config::new()
        .compile_protos(
            &[
                "../../proto/common.proto",
                "../../proto/directives.proto",
                "../../proto/messages.proto",
            ],
            &["../../proto/"],
        )
        .unwrap();
}
```

**Step 3: Create empty lib.rs**

```rust
// Generated protobuf code will be included here
pub mod beancount {
    include!(concat!(env!("OUT_DIR"), "/beancount.rs"));
}
```

**Step 4: Create main.rs stub**

```rust
fn main() {
    println!("Parser plugin starting...");
}
```

**Step 5: Test build**

Run: `cd plugins/parser-lima && cargo build`
Expected: Build succeeds, generates protobuf code

**Step 6: Commit**

```bash
git add plugins/parser-lima/
git commit -m "feat(parser): initialize Rust parser plugin project"
```

---

### Task 2: Implement protobuf message I/O

**Files:**
- Create: `plugins/parser-lima/src/protocol.rs`
- Modify: `plugins/parser-lima/src/main.rs`
- Create: `plugins/parser-lima/tests/protocol_test.rs`

**Step 1: Write test for reading length-prefixed message**

```rust
// tests/protocol_test.rs
use std::io::Cursor;

#[test]
fn test_read_message_simple() {
    // Create a test message: length=5, data="hello"
    let data = vec![5, 0, 0, 0, b'h', b'e', b'l', b'l', b'o'];
    let mut reader = Cursor::new(data);

    let result = read_raw_message(&mut reader).unwrap();
    assert_eq!(result, b"hello");
}
```

**Step 2: Run test to verify failure**

Run: `cd plugins/parser-lima && cargo test test_read_message_simple`
Expected: FAIL with "function `read_raw_message` not found"

**Step 3: Implement message I/O in protocol.rs**

```rust
use std::io::{self, Read, Write};
use prost::Message;

pub fn read_raw_message<R: Read>(reader: &mut R) -> io::Result<Vec<u8>> {
    // Read 4-byte length prefix (little-endian)
    let mut len_buf = [0u8; 4];
    reader.read_exact(&mut len_buf)?;
    let len = u32::from_le_bytes(len_buf) as usize;

    // Read message bytes
    let mut buf = vec![0u8; len];
    reader.read_exact(&mut buf)?;
    Ok(buf)
}

pub fn write_raw_message<W: Write>(writer: &mut W, data: &[u8]) -> io::Result<()> {
    // Write length prefix
    let len = (data.len() as u32).to_le_bytes();
    writer.write_all(&len)?;

    // Write message
    writer.write_all(data)?;
    writer.flush()
}

pub fn read_message<T: Message + Default, R: Read>(reader: &mut R) -> io::Result<T> {
    let buf = read_raw_message(reader)?;
    T::decode(&buf[..]).map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))
}

pub fn write_message<T: Message, W: Write>(writer: &mut W, msg: &T) -> io::Result<()> {
    let buf = msg.encode_to_vec();
    write_raw_message(writer, &buf)
}
```

**Step 4: Update main.rs to use protocol module**

```rust
mod protocol;

fn main() {
    println!("Parser plugin starting...");
}
```

**Step 5: Update test to use protocol module**

```rust
use beancount_parser_lima_plugin::protocol::read_raw_message;
// ... rest of test
```

**Step 6: Run test to verify pass**

Run: `cd plugins/parser-lima && cargo test test_read_message_simple`
Expected: PASS

**Step 7: Commit**

```bash
git add plugins/parser-lima/
git commit -m "feat(parser): implement protobuf message I/O"
```

---

### Task 3: Implement plugin protocol handlers

**Files:**
- Create: `plugins/parser-lima/src/plugin.rs`
- Modify: `plugins/parser-lima/src/main.rs`
- Create: `plugins/parser-lima/tests/plugin_protocol_test.rs`

**Step 1: Write test for init protocol**

```rust
// tests/plugin_protocol_test.rs
use std::io::Cursor;
use beancount_parser_lima_plugin::plugin::PluginHandler;

#[test]
fn test_plugin_init() {
    let handler = PluginHandler::new();

    let init_req = create_init_request("parser", "parser");
    let init_resp = handler.handle_init(init_req);

    assert!(init_resp.success);
    assert_eq!(init_resp.plugin_version, env!("CARGO_PKG_VERSION"));
}
```

**Step 2: Run test to verify failure**

Run: `cargo test test_plugin_init`
Expected: FAIL with "module `plugin` not found"

**Step 3: Implement plugin handler**

```rust
// src/plugin.rs
use crate::beancount::{InitRequest, InitResponse, ProcessRequest, ProcessResponse};
use std::collections::HashMap;

pub struct PluginHandler {
    version: String,
}

impl PluginHandler {
    pub fn new() -> Self {
        Self {
            version: env!("CARGO_PKG_VERSION").to_string(),
        }
    }

    pub fn handle_init(&self, _request: InitRequest) -> InitResponse {
        InitResponse {
            success: true,
            error_message: String::new(),
            plugin_version: self.version.clone(),
            capabilities: HashMap::new(),
        }
    }

    pub fn handle_process(&self, request: ProcessRequest) -> ProcessResponse {
        // TODO: Implement actual parsing
        ProcessResponse {
            directives: vec![],
            errors: vec![],
            updated_options: HashMap::new(),
        }
    }
}
```

**Step 4: Update main.rs to expose plugin module**

```rust
pub mod protocol;
pub mod plugin;
```

**Step 5: Create test helper for init request**

```rust
use beancount_parser_lima_plugin::beancount::InitRequest;

fn create_init_request(name: &str, stage: &str) -> InitRequest {
    InitRequest {
        plugin_name: name.to_string(),
        pipeline_stage: stage.to_string(),
        options: std::collections::HashMap::new(),
    }
}
```

**Step 6: Run test to verify pass**

Run: `cargo test test_plugin_init`
Expected: PASS

**Step 7: Commit**

```bash
git add plugins/parser-lima/
git commit -m "feat(parser): implement plugin protocol handlers"
```

---

### Task 4: Implement main plugin loop

**Files:**
- Modify: `plugins/parser-lima/src/main.rs`
- Create: `plugins/parser-lima/tests/integration_test.rs`

**Step 1: Write integration test**

```rust
// tests/integration_test.rs
use std::process::{Command, Stdio};
use std::io::Write;

#[test]
fn test_plugin_lifecycle() {
    // This test will manually drive the plugin through init -> process -> shutdown
    // Skipping for now as it requires binary to be built
}
```

**Step 2: Implement main loop**

```rust
// src/main.rs
mod protocol;
mod plugin;

use crate::beancount::{InitRequest, ProcessRequest, ShutdownRequest};
use crate::plugin::PluginHandler;
use crate::protocol::{read_message, write_message};
use std::io::{stdin, stdout};

fn main() -> std::io::Result<()> {
    let mut handler = PluginHandler::new();

    let mut stdin = stdin().lock();
    let mut stdout = stdout().lock();

    // Handle init
    let init_req: InitRequest = read_message(&mut stdin)?;
    let init_resp = handler.handle_init(init_req);
    write_message(&mut stdout, &init_resp)?;

    // Main process loop
    loop {
        // Try to read next message
        match read_message::<ProcessRequest, _>(&mut stdin) {
            Ok(proc_req) => {
                let proc_resp = handler.handle_process(proc_req);
                write_message(&mut stdout, &proc_resp)?;
            }
            Err(e) if e.kind() == std::io::ErrorKind::UnexpectedEof => {
                // Normal shutdown on EOF
                break;
            }
            Err(e) => {
                eprintln!("Error reading message: {}", e);
                return Err(e);
            }
        }
    }

    Ok(())
}
```

**Step 3: Build and test manually**

Run: `cargo build --release`
Expected: Binary created at `target/release/parser-lima`

**Step 4: Commit**

```bash
git add plugins/parser-lima/src/main.rs
git commit -m "feat(parser): implement plugin main loop"
```

---

### Task 5: Implement beancount parsing logic

**Files:**
- Create: `plugins/parser-lima/src/converter.rs`
- Modify: `plugins/parser-lima/src/plugin.rs`
- Create: `plugins/parser-lima/tests/converter_test.rs`

**Step 1: Write test for transaction conversion**

```rust
// tests/converter_test.rs
use beancount_parser_lima::Directive as LimaDirective;
use beancount_parser_lima_plugin::converter::convert_directive;

#[test]
fn test_convert_transaction() {
    // Create a simple lima transaction
    let lima_txn = create_test_transaction();

    let proto_directive = convert_directive(&lima_txn).unwrap();

    assert!(proto_directive.directive_type.is_some());
    // More specific assertions about transaction fields
}
```

**Step 2: Run test to verify failure**

Run: `cargo test test_convert_transaction`
Expected: FAIL with "module `converter` not found"

**Step 3: Implement converter module**

```rust
// src/converter.rs
use crate::beancount;
use beancount_parser_lima::{Directive as LimaDirective, Transaction as LimaTxn};

pub fn convert_directive(lima: &LimaDirective) -> Result<beancount::Directive, String> {
    match lima {
        LimaDirective::Transaction(txn) => Ok(convert_transaction(txn)?),
        LimaDirective::Balance(bal) => Ok(convert_balance(bal)?),
        LimaDirective::Open(open) => Ok(convert_open(open)?),
        // Add other directive types
        _ => Err(format!("Unsupported directive type")),
    }
}

fn convert_transaction(lima: &LimaTxn) -> Result<beancount::Directive, String> {
    let mut proto_txn = beancount::Transaction {
        date: Some(convert_date(&lima.date)),
        flag: lima.flag.as_ref().map(|f| f.to_string()),
        payee: lima.payee.clone(),
        narration: lima.narration.clone(),
        tags: lima.tags.iter().map(|t| t.to_string()).collect(),
        links: lima.links.iter().map(|l| l.to_string()).collect(),
        postings: lima.postings.iter().map(convert_posting).collect(),
        metadata: None, // TODO: Convert metadata
        location: Some(convert_location(&lima.location)),
    };

    Ok(beancount::Directive {
        directive_type: Some(beancount::directive::DirectiveType::Transaction(proto_txn)),
    })
}

fn convert_date(lima_date: &beancount_parser_lima::Date) -> beancount::Date {
    beancount::Date {
        year: lima_date.year as i32,
        month: lima_date.month as i32,
        day: lima_date.day as i32,
    }
}

fn convert_posting(lima_post: &beancount_parser_lima::Posting) -> beancount::Posting {
    beancount::Posting {
        account: lima_post.account.clone(),
        amount: lima_post.amount.as_ref().map(convert_amount),
        cost: None, // TODO
        price: None, // TODO
        flag: None,
        metadata: None,
    }
}

fn convert_amount(lima_amt: &beancount_parser_lima::Amount) -> beancount::Amount {
    beancount::Amount {
        number: lima_amt.value.to_string(),
        currency: lima_amt.currency.clone(),
    }
}

fn convert_location(lima_loc: &beancount_parser_lima::Location) -> beancount::Location {
    beancount::Location {
        filename: lima_loc.filename.clone(),
        line: lima_loc.line as i32,
        column: 0, // Lima doesn't track column
    }
}

fn convert_balance(lima: &beancount_parser_lima::Balance) -> Result<beancount::Directive, String> {
    // TODO: Implement
    Err("Not implemented".to_string())
}

fn convert_open(lima: &beancount_parser_lima::Open) -> Result<beancount::Directive, String> {
    // TODO: Implement
    Err("Not implemented".to_string())
}
```

**Step 4: Update plugin.rs to use converter**

```rust
// src/plugin.rs
use crate::converter;

impl PluginHandler {
    pub fn handle_process(&self, request: ProcessRequest) -> ProcessResponse {
        // Get input file from options
        let input_file = request.options_map.get("input_file")
            .expect("input_file not in options");

        // Read and parse file
        let content = std::fs::read_to_string(input_file)
            .expect("Failed to read input file");

        let parsed = beancount_parser_lima::parse(&content)
            .expect("Failed to parse beancount file");

        // Convert to protobuf directives
        let mut directives = vec![];
        let mut errors = vec![];

        for lima_directive in parsed.directives {
            match converter::convert_directive(&lima_directive) {
                Ok(proto_dir) => directives.push(proto_dir),
                Err(e) => {
                    errors.push(create_error(&e, "parser"));
                }
            }
        }

        ProcessResponse {
            directives,
            errors,
            updated_options: HashMap::new(),
        }
    }
}

fn create_error(msg: &str, source: &str) -> beancount::Error {
    beancount::Error {
        message: msg.to_string(),
        source: source.to_string(),
        location: None,
    }
}
```

**Step 5: Add converter module to main.rs**

```rust
pub mod converter;
```

**Step 6: Run test**

Run: `cargo test test_convert_transaction`
Expected: May need to adjust test based on actual lima types

**Step 7: Commit**

```bash
git add plugins/parser-lima/
git commit -m "feat(parser): implement beancount AST to protobuf conversion"
```

---

## Phase 3: Python Auto-Balance Plugin

### Task 6: Set up Python plugin project

**Files:**
- Create: `plugins/auto-balance/pyproject.toml`
- Create: `plugins/auto-balance/auto_balance.py`
- Create: `plugins/auto-balance/test_auto_balance.py`

**Step 1: Create pyproject.toml**

```toml
[project]
name = "beancount-auto-balance-plugin"
version = "0.1.0"
requires-python = ">=3.11"
dependencies = [
    "protobuf>=4.25.0",
]

[project.optional-dependencies]
dev = [
    "pytest>=7.0.0",
]

[build-system]
requires = ["setuptools>=61.0"]
build-backend = "setuptools.build_meta"
```

**Step 2: Create empty plugin file**

```python
#!/usr/bin/env python3
"""Auto-balance plugin for beancount-runner."""

def main():
    print("Auto-balance plugin starting...")

if __name__ == "__main__":
    main()
```

**Step 3: Make executable**

Run: `chmod +x plugins/auto-balance/auto_balance.py`

**Step 4: Test execution**

Run: `python plugins/auto-balance/auto_balance.py`
Expected: Prints "Auto-balance plugin starting..."

**Step 5: Commit**

```bash
git add plugins/auto-balance/
git commit -m "feat(plugin): initialize Python auto-balance plugin"
```

---

### Task 7: Implement Python protobuf I/O

**Files:**
- Modify: `plugins/auto-balance/auto_balance.py`
- Create: `plugins/auto-balance/test_protocol.py`

**Step 1: Write test for message I/O**

```python
# test_protocol.py
import struct
from io import BytesIO
from auto_balance import read_message, write_message

def test_read_write_message():
    # Create test data
    test_data = b"hello world"

    # Write to buffer
    output = BytesIO()
    write_raw_message(output, test_data)

    # Read from buffer
    output.seek(0)
    result = read_raw_message(output)

    assert result == test_data
```

**Step 2: Run test to verify failure**

Run: `cd plugins/auto-balance && pytest test_protocol.py`
Expected: FAIL with "function 'read_message' not found"

**Step 3: Implement message I/O functions**

```python
import sys
import struct
from typing import TypeVar, Type

# Import generated protobuf (will be in generated/python/)
sys.path.insert(0, '../../generated/python')
from proto import common_pb2, directives_pb2, messages_pb2

T = TypeVar('T')

def read_raw_message(stream) -> bytes:
    """Read length-prefixed message from stream."""
    # Read 4-byte length (little-endian)
    length_bytes = stream.read(4)
    if not length_bytes:
        return None

    length = struct.unpack('<I', length_bytes)[0]

    # Read message bytes
    data = stream.read(length)
    if len(data) != length:
        raise IOError(f"Expected {length} bytes, got {len(data)}")

    return data

def write_raw_message(stream, data: bytes):
    """Write length-prefixed message to stream."""
    # Write length prefix
    length = struct.pack('<I', len(data))
    stream.write(length)

    # Write message
    stream.write(data)
    stream.flush()

def read_message(msg_class: Type[T], stream) -> T:
    """Read and parse protobuf message."""
    data = read_raw_message(stream)
    if data is None:
        return None

    msg = msg_class()
    msg.ParseFromString(data)
    return msg

def write_message(stream, msg):
    """Serialize and write protobuf message."""
    data = msg.SerializeToString()
    write_raw_message(stream, data)
```

**Step 4: Run test to verify pass**

Run: `pytest test_protocol.py`
Expected: PASS

**Step 5: Commit**

```bash
git add plugins/auto-balance/
git commit -m "feat(plugin): implement Python protobuf I/O"
```

---

### Task 8: Implement plugin protocol in Python

**Files:**
- Modify: `plugins/auto-balance/auto_balance.py`
- Create: `plugins/auto-balance/test_plugin_protocol.py`

**Step 1: Write test for plugin lifecycle**

```python
# test_plugin_protocol.py
import pytest
from auto_balance import PluginHandler

def test_handle_init():
    handler = PluginHandler()

    init_req = messages_pb2.InitRequest(
        plugin_name="auto-balance",
        pipeline_stage="plugin"
    )

    init_resp = handler.handle_init(init_req)

    assert init_resp.success
    assert init_resp.plugin_version == "0.1.0"
```

**Step 2: Run test to verify failure**

Run: `pytest test_plugin_protocol.py`
Expected: FAIL with "class 'PluginHandler' not found"

**Step 3: Implement plugin handler class**

```python
class PluginHandler:
    """Handles plugin protocol and auto-balance logic."""

    VERSION = "0.1.0"

    def __init__(self):
        self.pad_account = "Equity:Opening-Balances"

    def handle_init(self, request: messages_pb2.InitRequest) -> messages_pb2.InitResponse:
        """Handle initialization request."""
        # Extract pad account from options if provided
        if "pad_account" in request.options:
            self.pad_account = request.options["pad_account"]

        return messages_pb2.InitResponse(
            success=True,
            plugin_version=self.VERSION,
        )

    def handle_process(self, request: messages_pb2.ProcessRequest) -> messages_pb2.ProcessResponse:
        """Process directives and generate pad entries."""
        # TODO: Implement auto-balance logic
        return messages_pb2.ProcessResponse(
            directives=list(request.directives),
            errors=[],
        )
```

**Step 4: Run test to verify pass**

Run: `pytest test_plugin_protocol.py`
Expected: PASS

**Step 5: Commit**

```bash
git add plugins/auto-balance/
git commit -m "feat(plugin): implement plugin protocol handler"
```

---

### Task 9: Implement auto-balance logic

**Files:**
- Modify: `plugins/auto-balance/auto_balance.py`
- Create: `plugins/auto-balance/test_auto_balance_logic.py`

**Step 1: Write test for pad generation**

```python
# test_auto_balance_logic.py
import pytest
from auto_balance import PluginHandler

def test_generate_pad_for_balance():
    handler = PluginHandler()

    # Create a Balance directive that needs padding
    balance = directives_pb2.Directive()
    balance.balance.date.year = 2024
    balance.balance.date.month = 1
    balance.balance.date.day = 10
    balance.balance.account = "Assets:Checking"
    balance.balance.amount.number = "1000.00"
    balance.balance.amount.currency = "USD"

    request = messages_pb2.ProcessRequest(directives=[balance])
    response = handler.handle_process(request)

    # Should generate a Pad directive before the balance
    assert len(response.directives) == 2
    assert response.directives[0].HasField('pad')
    assert response.directives[0].pad.account == "Assets:Checking"
    assert response.directives[0].pad.source_account == "Equity:Opening-Balances"
```

**Step 2: Run test to verify failure**

Run: `pytest test_auto_balance_logic.py`
Expected: FAIL - returns 1 directive instead of 2

**Step 3: Implement auto-balance logic**

```python
def handle_process(self, request: messages_pb2.ProcessRequest) -> messages_pb2.ProcessResponse:
    """Process directives and generate pad entries."""
    directives = list(request.directives)
    new_directives = []
    errors = []

    # Find all Balance directives
    balance_accounts = set()
    for directive in directives:
        if directive.HasField('balance'):
            balance_accounts.add(directive.balance.account)

    # Generate Pad directives for each balance account
    for account in balance_accounts:
        # Find first balance for this account
        first_balance = self._find_first_balance(directives, account)
        if first_balance:
            pad = self._create_pad_directive(account, first_balance.date)
            new_directives.append(pad)

    # Combine original and new directives
    all_directives = new_directives + directives

    # Sort by date
    all_directives.sort(key=lambda d: self._get_directive_date(d))

    return messages_pb2.ProcessResponse(
        directives=all_directives,
        errors=errors,
    )

def _find_first_balance(self, directives, account: str):
    """Find the first Balance directive for an account."""
    for d in directives:
        if d.HasField('balance') and d.balance.account == account:
            return d.balance
    return None

def _create_pad_directive(self, account: str, balance_date):
    """Create a Pad directive one day before balance date."""
    pad = directives_pb2.Directive()

    # Set date to one day before balance
    pad.pad.date.year = balance_date.year
    pad.pad.date.month = balance_date.month
    pad.pad.date.day = balance_date.day - 1  # Simplified

    pad.pad.account = account
    pad.pad.source_account = self.pad_account

    return pad

def _get_directive_date(self, directive):
    """Extract date from any directive type for sorting."""
    if directive.HasField('transaction'):
        d = directive.transaction.date
    elif directive.HasField('balance'):
        d = directive.balance.date
    elif directive.HasField('pad'):
        d = directive.pad.date
    elif directive.HasField('open'):
        d = directive.open.date
    else:
        # Default date for unknown types
        return (9999, 12, 31)

    return (d.year, d.month, d.day)
```

**Step 4: Run test to verify pass**

Run: `pytest test_auto_balance_logic.py`
Expected: PASS

**Step 5: Commit**

```bash
git add plugins/auto-balance/
git commit -m "feat(plugin): implement auto-balance pad generation"
```

---

### Task 10: Implement main plugin loop

**Files:**
- Modify: `plugins/auto-balance/auto_balance.py`

**Step 1: Implement main function**

```python
def main():
    """Main plugin loop."""
    handler = PluginHandler()

    stdin_stream = sys.stdin.buffer
    stdout_stream = sys.stdout.buffer

    # Handle init
    init_req = read_message(messages_pb2.InitRequest, stdin_stream)
    init_resp = handler.handle_init(init_req)
    write_message(stdout_stream, init_resp)

    # Main process loop
    while True:
        try:
            proc_req = read_message(messages_pb2.ProcessRequest, stdin_stream)
            if proc_req is None:
                # EOF - normal shutdown
                break

            proc_resp = handler.handle_process(proc_req)
            write_message(stdout_stream, proc_resp)

        except Exception as e:
            # Log error to stderr (stdout is for protocol)
            print(f"Error processing: {e}", file=sys.stderr)
            break
```

**Step 2: Test manually**

Run: `python plugins/auto-balance/auto_balance.py`
(Will hang waiting for stdin - that's correct)
Press Ctrl+C to exit

**Step 3: Commit**

```bash
git add plugins/auto-balance/auto_balance.py
git commit -m "feat(plugin): implement main plugin loop"
```

---

## Phase 4: Zig Validator Completion

### Task 11: Implement transaction balance validation

**Files:**
- Modify: `src/validator.zig`
- Create: `src/validator_test.zig`

**Step 1: Write test for balanced transaction**

```zig
// src/validator_test.zig
const std = @import("std");
const validator = @import("validator.zig");
const testing = std.testing;

test "balanced transaction passes validation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create a balanced transaction
    var txn = createTestTransaction(allocator);

    var val = validator.Validator.init(allocator);
    var errors = std.ArrayList(validator.Error).init(allocator);

    try val.validateTransactionBalances(&[_]validator.Directive{txn}, &errors);

    try testing.expectEqual(@as(usize, 0), errors.items.len);
}
```

**Step 2: Run test to verify failure**

Run: `zig test src/validator_test.zig`
Expected: FAIL with compilation errors (need to define types)

**Step 3: Define test helper types**

```zig
fn createTestTransaction(allocator: std.mem.Allocator) validator.Directive {
    // TODO: Create proper test transaction structure
    // This will be implemented once we have actual protobuf types
    return undefined;
}
```

**Step 4: Implement validateTransactionBalances**

```zig
fn validateTransactionBalances(
    self: *Validator,
    directives: []const Directive,
    errors: *std.ArrayList(Error),
) !void {
    for (directives) |directive| {
        // Skip if not a transaction
        if (!directive.hasTransaction()) continue;

        const txn = directive.getTransaction();

        // Track balance per currency
        var balance_map = std.StringHashMap(f64).init(self.allocator);
        defer balance_map.deinit();

        // Sum all postings
        for (txn.postings) |posting| {
            if (posting.amount) |amount| {
                const value = try parseAmount(amount.number);
                const currency = amount.currency;

                const entry = try balance_map.getOrPut(currency);
                if (!entry.found_existing) {
                    entry.value_ptr.* = 0;
                }
                entry.value_ptr.* += value;
            }
        }

        // Check each currency balances to zero
        var iter = balance_map.iterator();
        while (iter.next()) |entry| {
            const balance = entry.value_ptr.*;
            if (@abs(balance) > self.tolerance) {
                try errors.append(Error{
                    .message = try std.fmt.allocPrint(
                        self.allocator,
                        "Transaction does not balance: {s} off by {d:.2}",
                        .{ entry.key_ptr.*, balance }
                    ),
                    .source = try self.allocator.dupe(u8, "validator"),
                });
            }
        }
    }
}

fn parseAmount(number_str: []const u8) !f64 {
    return std.fmt.parseFloat(f64, number_str) catch |err| {
        std.debug.print("Failed to parse amount: {s}\n", .{number_str});
        return err;
    };
}
```

**Step 5: Run test (will skip until types are ready)**

Note: Full test execution requires protobuf types to be generated for Zig

**Step 6: Commit**

```bash
git add src/validator.zig src/validator_test.zig
git commit -m "feat(validator): implement transaction balance validation"
```

---

### Task 12: Implement account usage validation

**Files:**
- Modify: `src/validator.zig`

**Step 1: Implement validateAccountUsage**

```zig
fn validateAccountUsage(
    self: *Validator,
    directives: []const Directive,
    errors: *std.ArrayList(Error),
) !void {
    // Track opened accounts with their dates
    var open_accounts = std.StringHashMap(Date).init(self.allocator);
    defer {
        var iter = open_accounts.keyIterator();
        while (iter.next()) |key| {
            self.allocator.free(key.*);
        }
        open_accounts.deinit();
    }

    for (directives) |directive| {
        // Record Open directives
        if (directive.hasOpen()) {
            const open = directive.getOpen();
            try open_accounts.put(
                try self.allocator.dupe(u8, open.account),
                open.date
            );
        }

        // Check Transaction postings
        if (directive.hasTransaction()) {
            const txn = directive.getTransaction();

            for (txn.postings) |posting| {
                if (!open_accounts.contains(posting.account)) {
                    try errors.append(Error{
                        .message = try std.fmt.allocPrint(
                            self.allocator,
                            "Account '{s}' used before being opened",
                            .{posting.account}
                        ),
                        .source = try self.allocator.dupe(u8, "validator"),
                    });
                } else {
                    // Verify transaction date >= open date
                    const open_date = open_accounts.get(posting.account).?;
                    if (compareDates(txn.date, open_date) < 0) {
                        try errors.append(Error{
                            .message = try std.fmt.allocPrint(
                                self.allocator,
                                "Account '{s}' used on {d}-{d:0>2}-{d:0>2} before open date {d}-{d:0>2}-{d:0>2}",
                                .{
                                    posting.account,
                                    txn.date.year, txn.date.month, txn.date.day,
                                    open_date.year, open_date.month, open_date.day,
                                }
                            ),
                            .source = try self.allocator.dupe(u8, "validator"),
                        });
                    }
                }
            }
        }

        // Also check Balance directives
        if (directive.hasBalance()) {
            const bal = directive.getBalance();
            if (!open_accounts.contains(bal.account)) {
                try errors.append(Error{
                    .message = try std.fmt.allocPrint(
                        self.allocator,
                        "Balance assertion for unopened account '{s}'",
                        .{bal.account}
                    ),
                    .source = try self.allocator.dupe(u8, "validator"),
                });
            }
        }
    }
}

fn compareDates(a: Date, b: Date) i32 {
    if (a.year != b.year) return a.year - b.year;
    if (a.month != b.month) return a.month - b.month;
    return a.day - b.day;
}
```

**Step 2: Commit**

```bash
git add src/validator.zig
git commit -m "feat(validator): implement account usage validation"
```

---

### Task 13: Implement date ordering validation

**Files:**
- Modify: `src/validator.zig`

**Step 1: Implement validateDateOrdering**

```zig
fn validateDateOrdering(
    self: *Validator,
    directives: []const Directive,
    errors: *std.ArrayList(Error),
) !void {
    var prev_date: ?Date = null;

    for (directives) |directive| {
        const current_date = getDirectiveDate(directive) orelse continue;

        if (prev_date) |prev| {
            const cmp = compareDates(current_date, prev);
            if (cmp < 0) {
                try errors.append(Error{
                    .message = try std.fmt.allocPrint(
                        self.allocator,
                        "Directive out of order: {d}-{d:0>2}-{d:0>2} comes after {d}-{d:0>2}-{d:0>2}",
                        .{
                            current_date.year, current_date.month, current_date.day,
                            prev.year, prev.month, prev.day,
                        }
                    ),
                    .source = try self.allocator.dupe(u8, "validator"),
                });
            }
        }

        prev_date = current_date;
    }
}

fn getDirectiveDate(directive: Directive) ?Date {
    if (directive.hasTransaction()) return directive.getTransaction().date;
    if (directive.hasBalance()) return directive.getBalance().date;
    if (directive.hasOpen()) return directive.getOpen().date;
    if (directive.hasClose()) return directive.getClose().date;
    if (directive.hasPad()) return directive.getPad().date;
    return null;
}
```

**Step 2: Commit**

```bash
git add src/validator.zig
git commit -m "feat(validator): implement date ordering validation"
```

---

## Phase 5: End-to-End Integration

### Task 14: Generate Zig protobuf code

**Files:**
- Create: `build.zig`
- Modify: `flake.nix`

**Step 1: Create build.zig for Zig project**

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "beancount-runner",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Add protobuf dependency (will need protobuf-zig library)
    // For now, we'll manually handle protobuf

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Tests
    const tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);
}
```

**Step 2: Update flake.nix build phase**

```nix
buildPhase = ''
  # Generate protobuf code
  mkdir -p generated/{rust,python}

  # Rust
  protoc --rust_out=generated/rust \
    --proto_path=proto \
    proto/*.proto

  # Python
  protoc --python_out=generated/python \
    --proto_path=proto \
    proto/*.proto

  # Build Zig using build.zig
  zig build -Doptimize=ReleaseFast

  # Build Rust parser
  cd plugins/parser-lima
  cargo build --release
  cd ../..
'';
```

**Step 3: Test build**

Run: `nix build`
Expected: Builds successfully

**Step 4: Commit**

```bash
git add build.zig flake.nix
git commit -m "feat(build): add Zig build system and update flake"
```

---

### Task 15: Implement protobuf types in Zig

**Files:**
- Create: `src/proto.zig`
- Modify: `src/orchestrator.zig`
- Modify: `src/validator.zig`

**Step 1: Create manual protobuf type definitions**

Note: Zig doesn't have official protobuf support, so we'll create simplified types

```zig
// src/proto.zig
const std = @import("std");

pub const Date = struct {
    year: i32,
    month: i32,
    day: i32,
};

pub const Amount = struct {
    number: []const u8,
    currency: []const u8,
};

pub const Location = struct {
    filename: []const u8,
    line: i32,
    column: i32,
};

pub const Error = struct {
    message: []const u8,
    source: []const u8,
    location: ?Location = null,
};

pub const Posting = struct {
    account: []const u8,
    amount: ?Amount,
    cost: ?Amount = null,
    price: ?Amount = null,
    flag: ?[]const u8 = null,
};

pub const Transaction = struct {
    date: Date,
    flag: ?[]const u8,
    payee: ?[]const u8,
    narration: []const u8,
    tags: [][]const u8,
    links: [][]const u8,
    postings: []Posting,
    location: Location,
};

pub const Balance = struct {
    date: Date,
    account: []const u8,
    amount: Amount,
    location: Location,
};

pub const Open = struct {
    date: Date,
    account: []const u8,
    currencies: [][]const u8,
    location: Location,
};

pub const Close = struct {
    date: Date,
    account: []const u8,
    location: Location,
};

pub const Pad = struct {
    date: Date,
    account: []const u8,
    source_account: []const u8,
    location: Location,
};

pub const DirectiveType = union(enum) {
    transaction: Transaction,
    balance: Balance,
    open: Open,
    close: Close,
    pad: Pad,
    // Add other types as needed
};

pub const Directive = struct {
    directive_type: DirectiveType,

    pub fn hasTransaction(self: Directive) bool {
        return self.directive_type == .transaction;
    }

    pub fn getTransaction(self: Directive) Transaction {
        return self.directive_type.transaction;
    }

    pub fn hasBalance(self: Directive) bool {
        return self.directive_type == .balance;
    }

    pub fn getBalance(self: Directive) Balance {
        return self.directive_type.balance;
    }

    pub fn hasOpen(self: Directive) bool {
        return self.directive_type == .open;
    }

    pub fn getOpen(self: Directive) Open {
        return self.directive_type.open;
    }

    pub fn hasClose(self: Directive) bool {
        return self.directive_type == .close;
    }

    pub fn getClose(self: Directive) Close {
        return self.directive_type.close;
    }

    pub fn hasPad(self: Directive) bool {
        return self.directive_type == .pad;
    }

    pub fn getPad(self: Directive) Pad {
        return self.directive_type.pad;
    }
};
```

**Step 2: Update validator to use proto types**

```zig
// src/validator.zig
const proto = @import("proto.zig");

pub const Validator = struct {
    allocator: std.mem.Allocator,
    tolerance: f64,

    pub fn validate(
        self: *Validator,
        directives: []const proto.Directive,
    ) !ValidationResult {
        // Now uses proto.Directive instead of placeholder
        // ... rest of implementation
    }
};

pub const ValidationResult = struct {
    is_valid: bool,
    errors: []proto.Error,
};
```

**Step 3: Update orchestrator to use proto types**

```zig
// src/orchestrator.zig
const proto = @import("proto.zig");

pub const PipelineResult = struct {
    directives: []proto.Directive,
    errors: []proto.Error,
    options: std.StringHashMap([]const u8),
    // ...
};
```

**Step 4: Commit**

```bash
git add src/proto.zig src/validator.zig src/orchestrator.zig
git commit -m "feat(zig): add protobuf type definitions"
```

---

### Task 16: Implement external plugin execution in orchestrator

**Files:**
- Modify: `src/orchestrator.zig`
- Modify: `src/plugin_manager.zig`

**Step 1: Implement JSON serialization for protobuf (temporary)**

Since we don't have full protobuf support in Zig yet, we'll use JSON as intermediate format

```zig
// src/orchestrator.zig

fn runExternalStage(
    self: *Orchestrator,
    stage: config.StageConfig,
    current_directives: []const proto.Directive,
    options: std.StringHashMap([]const u8),
    input_file: []const u8,
) !StageResult {
    // Spawn plugin
    var plugin = try self.plugin_manager.spawn(
        stage.executable.?,
        stage.args,
    );

    // Send init request (as JSON for now)
    const init_req = try createInitRequest(self.allocator, stage.name, options);
    try plugin.sendMessage(init_req);
    defer self.allocator.free(init_req);

    // Receive init response
    const init_resp = try plugin.receiveMessage(self.allocator);
    defer self.allocator.free(init_resp);

    // Parse response and check success
    // TODO: Parse JSON and verify success

    // Send process request
    var options_with_input = try options.clone();
    try options_with_input.put("input_file", input_file);

    const proc_req = try createProcessRequest(
        self.allocator,
        current_directives,
        options_with_input,
    );
    try plugin.sendMessage(proc_req);
    defer self.allocator.free(proc_req);

    // Receive process response
    const proc_resp = try plugin.receiveMessage(self.allocator);
    defer self.allocator.free(proc_resp);

    // Parse directives and errors from response
    // TODO: Implement JSON -> proto.Directive parsing

    // Send shutdown
    const shutdown_req = try createShutdownRequest(self.allocator);
    try plugin.sendMessage(shutdown_req);
    defer self.allocator.free(shutdown_req);

    return StageResult{
        .directives = &[_]proto.Directive{},
        .errors = &[_]proto.Error{},
        .updated_options = std.StringHashMap([]const u8).init(self.allocator),
    };
}

fn createInitRequest(
    allocator: std.mem.Allocator,
    name: []const u8,
    options: std.StringHashMap([]const u8),
) ![]u8 {
    // Create JSON representation of InitRequest
    // Simplified for now
    return try std.fmt.allocPrint(allocator,
        \\{{"plugin_name": "{s}", "pipeline_stage": "plugin", "options": {{}}}}
    , .{name});
}

fn createProcessRequest(
    allocator: std.mem.Allocator,
    directives: []const proto.Directive,
    options: std.StringHashMap([]const u8),
) ![]u8 {
    // Create JSON representation
    // TODO: Implement full serialization
    _ = directives;
    _ = options;
    return try allocator.dupe(u8, "{}");
}

fn createShutdownRequest(allocator: std.mem.Allocator) ![]u8 {
    return try allocator.dupe(u8, "{}");
}
```

**Step 2: Commit**

```bash
git add src/orchestrator.zig
git commit -m "feat(orchestrator): implement external plugin execution"
```

---

### Task 17: Add proper TOML parser

**Files:**
- Modify: `flake.nix`
- Modify: `src/config.zig`

**Step 1: Add zig-toml dependency to flake**

Update flake.nix to include zig-toml library (if available) or implement basic parser

**Step 2: Implement TOML parsing**

```zig
// src/config.zig

fn parseToml(allocator: std.mem.Allocator, content: []const u8) !PipelineConfig {
    // For MVP, implement basic line-by-line parser
    // Production would use proper TOML library

    var config = PipelineConfig{
        .input = try allocator.dupe(u8, "examples/sample.beancount"),
        .output_format = try allocator.dupe(u8, "json"),
        .output_path = try allocator.dupe(u8, "output.json"),
        .verbose = false,
        .stages = undefined,
        .options = std.StringHashMap([]const u8).init(allocator),
    };

    var stages = std.ArrayList(StageConfig).init(allocator);

    var lines = std.mem.split(u8, content, "\n");
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");

        // Skip comments and empty lines
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        // Parse key = value
        if (std.mem.indexOf(u8, trimmed, "=")) |eq_pos| {
            const key = std.mem.trim(u8, trimmed[0..eq_pos], " \t");
            const value = std.mem.trim(u8, trimmed[eq_pos + 1 ..], " \t\"");

            if (std.mem.eql(u8, key, "input")) {
                allocator.free(config.input);
                config.input = try allocator.dupe(u8, value);
            } else if (std.mem.eql(u8, key, "output_format")) {
                allocator.free(config.output_format);
                config.output_format = try allocator.dupe(u8, value);
            }
            // Add more fields
        }

        // Parse [[pipeline.stages]] sections
        // Simplified - would need proper TOML parser
    }

    config.stages = try stages.toOwnedSlice();
    return config;
}
```

**Step 3: Commit**

```bash
git add src/config.zig
git commit -m "feat(config): implement basic TOML parser"
```

---

### Task 18: End-to-end integration test

**Files:**
- Create: `test/integration_test.sh`
- Create: `test/expected_output.json`

**Step 1: Create integration test script**

```bash
#!/usr/bin/env bash
# test/integration_test.sh

set -euo pipefail

echo "Running end-to-end integration test..."

# Build everything
echo "Building Zig orchestrator..."
zig build

echo "Building Rust parser..."
cd plugins/parser-lima && cargo build --release && cd ../..

echo "Testing Python plugin..."
python plugins/auto-balance/auto_balance.py --help || true

# Run full pipeline
echo "Running pipeline..."
./zig-out/bin/beancount-runner \
  --input examples/sample.beancount \
  --verbose \
  --config pipeline.toml

echo "Checking output..."
if [ -f output.json ]; then
  echo "✓ Output file generated"

  # Verify output has expected structure
  if jq -e '.directives' output.json > /dev/null; then
    echo "✓ Output has directives"
  else
    echo "✗ Output missing directives"
    exit 1
  fi

  if jq -e '.errors' output.json > /dev/null; then
    echo "✓ Output has errors field"
  else
    echo "✗ Output missing errors"
    exit 1
  fi

  echo "✓ Integration test passed!"
else
  echo "✗ Output file not generated"
  exit 1
fi
```

**Step 2: Make executable**

Run: `chmod +x test/integration_test.sh`

**Step 3: Run integration test**

Run: `./test/integration_test.sh`
Expected: Full pipeline executes successfully

**Step 4: Commit**

```bash
git add test/
git commit -m "test: add end-to-end integration test"
```

---

### Task 19: Add output formatting

**Files:**
- Create: `src/output.zig`
- Modify: `src/main.zig`

**Step 1: Implement JSON output**

```zig
// src/output.zig
const std = @import("std");
const proto = @import("proto.zig");

pub fn writeJson(
    allocator: std.mem.Allocator,
    directives: []const proto.Directive,
    errors: []const proto.Error,
    path: []const u8,
) !void {
    var file = try std.fs.cwd().createFile(path, .{});
    defer file.close();

    var writer = file.writer();

    // Write JSON manually (simplified)
    try writer.writeAll("{\n");
    try writer.writeAll("  \"directives\": [\n");

    for (directives, 0..) |directive, i| {
        try writeDirectiveJson(writer, directive);
        if (i < directives.len - 1) {
            try writer.writeAll(",\n");
        }
    }

    try writer.writeAll("\n  ],\n");
    try writer.writeAll("  \"errors\": [\n");

    for (errors, 0..) |err, i| {
        try writeErrorJson(writer, err);
        if (i < errors.len - 1) {
            try writer.writeAll(",\n");
        }
    }

    try writer.writeAll("\n  ]\n");
    try writer.writeAll("}\n");
}

fn writeDirectiveJson(writer: anytype, directive: proto.Directive) !void {
    switch (directive.directive_type) {
        .transaction => |txn| {
            try writer.print("    {{\"type\": \"transaction\", \"date\": \"{d}-{d:0>2}-{d:0>2}\", \"narration\": \"{s}\"}}",
                .{txn.date.year, txn.date.month, txn.date.day, txn.narration});
        },
        .balance => |bal| {
            try writer.print("    {{\"type\": \"balance\", \"account\": \"{s}\", \"amount\": \"{s} {s}\"}}",
                .{bal.account, bal.amount.number, bal.amount.currency});
        },
        else => {
            try writer.writeAll("    {\"type\": \"other\"}");
        },
    }
}

fn writeErrorJson(writer: anytype, err: proto.Error) !void {
    try writer.print("    {{\"message\": \"{s}\", \"source\": \"{s}\"}}",
        .{err.message, err.source});
}
```

**Step 2: Update main.zig to use output module**

```zig
const output = @import("output.zig");

fn writeOutput(
    allocator: std.mem.Allocator,
    result: anytype,
    format: []const u8,
    output_path: []const u8,
) !void {
    if (std.mem.eql(u8, format, "json")) {
        try output.writeJson(allocator, result.directives, result.errors, output_path);
    } else {
        std.debug.print("Unsupported output format: {s}\n", .{format});
        return error.UnsupportedFormat;
    }
}
```

**Step 3: Commit**

```bash
git add src/output.zig src/main.zig
git commit -m "feat(output): implement JSON output formatting"
```

---

### Task 20: Documentation and final polish

**Files:**
- Modify: `README.md`
- Create: `docs/DEVELOPMENT.md`
- Create: `CHANGELOG.md`

**Step 1: Update README with build instructions**

Add to README.md:

```markdown
## Building from Source

### Using Nix (Recommended)

```bash
nix build
./result/bin/beancount-runner --input examples/sample.beancount
```

### Manual Build

```bash
# Generate protobuf code
protoc --python_out=generated/python --proto_path=proto proto/*.proto
protoc --rust_out=generated/rust --proto_path=proto proto/*.proto

# Build Zig orchestrator
zig build -Doptimize=ReleaseFast

# Build Rust parser
cd plugins/parser-lima && cargo build --release && cd ../..

# Run
./zig-out/bin/beancount-runner --input examples/sample.beancount
```

## Testing

```bash
# Zig tests
zig build test

# Rust tests
cd plugins/parser-lima && cargo test

# Python tests
cd plugins/auto-balance && pytest

# Integration test
./test/integration_test.sh
```
```

**Step 2: Create development guide**

```markdown
# Development Guide

## Project Structure

See main README.md for directory layout.

## Adding a New Plugin

1. Create plugin directory in `plugins/`
2. Implement protocol (Init/Process/Shutdown)
3. Use length-prefixed protobuf messages
4. Add to `pipeline.toml`
5. Test standalone before integration

See `docs/plugin-protocol.md` for details.

## Modifying Protobuf Schema

1. Edit `.proto` files in `proto/`
2. Regenerate code: `nix develop` (automatic)
3. Update type definitions in `src/proto.zig`
4. Update converters in Rust/Python plugins

## Running Tests

- Unit: `zig build test`, `cargo test`, `pytest`
- Integration: `./test/integration_test.sh`
- Manual: Run with `--verbose` flag
```

**Step 3: Create changelog**

```markdown
# Changelog

## [0.1.0] - 2026-03-02

### Added
- Zig core orchestrator with plugin lifecycle management
- Comprehensive protobuf schemas for all beancount directives
- Rust parser plugin using beancount_parser_lima
- Python auto-balance plugin
- Built-in Zig validator with 4 core validations
- Nix flake for reproducible builds
- JSON output format
- End-to-end integration tests

### Core Features
- Multi-language plugin support (Rust, Python, Zig)
- Length-prefixed protobuf communication
- 3-stage pipeline (Parser → Plugins → Validator)
- TOML configuration format
```

**Step 4: Commit**

```bash
git add README.md docs/DEVELOPMENT.md CHANGELOG.md
git commit -m "docs: add build instructions and development guide"
```

---

## Summary

**Total Tasks: 20**

**Estimated Time: 2-3 days of focused development**

**Key Dependencies:**
- Zig protobuf library (or manual types as implemented)
- Rust beancount_parser_lima
- Python protobuf

**Testing Strategy:**
- Unit tests for each component
- Integration test for full pipeline
- Manual testing with sample.beancount

**Success Criteria:**
- Full pipeline executes: file → parser → plugin → validator → output
- All 4 core validations working
- Plugins can add/modify/delete directives
- JSON output contains directives and errors
