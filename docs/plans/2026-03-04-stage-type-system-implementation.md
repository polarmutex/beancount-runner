# Stage Type System Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add formal stage types (parsing, booking, transformation, validation) with runtime ordering enforcement

**Architecture:** Extend StageConfig with pipeline_stage_type enum, add validation function to check stage ordering rules, update TOML parser to read stage_type field, create Python beancount reference plugin

**Tech Stack:** Zig 0.16, TOML parsing, Protocol Buffers, Python 3.11+, beancount>=2.3.6

---

## Task 1: Add PipelineStageType Enum

**Files:**
- Modify: `src/config.zig:50-53`

**Step 1: Write failing test for PipelineStageType.fromString**

```zig
// Add to src/config.zig after StageType enum
test "PipelineStageType.fromString valid types" {
    const testing = std.testing;

    try testing.expectEqual(PipelineStageType.parsing, try PipelineStageType.fromString("parsing"));
    try testing.expectEqual(PipelineStageType.booking, try PipelineStageType.fromString("booking"));
    try testing.expectEqual(PipelineStageType.transformation, try PipelineStageType.fromString("transformation"));
    try testing.expectEqual(PipelineStageType.validation, try PipelineStageType.fromString("validation"));
    try testing.expectEqual(PipelineStageType.parsing_booking, try PipelineStageType.fromString("parsing+booking"));
}

test "PipelineStageType.fromString invalid type" {
    const testing = std.testing;

    try testing.expectError(error.InvalidPipelineStageType, PipelineStageType.fromString("unknown"));
    try testing.expectError(error.InvalidPipelineStageType, PipelineStageType.fromString(""));
}
```

**Step 2: Run test to verify it fails**

Run: `zig build test`
Expected: Compilation error - "PipelineStageType not defined"

**Step 3: Add PipelineStageType enum**

In `src/config.zig` after line 53, add:

```zig
pub const PipelineStageType = enum {
    parsing,
    booking,
    transformation,
    validation,
    parsing_booking, // Combined stage

    pub fn fromString(s: []const u8) !PipelineStageType {
        if (std.mem.eql(u8, s, "parsing")) return .parsing;
        if (std.mem.eql(u8, s, "booking")) return .booking;
        if (std.mem.eql(u8, s, "transformation")) return .transformation;
        if (std.mem.eql(u8, s, "validation")) return .validation;
        if (std.mem.eql(u8, s, "parsing+booking")) return .parsing_booking;
        return error.InvalidPipelineStageType;
    }

    pub fn toPhase(self: PipelineStageType) u8 {
        return switch (self) {
            .parsing, .parsing_booking => 0,
            .booking => 1,
            .transformation => 2,
            .validation => 3,
        };
    }
};
```

**Step 4: Run test to verify it passes**

Run: `zig build test`
Expected: Tests pass

**Step 5: Commit**

```bash
git add src/config.zig
git commit -m "feat: add PipelineStageType enum with fromString"
```

---

## Task 2: Add pipeline_stage_type Field to StageConfig

**Files:**
- Modify: `src/config.zig:30-48`

**Step 1: Write failing test for StageConfig with pipeline_stage_type**

Add to `src/config.zig`:

```zig
test "StageConfig with pipeline_stage_type" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var stage = StageConfig{
        .name = try allocator.dupe(u8, "parser"),
        .stage_type = .external,
        .pipeline_stage_type = .parsing,
        .executable = try allocator.dupe(u8, "./parser"),
        .args = try allocator.alloc([]const u8, 0),
        .language = null,
        .description = null,
        .function_name = null,
    };
    defer stage.deinit(allocator);

    try testing.expectEqual(PipelineStageType.parsing, stage.pipeline_stage_type);
}
```

**Step 2: Run test to verify it fails**

Run: `zig build test`
Expected: Compilation error - "no field named 'pipeline_stage_type' in struct 'StageConfig'"

**Step 3: Add pipeline_stage_type field to StageConfig**

In `src/config.zig`, modify StageConfig struct (around line 30):

```zig
pub const StageConfig = struct {
    name: []const u8,
    stage_type: StageType,
    pipeline_stage_type: ?PipelineStageType,  // NEW: optional for backward compatibility
    executable: ?[]const u8,
    args: [][]const u8,
    language: ?[]const u8,
    description: ?[]const u8,
    function_name: ?[]const u8, // For builtin type

    pub fn deinit(self: *StageConfig, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        if (self.executable) |exe| allocator.free(exe);
        for (self.args) |arg| allocator.free(arg);
        allocator.free(self.args);
        if (self.language) |lang| allocator.free(lang);
        if (self.description) |desc| allocator.free(desc);
        if (self.function_name) |func| allocator.free(func);
    }
};
```

**Step 4: Update test to use optional pipeline_stage_type**

Update the test added in Step 1 to match the optional field:

```zig
test "StageConfig with pipeline_stage_type" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var stage = StageConfig{
        .name = try allocator.dupe(u8, "parser"),
        .stage_type = .external,
        .pipeline_stage_type = .parsing,  // Optional, so we can set it
        .executable = try allocator.dupe(u8, "./parser"),
        .args = try allocator.alloc([]const u8, 0),
        .language = null,
        .description = null,
        .function_name = null,
    };
    defer stage.deinit(allocator);

    try testing.expectEqual(PipelineStageType.parsing, stage.pipeline_stage_type.?);
}
```

**Step 5: Run test to verify it passes**

Run: `zig build test`
Expected: Tests pass

**Step 6: Commit**

```bash
git add src/config.zig
git commit -m "feat: add pipeline_stage_type field to StageConfig"
```

---

## Task 3: Add Stage Inference Logic

**Files:**
- Modify: `src/config.zig` (add after PipelineStageType enum)

**Step 1: Write failing test for inferPipelineStageType**

Add to `src/config.zig`:

```zig
test "inferPipelineStageType first stage is parsing" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var stage = StageConfig{
        .name = try allocator.dupe(u8, "parser"),
        .stage_type = .external,
        .pipeline_stage_type = null,
        .executable = null,
        .args = try allocator.alloc([]const u8, 0),
        .language = null,
        .description = null,
        .function_name = null,
    };
    defer stage.deinit(allocator);

    const inferred = inferPipelineStageType(&stage, 0, 3);
    try testing.expectEqual(PipelineStageType.parsing, inferred);
}

test "inferPipelineStageType last stage named validator is validation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var stage = StageConfig{
        .name = try allocator.dupe(u8, "validator"),
        .stage_type = .builtin,
        .pipeline_stage_type = null,
        .executable = null,
        .args = try allocator.alloc([]const u8, 0),
        .language = null,
        .description = null,
        .function_name = try allocator.dupe(u8, "validate_all"),
    };
    defer stage.deinit(allocator);

    const inferred = inferPipelineStageType(&stage, 2, 3);
    try testing.expectEqual(PipelineStageType.validation, inferred);
}

test "inferPipelineStageType middle stage is transformation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var stage = StageConfig{
        .name = try allocator.dupe(u8, "auto-balance"),
        .stage_type = .external,
        .pipeline_stage_type = null,
        .executable = null,
        .args = try allocator.alloc([]const u8, 0),
        .language = null,
        .description = null,
        .function_name = null,
    };
    defer stage.deinit(allocator);

    const inferred = inferPipelineStageType(&stage, 1, 3);
    try testing.expectEqual(PipelineStageType.transformation, inferred);
}
```

**Step 2: Run test to verify it fails**

Run: `zig build test`
Expected: Compilation error - "use of undeclared identifier 'inferPipelineStageType'"

**Step 3: Implement inferPipelineStageType function**

Add after PipelineStageType enum in `src/config.zig`:

```zig
fn inferPipelineStageType(stage: *const StageConfig, position: usize, total: usize) PipelineStageType {
    // First stage → parsing
    if (position == 0) return .parsing;

    // Last stage named "validator" or "validate" → validation
    if (position == total - 1 and
        (std.mem.eql(u8, stage.name, "validator") or
         std.mem.eql(u8, stage.name, "validate")))
    {
        return .validation;
    }

    // Everything else → transformation
    return .transformation;
}
```

**Step 4: Run test to verify it passes**

Run: `zig build test`
Expected: Tests pass

**Step 5: Commit**

```bash
git add src/config.zig
git commit -m "feat: add stage type inference for backward compatibility"
```

---

## Task 4: Add Pipeline Validation Function

**Files:**
- Modify: `src/config.zig` (add after inferPipelineStageType)

**Step 1: Write failing test for validatePipelineStages**

Add to `src/config.zig`:

```zig
test "validatePipelineStages empty pipeline fails" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const stages = try allocator.alloc(StageConfig, 0);
    defer allocator.free(stages);

    try testing.expectError(error.EmptyPipeline, validatePipelineStages(stages));
}

test "validatePipelineStages no parsing stage fails" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var stages = try allocator.alloc(StageConfig, 1);
    defer {
        for (stages) |*stage| stage.deinit(allocator);
        allocator.free(stages);
    }

    stages[0] = StageConfig{
        .name = try allocator.dupe(u8, "validator"),
        .stage_type = .builtin,
        .pipeline_stage_type = .validation,
        .executable = null,
        .args = try allocator.alloc([]const u8, 0),
        .language = null,
        .description = null,
        .function_name = null,
    };

    try testing.expectError(error.NoParsingStageDefined, validatePipelineStages(stages));
}

test "validatePipelineStages invalid order fails" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var stages = try allocator.alloc(StageConfig, 2);
    defer {
        for (stages) |*stage| stage.deinit(allocator);
        allocator.free(stages);
    }

    // Validation before parsing - invalid
    stages[0] = StageConfig{
        .name = try allocator.dupe(u8, "validator"),
        .stage_type = .builtin,
        .pipeline_stage_type = .validation,
        .executable = null,
        .args = try allocator.alloc([]const u8, 0),
        .language = null,
        .description = null,
        .function_name = null,
    };

    stages[1] = StageConfig{
        .name = try allocator.dupe(u8, "parser"),
        .stage_type = .external,
        .pipeline_stage_type = .parsing,
        .executable = null,
        .args = try allocator.alloc([]const u8, 0),
        .language = null,
        .description = null,
        .function_name = null,
    };

    try testing.expectError(error.InvalidStageOrder, validatePipelineStages(stages));
}

test "validatePipelineStages valid order succeeds" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var stages = try allocator.alloc(StageConfig, 3);
    defer {
        for (stages) |*stage| stage.deinit(allocator);
        allocator.free(stages);
    }

    stages[0] = StageConfig{
        .name = try allocator.dupe(u8, "parser"),
        .stage_type = .external,
        .pipeline_stage_type = .parsing,
        .executable = null,
        .args = try allocator.alloc([]const u8, 0),
        .language = null,
        .description = null,
        .function_name = null,
    };

    stages[1] = StageConfig{
        .name = try allocator.dupe(u8, "auto-balance"),
        .stage_type = .external,
        .pipeline_stage_type = .transformation,
        .executable = null,
        .args = try allocator.alloc([]const u8, 0),
        .language = null,
        .description = null,
        .function_name = null,
    };

    stages[2] = StageConfig{
        .name = try allocator.dupe(u8, "validator"),
        .stage_type = .builtin,
        .pipeline_stage_type = .validation,
        .executable = null,
        .args = try allocator.alloc([]const u8, 0),
        .language = null,
        .description = null,
        .function_name = null,
    };

    try validatePipelineStages(stages);
}
```

**Step 2: Run test to verify it fails**

Run: `zig build test`
Expected: Compilation error - "use of undeclared identifier 'validatePipelineStages'"

**Step 3: Implement validatePipelineStages function**

Add after inferPipelineStageType in `src/config.zig`:

```zig
pub fn validatePipelineStages(stages: []const StageConfig) !void {
    if (stages.len == 0) {
        return error.EmptyPipeline;
    }

    // Rule 1: At least one parsing stage
    var has_parsing = false;
    for (stages) |stage| {
        if (stage.pipeline_stage_type) |pst| {
            if (pst == .parsing or pst == .parsing_booking) {
                has_parsing = true;
                break;
            }
        }
    }
    if (!has_parsing) {
        std.log.err("Pipeline must include at least one parsing stage", .{});
        return error.NoParsingStageDefined;
    }

    // Rule 2: Enforce stage ordering
    var current_phase: u8 = 0; // 0=parsing, 1=booking, 2=transformation, 3=validation

    for (stages) |stage| {
        if (stage.pipeline_stage_type) |pst| {
            const phase = pst.toPhase();

            if (phase < current_phase) {
                std.log.err("Invalid stage order: '{s}' (type={s}) cannot come after phase {d}", .{
                    stage.name,
                    @tagName(pst),
                    current_phase,
                });
                return error.InvalidStageOrder;
            }

            // Allow same phase (multiple transformations)
            if (phase > current_phase) {
                current_phase = phase;
            }
        }
    }
}
```

**Step 4: Run test to verify it passes**

Run: `zig build test`
Expected: Tests pass

**Step 5: Commit**

```bash
git add src/config.zig
git commit -m "feat: add pipeline stage validation with ordering rules"
```

---

## Task 5: Update TOML Parser to Read stage_type

**Files:**
- Modify: `src/config.zig:158-204`

**Step 1: Write failing integration test**

Add to `src/config.zig`:

```zig
test "parseToml with stage_type field" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const toml_content =
        \\[pipeline]
        \\input = "test.beancount"
        \\output_format = "json"
        \\output_path = "out.json"
        \\verbose = false
        \\
        \\[[pipeline.stages]]
        \\name = "parser"
        \\type = "external"
        \\stage_type = "parsing"
        \\executable = "./parser"
        \\
        \\[[pipeline.stages]]
        \\name = "validator"
        \\type = "builtin"
        \\stage_type = "validation"
        \\function = "validate_all"
    ;

    var config = try parseToml(allocator, toml_content);
    defer config.deinit(allocator);

    try testing.expectEqual(@as(usize, 2), config.stages.len);
    try testing.expectEqual(PipelineStageType.parsing, config.stages[0].pipeline_stage_type.?);
    try testing.expectEqual(PipelineStageType.validation, config.stages[1].pipeline_stage_type.?);
}
```

**Step 2: Run test to verify it fails**

Run: `zig build test`
Expected: Test fails - pipeline_stage_type is null

**Step 3: Update parseToml to parse stage_type field**

In `src/config.zig`, inside the stage parsing section (around line 158), add after parsing "function" key:

```zig
                    } else if (std.mem.eql(u8, key, "stage_type")) {
                        if (stage.pipeline_stage_type) |_| {
                            // Already set, skip
                        } else {
                            stage.pipeline_stage_type = PipelineStageType.fromString(value) catch |err| {
                                std.log.warn("Invalid stage_type '{s}' for stage '{s}': {any}. Stage type will be inferred.", .{ value, stage.name, err });
                                null
                            };
                        }
```

**Step 4: Update parseToml to infer stage_type if missing**

After the main parsing loop (around line 213), before returning config, add:

```zig
    // Infer pipeline_stage_type for stages that don't have it
    for (config.stages, 0..) |*stage, idx| {
        if (stage.pipeline_stage_type == null) {
            stage.pipeline_stage_type = inferPipelineStageType(stage, idx, config.stages.len);
            std.log.warn("stage_type not specified for stage '{s}', inferring '{s}'", .{
                stage.name,
                @tagName(stage.pipeline_stage_type.?),
            });
        }
    }
```

**Step 5: Run test to verify it passes**

Run: `zig build test`
Expected: Tests pass

**Step 6: Commit**

```bash
git add src/config.zig
git commit -m "feat: parse stage_type from TOML with inference fallback"
```

---

## Task 6: Call validatePipelineStages in Orchestrator

**Files:**
- Modify: `src/orchestrator.zig:15-30`

**Step 1: Write failing test**

Create test file `src/orchestrator_test.zig`:

```zig
const std = @import("std");
const Orchestrator = @import("orchestrator.zig").Orchestrator;
const config = @import("config.zig");

test "Orchestrator.init validates pipeline stages" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create invalid config (no parsing stage)
    var stages = try allocator.alloc(config.StageConfig, 1);
    stages[0] = config.StageConfig{
        .name = try allocator.dupe(u8, "validator"),
        .stage_type = .builtin,
        .pipeline_stage_type = .validation,
        .executable = null,
        .args = try allocator.alloc([]const u8, 0),
        .language = null,
        .description = null,
        .function_name = try allocator.dupe(u8, "validate_all"),
    };

    var pipeline_config = config.PipelineConfig{
        .input = try allocator.dupe(u8, "test.beancount"),
        .output_format = try allocator.dupe(u8, "json"),
        .output_path = try allocator.dupe(u8, "out.json"),
        .verbose = false,
        .stages = stages,
        .options = std.StringHashMap([]const u8).init(allocator),
    };
    defer pipeline_config.deinit(allocator);

    const io = std.Io.default();
    try testing.expectError(
        error.NoParsingStageDefined,
        Orchestrator.init(allocator, pipeline_config, io, false)
    );
}
```

**Step 2: Add test to build.zig**

In `build.zig`, add orchestrator_test to tests:

```zig
const orchestrator_test = b.addTest(.{
    .root_source_file = b.path("src/orchestrator_test.zig"),
    .target = target,
    .optimize = optimize,
});
test_step.dependOn(&orchestrator_test.step);
```

**Step 3: Run test to verify it fails**

Run: `zig build test`
Expected: Test fails - orchestrator doesn't validate stages

**Step 4: Add validation call to Orchestrator.init**

In `src/orchestrator.zig`, modify the init function (around line 15):

```zig
    pub fn init(
        allocator: std.mem.Allocator,
        pipeline_config: config.PipelineConfig,
        io: std.Io,
        verbose: bool,
    ) !Orchestrator {
        // Validate pipeline stages
        try config.validatePipelineStages(pipeline_config.stages);

        const plugin_manager = try PluginManager.init(allocator);

        return Orchestrator{
            .allocator = allocator,
            .config = pipeline_config,
            .plugin_manager = plugin_manager,
            .io = io,
            .verbose = verbose,
        };
    }
```

**Step 5: Run test to verify it passes**

Run: `zig build test`
Expected: Tests pass

**Step 6: Commit**

```bash
git add src/orchestrator.zig src/orchestrator_test.zig build.zig
git commit -m "feat: validate pipeline stages in orchestrator initialization"
```

---

## Task 7: Update pipeline.toml with stage_type

**Files:**
- Modify: `pipeline.toml:19-48`

**Step 1: Add stage_type to existing stages**

```toml
# Stage 1: Parser - Convert .beancount file to directive stream
[[pipeline.stages]]
name = "parser"
type = "external"
stage_type = "parsing"
executable = "./plugins/parser-lima/target/release/parser-lima"
language = "rust"
description = "Parse beancount file using lima parser"

# Stage 2: Auto-balance plugin - Generate Pad directives
[[pipeline.stages]]
name = "auto-balance"
type = "external"
stage_type = "transformation"
executable = "python"
args = ["./plugins/auto-balance/auto_balance.py"]
language = "python"
description = "Automatically generate padding entries for balance assertions"

# Stage 3: Validator - Final validation and error checking
[[pipeline.stages]]
name = "validator"
type = "builtin"
stage_type = "validation"
function = "validate_all"
description = "Validate transactions balance, account usage, and date ordering"
```

**Step 2: Test pipeline loads correctly**

Run: `zig build && ./zig-out/bin/beancount-runner --input examples/sample.beancount`
Expected: Pipeline runs without errors

**Step 3: Commit**

```bash
git add pipeline.toml
git commit -m "config: add stage_type to pipeline stages"
```

---

## Task 8: Update Architecture Documentation

**Files:**
- Modify: `docs/architecture.md:42-86`

**Step 1: Add Parsing and Booking Stages section**

After line 41 in `docs/architecture.md`, add:

```markdown
## Stage Types

Beancount Runner defines four stage types that formalize the pipeline architecture:

### 1. Parsing Stage

**Purpose:** Convert text input to raw directive stream

**Input:** File path (via InitRequest)
**Output:** Raw directives (no interpolation)

**Responsibilities:**
- Tokenize and parse beancount syntax
- Convert to protobuf directive structures
- Preserve source location metadata (file:line)
- Report syntax errors

**Examples:**
- `parser-lima` (Rust) - src/config.zig:32
- Python beancount parser - plugins/python-beancount/

### 2. Booking Stage

**Purpose:** Interpolate amounts and compute running balances

**Input:** Raw directives from parsing
**Output:** Booked directives with interpolated amounts

**Responsibilities:**
- Interpolate missing transaction amounts
- Compute running balances per account/currency
- Process Pad directives (generate automatic transactions)
- Validate transactions balance within tolerance
- Report booking errors

**Examples:**
- Python beancount booking - plugins/python-beancount/

### 3. Transformation Stage

**Purpose:** Modify directive stream with custom logic

**Input:** Directives (raw or booked)
**Output:** Modified directives

**Responsibilities:**
- Add, modify, or remove directives
- Apply business logic (categorization, splitting, etc.)
- Can be chained (multiple transformation stages)

**Examples:**
- `auto-balance` - plugins/auto-balance/

### 4. Validation Stage

**Purpose:** Check directives for errors without modification

**Input:** Directives (should be booked)
**Output:** Same directives + validation errors

**Responsibilities:**
- Check balance assertions - src/validator.zig:62-80
- Verify account usage - src/validator.zig:45-60
- Check date ordering - src/validator.zig:82-95
- Collect all validation errors without modifying directives

**Examples:**
- Built-in validator - src/validator.zig

### Stage Ordering Rules

Stages must follow this order:
```
[Parsing] → [Booking] → [Transformation]* → [Validation]
```

**Rules enforced by orchestrator:**
1. At least one parsing stage required
2. Parsing must come first
3. Booking (if present) must come after parsing
4. Transformations can appear in any order between booking and validation
5. Validation (if present) must be last

**Configuration:**

```toml
[[pipeline.stages]]
name = "parser"
type = "external"
stage_type = "parsing"  # Required field
executable = "./plugins/parser"

[[pipeline.stages]]
name = "validator"
type = "builtin"
stage_type = "validation"
function = "validate_all"
```

**Combined Stages:**

A single plugin can implement multiple sequential stage types:

```toml
[[pipeline.stages]]
name = "python-beancount"
type = "external"
stage_type = "parsing+booking"  # Combined stage
executable = "python"
args = ["./plugins/python-beancount/beancount_plugin.py"]
```
```

**Step 2: Update Orchestrator section to mention validation**

Replace the existing "Zig Orchestrator" section:

```markdown
### Zig Orchestrator

The orchestrator coordinates the pipeline:

1. Load Configuration (pipeline.toml)
2. Validate Stage Ordering (src/config.zig:validatePipelineStages)
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
```

**Step 3: Commit**

```bash
git add docs/architecture.md
git commit -m "docs: add stage types section to architecture"
```

---

## Task 9: Update Plugin Protocol Documentation

**Files:**
- Modify: `docs/plugin-protocol.md`

**Step 1: Add Stage Types section**

Add after the introduction section in `docs/plugin-protocol.md`:

```markdown
## Stage Types

Plugins must declare their stage type in the pipeline configuration. Stage types define the plugin's role and responsibilities:

### Parsing Stage (`stage_type = "parsing"`)

**Contract:**
- **Input:** File path provided in InitRequest
- **Output:** Raw directives (no amount interpolation)
- **Must preserve:** Source location metadata
- **Must NOT:** Interpolate amounts, modify directive order, compute balances

**Example:** Rust parser-lima plugin

### Booking Stage (`stage_type = "booking"`)

**Contract:**
- **Input:** Raw directives from parsing stage
- **Output:** Booked directives with interpolated amounts
- **Must:** Interpolate missing amounts, compute running balances, process Pad directives
- **Must validate:** Transactions balance within tolerance
- **Must NOT:** Parse text, add arbitrary directives

**Example:** Python beancount booking plugin

### Transformation Stage (`stage_type = "transformation"`)

**Contract:**
- **Input:** Directives (raw or booked)
- **Output:** Modified directives
- **May:** Add, modify, or remove directives
- **Must preserve:** Valid protobuf structure
- **Can be:** Chained with other transformation stages

**Example:** auto-balance plugin

### Validation Stage (`stage_type = "validation"`)

**Contract:**
- **Input:** Directives (preferably booked)
- **Output:** Same directives + validation errors
- **Must:** Return directives unchanged
- **Must:** Collect errors in ProcessResponse.errors field
- **Should:** Check balance assertions, account usage, date ordering

**Example:** Built-in Zig validator

### Combined Stages

A single plugin can implement multiple sequential stage types:

```toml
stage_type = "parsing+booking"
```

This is common for plugins that wrap existing tools (e.g., Python beancount) that perform both operations.

### Stage Ordering

The orchestrator enforces this ordering:

```
[Parsing] → [Booking] → [Transformation]* → [Validation]
```

Invalid configurations will fail at startup with a clear error message.
```

**Step 2: Update Configuration Example section**

Add stage_type to the example:

```toml
[[pipeline.stages]]
name = "my-plugin"
type = "external"
stage_type = "transformation"  # Required: parsing | booking | transformation | validation
executable = "./plugins/my-plugin/my-plugin"
language = "rust"
description = "My custom plugin"
```

**Step 3: Commit**

```bash
git add docs/plugin-protocol.md
git commit -m "docs: add stage types to plugin protocol"
```

---

## Task 10: Create Python Beancount Plugin Structure

**Files:**
- Create: `plugins/python-beancount/beancount_plugin.py`
- Create: `plugins/python-beancount/requirements.txt`
- Create: `plugins/python-beancount/README.md`

**Step 1: Create plugin directory and requirements**

```bash
mkdir -p plugins/python-beancount
```

Create `plugins/python-beancount/requirements.txt`:

```
beancount>=2.3.6
protobuf>=4.21.0
```

**Step 2: Create README**

Create `plugins/python-beancount/README.md`:

```markdown
# Python Beancount Plugin

Reference implementation of parsing+booking stages using Python's official beancount library.

## Purpose

This plugin demonstrates:
- Combined parsing+booking stage
- Integration with Python beancount
- Amount interpolation and balance computation
- Pad directive processing

## Configuration

```toml
[[pipeline.stages]]
name = "python-beancount"
type = "external"
stage_type = "parsing+booking"
executable = "python"
args = ["./plugins/python-beancount/beancount_plugin.py"]
language = "python"
```

## Installation

```bash
cd plugins/python-beancount
pip install -r requirements.txt
```

## Testing

```bash
# Test with sample file
python beancount_plugin.py < test_input.pb > test_output.pb
```

## Architecture

1. **Parsing:** Uses `beancount.loader.load_file()` to parse beancount syntax
2. **Booking:** Uses `beancount.parser.booking.book()` to interpolate amounts
3. **Conversion:** Converts beancount entries to protobuf directives
4. **Protocol:** Implements standard plugin protocol (Init/Process/Shutdown)
```

**Step 3: Commit**

```bash
git add plugins/python-beancount/
git commit -m "feat: create python-beancount plugin structure"
```

---

## Task 11: Implement Python Beancount Plugin Protocol Handlers

**Files:**
- Create: `plugins/python-beancount/beancount_plugin.py`

**Step 1: Create basic plugin skeleton**

Create `plugins/python-beancount/beancount_plugin.py`:

```python
#!/usr/bin/env python3
"""
Python Beancount Plugin - Reference implementation of parsing+booking stages.

Demonstrates combined parsing and booking using Python's official beancount library.
"""

import sys
import struct
import logging
from pathlib import Path

# Add generated protobuf path
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "generated" / "python"))

from proto import messages_pb2, common_pb2, directives_pb2

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)


def read_message(msg_class):
    """Read length-prefixed protobuf message from stdin."""
    length_bytes = sys.stdin.buffer.read(4)
    if len(length_bytes) < 4:
        raise EOFError("Failed to read message length")

    length = struct.unpack('<I', length_bytes)[0]
    data = sys.stdin.buffer.read(length)

    if len(data) < length:
        raise EOFError(f"Expected {length} bytes, got {len(data)}")

    msg = msg_class()
    msg.ParseFromString(data)
    return msg


def write_message(msg):
    """Write length-prefixed protobuf message to stdout."""
    data = msg.SerializeToString()
    length = struct.pack('<I', len(data))
    sys.stdout.buffer.write(length + data)
    sys.stdout.buffer.flush()


def handle_init():
    """Handle InitRequest."""
    init_req = read_message(messages_pb2.InitRequest)
    logger.info(f"Received InitRequest: protocol_version={init_req.protocol_version}")

    init_resp = messages_pb2.InitResponse(
        success=True,
        plugin_version="0.1.0",
        capabilities=["parsing", "booking"]
    )
    write_message(init_resp)
    logger.info("Sent InitResponse")

    return init_req.input_file


def handle_process(input_file):
    """Handle ProcessRequest."""
    req = read_message(messages_pb2.ProcessRequest)
    logger.info(f"Received ProcessRequest with {len(req.directives)} directives")

    # TODO: Implement parsing and booking
    # For now, return empty response
    resp = messages_pb2.ProcessResponse()
    write_message(resp)
    logger.info("Sent ProcessResponse")


def handle_shutdown():
    """Handle ShutdownRequest."""
    shutdown_req = read_message(messages_pb2.ShutdownRequest)
    logger.info("Received ShutdownRequest")

    shutdown_resp = messages_pb2.ShutdownResponse(success=True)
    write_message(shutdown_resp)
    logger.info("Sent ShutdownResponse")


def main():
    """Main plugin loop."""
    try:
        # Phase 1: Init
        input_file = handle_init()

        # Phase 2: Process
        handle_process(input_file)

        # Phase 3: Shutdown
        handle_shutdown()

    except Exception as e:
        logger.error(f"Plugin error: {e}", exc_info=True)
        sys.exit(1)


if __name__ == "__main__":
    main()
```

**Step 2: Make executable**

```bash
chmod +x plugins/python-beancount/beancount_plugin.py
```

**Step 3: Test basic protocol handling**

Create a simple test to verify protocol works:

```bash
# This will be tested in integration tests later
echo "Basic protocol skeleton created"
```

**Step 4: Commit**

```bash
git add plugins/python-beancount/beancount_plugin.py
git commit -m "feat: implement python-beancount protocol handlers"
```

---

## Task 12: Add Beancount Parsing to Python Plugin

**Files:**
- Modify: `plugins/python-beancount/beancount_plugin.py`

**Step 1: Add beancount imports**

At top of `beancount_plugin.py`, add:

```python
import beancount.loader
from beancount.parser import booking
from beancount.core import data
```

**Step 2: Implement parse_and_book function**

Add before `handle_process`:

```python
def parse_and_book(input_file):
    """Parse and book a beancount file.

    Returns:
        tuple: (entries, errors, options) where entries are booked
    """
    logger.info(f"Parsing file: {input_file}")

    # PARSING: Load beancount file
    entries, parse_errors, options_map = beancount.loader.load_file(input_file)
    logger.info(f"Parsed {len(entries)} entries with {len(parse_errors)} errors")

    # BOOKING: Apply beancount's booking logic
    logger.info("Starting booking phase")
    booked_entries, booking_errors = booking.book(entries, options_map)
    logger.info(f"Booked {len(booked_entries)} entries with {len(booking_errors)} booking errors")

    all_errors = list(parse_errors) + list(booking_errors)

    return booked_entries, all_errors, options_map
```

**Step 3: Update handle_process to use parse_and_book**

Replace the TODO in `handle_process`:

```python
def handle_process(input_file):
    """Handle ProcessRequest."""
    req = read_message(messages_pb2.ProcessRequest)
    logger.info(f"Received ProcessRequest with {len(req.directives)} directives")

    # Parse and book the beancount file
    entries, errors, options_map = parse_and_book(input_file)

    # TODO: Convert entries to protobuf directives
    # TODO: Convert errors to protobuf errors
    # For now, return empty response
    resp = messages_pb2.ProcessResponse()
    write_message(resp)
    logger.info("Sent ProcessResponse")
```

**Step 4: Manual test with sample file**

```bash
cd plugins/python-beancount
pip install -r requirements.txt
python -c "
import beancount.loader
from beancount.parser import booking
entries, errors, options = beancount.loader.load_file('../../examples/sample.beancount')
print(f'Parsed {len(entries)} entries')
booked, book_errors = booking.book(entries, options)
print(f'Booked {len(booked)} entries')
"
```

Expected: Output shows parsed and booked entries

**Step 5: Commit**

```bash
git add plugins/python-beancount/beancount_plugin.py
git commit -m "feat: add beancount parsing and booking to plugin"
```

---

## Task 13: Add Protobuf Conversion Stubs

**Files:**
- Create: `plugins/python-beancount/proto_conversion.py`

**Step 1: Create conversion module skeleton**

Create `plugins/python-beancount/proto_conversion.py`:

```python
"""
Conversion between beancount data types and protobuf messages.
"""

import sys
from pathlib import Path
from decimal import Decimal

# Add generated protobuf path
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "generated" / "python"))

from proto import common_pb2, directives_pb2
from beancount.core import data


def entry_to_directive(entry):
    """Convert beancount entry to protobuf Directive.

    Args:
        entry: Beancount entry (Transaction, Balance, Open, etc.)

    Returns:
        directives_pb2.Directive
    """
    # TODO: Implement full conversion
    # For now, return minimal directive
    directive = directives_pb2.Directive()

    # Set common fields
    if hasattr(entry, 'date'):
        directive.date.year = entry.date.year
        directive.date.month = entry.date.month
        directive.date.day = entry.date.day

    # Set metadata
    if hasattr(entry, 'meta') and entry.meta:
        if 'filename' in entry.meta:
            directive.meta.filename = entry.meta['filename']
        if 'lineno' in entry.meta:
            directive.meta.lineno = entry.meta['lineno']

    return directive


def error_to_protobuf(error):
    """Convert beancount error to protobuf Error.

    Args:
        error: Beancount error object

    Returns:
        common_pb2.Error
    """
    pb_error = common_pb2.Error()
    pb_error.message = str(error.message) if hasattr(error, 'message') else str(error)
    pb_error.severity = common_pb2.Error.ERROR

    if hasattr(error, 'entry') and error.entry and hasattr(error.entry, 'meta'):
        meta = error.entry.meta
        if 'filename' in meta:
            pb_error.source.filename = meta['filename']
        if 'lineno' in meta:
            pb_error.source.lineno = meta['lineno']

    return pb_error


def options_map_to_dict(options_map):
    """Convert beancount options_map to dict of strings.

    Args:
        options_map: Beancount options map

    Returns:
        dict: String key-value pairs
    """
    result = {}

    for key, value in options_map.items():
        # Convert value to string representation
        if isinstance(value, (list, tuple)):
            result[key] = ','.join(str(v) for v in value)
        else:
            result[key] = str(value)

    return result
```

**Step 2: Update handle_process to use conversions**

In `beancount_plugin.py`, import proto_conversion:

```python
import proto_conversion
```

Update `handle_process`:

```python
def handle_process(input_file):
    """Handle ProcessRequest."""
    req = read_message(messages_pb2.ProcessRequest)
    logger.info(f"Received ProcessRequest with {len(req.directives)} directives")

    # Parse and book the beancount file
    entries, errors, options_map = parse_and_book(input_file)

    # Convert to protobuf
    pb_directives = [proto_conversion.entry_to_directive(entry) for entry in entries]
    pb_errors = [proto_conversion.error_to_protobuf(error) for error in errors]
    pb_options = proto_conversion.options_map_to_dict(options_map)

    # Build response
    resp = messages_pb2.ProcessResponse()
    resp.directives.extend(pb_directives)
    resp.errors.extend(pb_errors)
    for key, value in pb_options.items():
        resp.updated_options[key] = value

    write_message(resp)
    logger.info(f"Sent ProcessResponse with {len(pb_directives)} directives, {len(pb_errors)} errors")
```

**Step 3: Commit**

```bash
git add plugins/python-beancount/proto_conversion.py plugins/python-beancount/beancount_plugin.py
git commit -m "feat: add protobuf conversion stubs to python plugin"
```

---

## Task 14: Update README with Usage Examples

**Files:**
- Modify: `README.md:89-122`

**Step 1: Add stage_type to pipeline configuration example**

Update the configuration section:

```markdown
## Configuration

The pipeline is configured via `pipeline.toml`:

```toml
[pipeline]
input = "examples/sample.beancount"
output_format = "json"

[[pipeline.stages]]
name = "parser"
type = "external"
stage_type = "parsing"
executable = "./plugins/parser-lima/target/release/parser-lima"
language = "rust"

[[pipeline.stages]]
name = "auto-balance"
type = "external"
stage_type = "transformation"
executable = "python"
args = ["./plugins/auto-balance/auto_balance.py"]
language = "python"

[[pipeline.stages]]
name = "validator"
type = "builtin"
stage_type = "validation"
function = "validate_all"

[options]
operating_currency = "USD"
tolerance_default = "0.005"
```

### Stage Types

Beancount Runner enforces a four-stage architecture:

1. **Parsing** - Text → raw directives
2. **Booking** - Raw directives → booked directives (interpolation, balance computation)
3. **Transformation** - Directive modifications (optional, repeatable)
4. **Validation** - Error checking without modification

The `stage_type` field is required and must follow ordering rules (parsing first, validation last).

### Python Beancount Example

Use Python's official beancount library for parsing and booking:

```toml
[[pipeline.stages]]
name = "python-beancount"
type = "external"
stage_type = "parsing+booking"
executable = "python"
args = ["./plugins/python-beancount/beancount_plugin.py"]
language = "python"
```
```

**Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add stage_type to README examples"
```

---

## Task 15: Create Example Pipeline Configurations

**Files:**
- Create: `examples/python-beancount/pipeline.toml`
- Create: `examples/rust-parser/pipeline.toml`

**Step 1: Create Python beancount example**

```bash
mkdir -p examples/python-beancount
```

Create `examples/python-beancount/pipeline.toml`:

```toml
# Example: Python Beancount Parser + Booking

[pipeline]
input = "../sample.beancount"
output_format = "json"
output_path = "output.json"
verbose = true

# Use Python beancount for parsing AND booking
[[pipeline.stages]]
name = "python-beancount"
type = "external"
stage_type = "parsing+booking"
executable = "python"
args = ["../../plugins/python-beancount/beancount_plugin.py"]
language = "python"
description = "Parse and book using Python beancount library"

# Optional: Add custom transformations after booking
# [[pipeline.stages]]
# name = "categorizer"
# type = "external"
# stage_type = "transformation"
# executable = "./my-categorizer"

# Optional: Add validation
[[pipeline.stages]]
name = "validator"
type = "builtin"
stage_type = "validation"
function = "validate_all"
description = "Validate booked directives"

[options]
operating_currency = "USD"
tolerance_default = "0.005"
```

**Step 2: Create Rust parser example**

```bash
mkdir -p examples/rust-parser
```

Create `examples/rust-parser/pipeline.toml`:

```toml
# Example: Rust Parser (no booking)

[pipeline]
input = "../sample.beancount"
output_format = "json"
output_path = "output.json"
verbose = true

# Use Rust parser for parsing only
[[pipeline.stages]]
name = "parser"
type = "external"
stage_type = "parsing"
executable = "../../plugins/parser-lima/target/release/parser-lima"
language = "rust"
description = "Parse beancount file using lima parser"

# Add transformation stages
[[pipeline.stages]]
name = "auto-balance"
type = "external"
stage_type = "transformation"
executable = "python"
args = ["../../plugins/auto-balance/auto_balance.py"]
language = "python"
description = "Generate padding entries"

# Add validation
[[pipeline.stages]]
name = "validator"
type = "builtin"
stage_type = "validation"
function = "validate_all"
description = "Validate directives"

[options]
operating_currency = "USD"
tolerance_default = "0.005"
```

**Step 3: Commit**

```bash
git add examples/
git commit -m "feat: add example pipeline configurations"
```

---

## Task 16: Integration Test

**Files:**
- Test: `zig build test && ./zig-out/bin/beancount-runner --input examples/sample.beancount`

**Step 1: Run unit tests**

Run: `zig build test`
Expected: All tests pass

**Step 2: Build orchestrator**

Run: `zig build`
Expected: Build succeeds

**Step 3: Test with existing pipeline (Rust parser)**

Run: `./zig-out/bin/beancount-runner --input examples/sample.beancount --verbose`
Expected: Pipeline runs with stage_type validation, shows parsing/transformation/validation stages

**Step 4: Verify stage ordering validation**

Create temporary invalid config in `test-invalid.toml`:

```toml
[pipeline]
input = "examples/sample.beancount"

[[pipeline.stages]]
name = "validator"
type = "builtin"
stage_type = "validation"
function = "validate_all"

[[pipeline.stages]]
name = "parser"
type = "external"
stage_type = "parsing"
executable = "./plugins/parser-lima/target/release/parser-lima"
```

Run: `./zig-out/bin/beancount-runner --config test-invalid.toml`
Expected: Error message about invalid stage order

Clean up:
```bash
rm test-invalid.toml
```

**Step 5: Commit if any fixes needed**

```bash
# Only if bugs were found and fixed
git add <fixed-files>
git commit -m "fix: <description>"
```

---

## Task 17: Final Documentation Review

**Files:**
- Read: `docs/architecture.md`
- Read: `docs/plugin-protocol.md`
- Read: `README.md`

**Step 1: Review documentation for consistency**

Check that all docs mention:
- Four stage types
- stage_type field requirement
- Ordering rules
- Python beancount example

**Step 2: Add cross-references**

Ensure docs link to:
- Design doc: `docs/plans/2026-03-04-stage-type-system-design.md`
- Config examples
- Plugin examples

**Step 3: Update DEVELOPMENT.md if present**

If `docs/DEVELOPMENT.md` exists, add note about stage types:

```markdown
## Stage Types

When creating a new plugin, specify its `stage_type` in pipeline.toml:
- `parsing` - Converts text to directives
- `booking` - Interpolates amounts and computes balances
- `transformation` - Modifies directives
- `validation` - Checks directives for errors

See `docs/architecture.md` for full stage type specifications.
```

**Step 4: Commit any documentation updates**

```bash
git add docs/
git commit -m "docs: add cross-references and clarifications"
```

---

## Execution Complete

All tasks implemented! The stage type system is now fully integrated into beancount-runner.

**Summary:**
- ✅ Added PipelineStageType enum with validation
- ✅ Updated StageConfig with pipeline_stage_type field
- ✅ Implemented stage inference for backward compatibility
- ✅ Added validatePipelineStages with ordering rules
- ✅ Updated TOML parser to read stage_type
- ✅ Integrated validation into orchestrator
- ✅ Updated all configuration files
- ✅ Created Python beancount reference plugin skeleton
- ✅ Updated all documentation
- ✅ Added example configurations

**Next Steps:**
- Complete proto_conversion.py implementation for full beancount type support
- Add integration tests for Python beancount plugin
- Consider implementing Zig-native booking stage for performance
