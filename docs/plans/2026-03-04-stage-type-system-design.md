# Stage Type System Design

**Date:** 2026-03-04
**Status:** Approved

## Overview

Add formal stage types (parsing, booking, transformation, validation) to the beancount-runner architecture with runtime enforcement of stage ordering. Python beancount serves as the reference implementation demonstrating both parsing and booking stages.

## Goals

1. **Formalize stage types** - Make parsing, booking, transformation, and validation first-class architectural concepts
2. **Enforce ordering** - Validate stage order at pipeline initialization
3. **Reference implementation** - Provide Python beancount plugin as canonical example
4. **Clear contracts** - Document what each stage type does and expects

## Non-Goals (YAGNI)

- Dynamic stage reordering
- Conditional stage execution
- Stage type inference in production (only during migration)
- Multiple parsing stages in one pipeline

## Architecture

### Current State

The pipeline is a linear sequence of stages with no formal stage type concept:
```
Parser-lima → Auto-balance → Validator
```

### New State

Stages are categorized by type, with enforced ordering:
```
[Parsing] → [Booking] → [Transformation]* → [Validation]
```

### Stage Type Hierarchy

1. **Parsing** - Text input → raw directives (required, must be first)
2. **Booking** - Raw directives → booked directives with interpolated amounts and computed balances (optional)
3. **Transformation** - Directive modifications (optional, repeatable)
4. **Validation** - Directive checking, error collection (optional, must be last if present)

### Key Properties

- Stage types enforce ordering at pipeline initialization
- Multiple transformation stages allowed (e.g., auto-balance, categorization)
- Parsing is required; booking and validation are optional
- A single plugin can implement multiple stage types (e.g., Python beancount does parsing + booking)

### Orchestrator Responsibilities

- Load pipeline.toml and validate stage order
- Reject invalid configurations (e.g., validation before parsing)
- Pass directives through stages according to type ordering

## Stage Type Definitions

### Parsing Stage

- **Input:** File path (via InitRequest) or empty directive list
- **Output:** Raw directives (no interpolation, no balance computation)
- **Responsibilities:**
  - Tokenize and parse beancount syntax
  - Convert to protobuf directive structures
  - Preserve source location metadata (file:line)
  - Report syntax errors
- **Must NOT:** Interpolate amounts, compute balances, modify directives
- **Examples:** parser-lima (Rust), Python beancount parser

### Booking Stage

- **Input:** Raw directives from parsing
- **Output:** Booked directives with interpolated amounts and computed balances
- **Responsibilities:**
  - Interpolate missing transaction amounts (auto-balance single posting)
  - Compute running balances per account per currency
  - Process Pad directives (generate automatic transactions)
  - Validate that transactions balance within tolerance
  - Report booking errors (unbalanced transactions, multiple missing amounts)
- **Must NOT:** Parse text, modify directive order, add new directive types beyond pads
- **Examples:** Python beancount booking, custom Zig booking implementation

### Transformation Stage

- **Input:** Directives (raw or booked)
- **Output:** Modified directives
- **Responsibilities:**
  - Add, modify, or remove directives
  - Apply business logic (categorization, splitting, etc.)
  - Can be chained (multiple transformation stages)
- **Examples:** auto-balance plugin, tag adder, account renamer

### Validation Stage

- **Input:** Directives (should be booked if booking stage ran)
- **Output:** Same directives + validation errors
- **Responsibilities:**
  - Check balance assertions
  - Verify account usage (accounts opened before use)
  - Check date ordering
  - Collect all validation errors without modifying directives
- **Must NOT:** Modify directives
- **Examples:** Current Zig validator

### Combined Stages

A single plugin can implement multiple sequential stage types (e.g., `stage_type = "parsing+booking"`). The orchestrator treats this as one stage that performs both functions.

## Configuration Changes

### New Field in pipeline.toml

Add `stage_type` field to each stage configuration:

```toml
[[pipeline.stages]]
name = "parser"
type = "external"
stage_type = "parsing"  # NEW: required field
executable = "./plugins/parser-lima/target/release/parser-lima"
language = "rust"

[[pipeline.stages]]
name = "auto-balance"
type = "external"
stage_type = "transformation"  # NEW: was implicit before
executable = "python"
args = ["./plugins/auto-balance/auto_balance.py"]
language = "python"

[[pipeline.stages]]
name = "validator"
type = "builtin"
stage_type = "validation"  # NEW: required field
function = "validate_all"
```

### Valid stage_type Values

- `"parsing"`
- `"booking"`
- `"transformation"`
- `"validation"`
- `"parsing+booking"` (combined stages)

### Python Beancount Example

```toml
[[pipeline.stages]]
name = "python-beancount"
type = "external"
stage_type = "parsing+booking"  # Combined stage
executable = "python"
args = ["./plugins/python-beancount/beancount_plugin.py"]
language = "python"

# Optional: additional transformations
[[pipeline.stages]]
name = "custom-categorizer"
type = "external"
stage_type = "transformation"
executable = "python"
args = ["./plugins/categorizer/categorize.py"]

# Optional: validation
[[pipeline.stages]]
name = "validator"
type = "builtin"
stage_type = "validation"
function = "validate_all"
```

### Validation Rules (enforced by orchestrator)

1. At least one `parsing` stage must exist
2. `parsing` must come before all other stages
3. If `booking` exists, it must come after `parsing` and before `transformation`/`validation`
4. `validation` must be last if present
5. `transformation` stages can appear in any order between booking and validation

### Error Examples

```toml
# INVALID: validation before parsing
[[pipeline.stages]]
stage_type = "validation"
# ...
[[pipeline.stages]]
stage_type = "parsing"
# Error: "Parsing stage must come first"

# INVALID: no parsing stage
[[pipeline.stages]]
stage_type = "transformation"
# Error: "Pipeline must include at least one parsing stage"
```

## Orchestrator Implementation

### New Data Structures (src/config.zig)

```zig
pub const StageType = enum {
    parsing,
    booking,
    transformation,
    validation,
    parsing_booking, // Combined stage

    pub fn fromString(s: []const u8) !StageType {
        if (std.mem.eql(u8, s, "parsing")) return .parsing;
        if (std.mem.eql(u8, s, "booking")) return .booking;
        if (std.mem.eql(u8, s, "transformation")) return .transformation;
        if (std.mem.eql(u8, s, "validation")) return .validation;
        if (std.mem.eql(u8, s, "parsing+booking")) return .parsing_booking;
        return error.InvalidStageType;
    }
};

pub const StageConfig = struct {
    name: []const u8,
    type: StageType,  // existing: "external" | "builtin"
    stage_type: StageType,  // NEW
    executable: ?[]const u8,
    args: ?[][]const u8,
    language: ?[]const u8,
    function: ?[]const u8,
};
```

### Validation Logic (src/config.zig)

```zig
pub fn validatePipelineStages(stages: []const StageConfig) !void {
    if (stages.len == 0) {
        return error.EmptyPipeline;
    }

    // Rule 1: At least one parsing stage
    var has_parsing = false;
    for (stages) |stage| {
        if (stage.stage_type == .parsing or stage.stage_type == .parsing_booking) {
            has_parsing = true;
            break;
        }
    }
    if (!has_parsing) {
        return error.NoParsingStageDefined;
    }

    // Rule 2: Enforce stage ordering
    var current_phase: u8 = 0; // 0=parsing, 1=booking, 2=transformation, 3=validation

    for (stages) |stage| {
        const phase = switch (stage.stage_type) {
            .parsing, .parsing_booking => 0,
            .booking => 1,
            .transformation => 2,
            .validation => 3,
        };

        if (phase < current_phase) {
            std.log.err("Invalid stage order: {s} (type={s}) cannot come after phase {d}",
                .{ stage.name, @tagName(stage.stage_type), current_phase });
            return error.InvalidStageOrder;
        }

        // Allow same phase (multiple transformations)
        if (phase > current_phase) {
            current_phase = phase;
        }
    }
}
```

### TOML Parsing Update (src/config.zig)

Add `stage_type` parsing to the existing TOML parser:

```zig
// In parseStage() function
const stage_type_str = // ... parse from TOML
const stage_type = StageType.fromString(stage_type_str) catch |err| {
    std.log.err("Invalid stage_type '{s}' for stage '{s}'", .{ stage_type_str, name });
    return err;
};
```

### Error Messages

Clear error messages when validation fails:
- `"Pipeline must include at least one parsing stage"`
- `"Stage 'validator' (type=validation) cannot come before stage 'parser' (type=parsing)"`
- `"Invalid stage_type 'unknown' in stage 'my-stage'. Valid types: parsing, booking, transformation, validation, parsing+booking"`

## Python Beancount Reference Implementation

### Purpose

Demonstrate a plugin that implements both parsing and booking stages using Python's official beancount library as the reference implementation.

### Plugin Structure

```
plugins/python-beancount/
├── beancount_plugin.py      # Main plugin entry point
├── parsing.py                # Text → directives
├── booking.py                # Directives → booked directives
├── proto_conversion.py       # Beancount types ↔ protobuf
└── requirements.txt          # beancount>=2.3.6
```

### High-Level Flow

```python
# beancount_plugin.py
import beancount.loader
from beancount.parser import booking

def main():
    # 1. Handle init
    init_req = read_message(InitRequest)
    write_message(InitResponse(success=True, plugin_version="0.1.0"))

    # 2. Process request
    req = read_message(ProcessRequest)
    input_file = req.input_file  # From InitRequest

    # PARSING: Load beancount file
    entries, errors, options = beancount.loader.load_file(input_file)

    # BOOKING: Apply beancount's booking logic
    booked_entries, booking_errors = booking.book(entries, options)

    # Convert to protobuf
    pb_directives = convert_entries_to_protobuf(booked_entries)
    pb_errors = convert_errors_to_protobuf(errors + booking_errors)

    # Send response
    write_message(ProcessResponse(
        directives=pb_directives,
        errors=pb_errors,
        options=convert_options_to_protobuf(options)
    ))
```

### What Python Beancount's Booking Does

1. **Amount Interpolation:**
   ```python
   2024-01-15 * "Groceries"
     Assets:Checking    -50.00 USD
     Expenses:Food              # Missing amount auto-filled to 50.00 USD
   ```

2. **Balance Computation:**
   Tracks running balances for each account/currency pair

3. **Pad Directive Processing:**
   ```python
   2024-01-01 open Assets:Checking
   2024-01-15 pad Assets:Checking Equity:Opening-Balances
   2024-01-20 balance Assets:Checking 1000.00 USD
   # Booking generates transaction to make balance match
   ```

4. **Transaction Validation:**
   Ensures transactions balance within tolerance before proceeding

### Configuration Example

```toml
# Use Python beancount for parsing+booking
[[pipeline.stages]]
name = "python-beancount"
type = "external"
stage_type = "parsing+booking"
executable = "python"
args = ["./plugins/python-beancount/beancount_plugin.py"]
language = "python"

# Optional: add custom transformations
[[pipeline.stages]]
name = "tag-adder"
type = "external"
stage_type = "transformation"
executable = "python"
args = ["./plugins/tag-adder/tag_adder.py"]

# Optional: additional validation
[[pipeline.stages]]
name = "validator"
type = "builtin"
stage_type = "validation"
function = "validate_all"
```

### Alternative: Separate Parsing and Booking Plugins

Users can also split these into separate plugins:

```toml
[[pipeline.stages]]
name = "python-parser"
type = "external"
stage_type = "parsing"
executable = "python"
args = ["./plugins/python-beancount/parser_only.py"]

[[pipeline.stages]]
name = "python-booking"
type = "external"
stage_type = "booking"
executable = "python"
args = ["./plugins/python-beancount/booking_only.py"]
```

### Benefits of Python Beancount as Reference

- Canonical implementation from original beancount
- Demonstrates all booking behaviors correctly
- Users can compare custom booking implementations against it
- Validates that protobuf schema supports all beancount features

## Migration Path

### Existing Pipeline (Before)

```toml
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
```

### Migrated Pipeline (After)

```toml
[[pipeline.stages]]
name = "parser"
type = "external"
stage_type = "parsing"  # ADD THIS
executable = "./plugins/parser-lima/target/release/parser-lima"
language = "rust"

[[pipeline.stages]]
name = "auto-balance"
type = "external"
stage_type = "transformation"  # ADD THIS
executable = "python"
args = ["./plugins/auto-balance/auto_balance.py"]
language = "python"

[[pipeline.stages]]
name = "validator"
type = "builtin"
stage_type = "validation"  # ADD THIS
function = "validate_all"
```

### Migration Strategy

**Phase 1: Add stage_type field** (backward compatible)
- Make `stage_type` optional initially
- If missing, infer from stage position and name
- Log warning: "stage_type not specified for stage 'parser', inferring 'parsing'"

**Phase 2: Make stage_type required** (breaking change)
- After 1-2 releases, make `stage_type` mandatory
- Provide migration tool: `./scripts/migrate_pipeline_config.sh pipeline.toml`
- Update all example configs and documentation

**Phase 3: Validation enforcement**
- Enforce stage ordering rules
- Provide clear error messages with fix suggestions

### Inference Rules (Phase 1 only)

```zig
fn inferStageType(stage: StageConfig, position: usize, total: usize) StageType {
    // First stage → parsing
    if (position == 0) return .parsing;

    // Last stage named "validator" or "validate" → validation
    if (position == total - 1 and
        (std.mem.eql(u8, stage.name, "validator") or
         std.mem.eql(u8, stage.name, "validate"))) {
        return .validation;
    }

    // Everything else → transformation
    return .transformation;
}
```

## Documentation Updates

Files to update:
- `docs/architecture.md` - Add "Parsing and Booking Stages" section
- `docs/plugin-protocol.md` - Document stage type contracts
- `README.md` - Update pipeline examples
- `examples/*/pipeline.toml` - Add stage_type to all examples

## Testing Strategy

1. **Config validation tests** - Test all validation rules
2. **Invalid config tests** - Ensure clear error messages
3. **Migration tests** - Verify inference logic works correctly
4. **Integration tests** - Existing pipelines work with new field

## Files Modified

- `src/config.zig` - Add StageType enum, validation logic, TOML parsing (~150 lines)
- `src/orchestrator.zig` - Call validatePipelineStages() during initialization (~5 lines)
- `docs/architecture.md` - Add stage types section (~200 lines)
- `docs/plugin-protocol.md` - Document stage type contracts (~150 lines)
- `README.md` - Update examples (~50 lines)
- `pipeline.toml` - Add stage_type fields (~3 lines)
- `examples/*/pipeline.toml` - Add stage_type to all examples (~10 lines)
- `plugins/python-beancount/` - New reference implementation (~500 lines)

## Success Criteria

- Pipeline configuration with stage_type validates correctly
- Invalid configurations produce clear error messages
- Python beancount plugin successfully parses and books test files
- Existing pipelines work with inferred stage types
- All documentation updated with stage type examples
- Integration tests pass with new configuration format
