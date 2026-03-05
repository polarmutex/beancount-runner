const std = @import("std");

pub const PipelineConfig = struct {
    input: []const u8,
    output_format: []const u8,
    output_path: []const u8,
    verbose: bool,
    stages: []StageConfig,
    options: std.StringHashMap([]const u8),

    pub fn deinit(self: *PipelineConfig, allocator: std.mem.Allocator) void {
        allocator.free(self.input);
        allocator.free(self.output_format);
        allocator.free(self.output_path);

        for (self.stages) |*stage| {
            stage.deinit(allocator);
        }
        allocator.free(self.stages);

        var iter = self.options.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        self.options.deinit();
    }
};

pub const StageConfig = struct {
    name: []const u8,
    stage_type: StageType,
    pipeline_stage_type: ?PipelineStageType, // Optional for backward compatibility
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

pub const StageType = enum {
    external,
    builtin,
};

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

test "StageConfig with pipeline_stage_type" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var stage = StageConfig{
        .name = try allocator.dupe(u8, "parser"),
        .stage_type = .external,
        .pipeline_stage_type = .parsing, // Optional, so we can set it
        .executable = try allocator.dupe(u8, "./parser"),
        .args = try allocator.alloc([]const u8, 0),
        .language = null,
        .description = null,
        .function_name = null,
    };
    defer stage.deinit(allocator);

    try testing.expectEqual(PipelineStageType.parsing, stage.pipeline_stage_type.?);
}

pub fn loadConfig(allocator: std.mem.Allocator, io: *const std.Io, path: []const u8) !PipelineConfig {
    // Read config file using Zig 0.16 Io interface
    const cwd_dir = std.Io.Dir.cwd();
    const content = try cwd_dir.readFileAlloc(io.*, path, allocator, .unlimited);
    defer allocator.free(content);

    // Parse TOML (simplified parser for now)
    return try parseToml(allocator, content);
}

fn parseToml(allocator: std.mem.Allocator, content: []const u8) !PipelineConfig {
    // Basic line-by-line TOML parser for MVP
    // Production would use a proper TOML library

    var config = PipelineConfig{
        .input = try allocator.dupe(u8, "examples/sample.beancount"),
        .output_format = try allocator.dupe(u8, "json"),
        .output_path = try allocator.dupe(u8, "output.json"),
        .verbose = false,
        .stages = undefined,
        .options = std.StringHashMap([]const u8).init(allocator),
    };
    errdefer {
        allocator.free(config.input);
        allocator.free(config.output_format);
        allocator.free(config.output_path);
        config.options.deinit();
    }

    var stages: std.ArrayList(StageConfig) = .empty;
    errdefer {
        for (stages.items) |*stage| {
            stage.deinit(allocator);
        }
        stages.deinit(allocator);
    }
    var current_stage: ?StageConfig = null;
    var current_section: []const u8 = "";

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");

        // Skip comments and empty lines
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        // Parse section headers
        if (trimmed[0] == '[') {
            // Save current stage if parsing one
            if (current_stage) |stage| {
                try stages.append(allocator, stage);
                current_stage = null;
            }

            if (std.mem.startsWith(u8, trimmed, "[[pipeline.stages]]")) {
                current_section = "stage";
                const empty_args = try allocator.alloc([]const u8, 0);
                current_stage = StageConfig{
                    .name = try allocator.dupe(u8, ""),
                    .stage_type = .external,
                    .pipeline_stage_type = null,
                    .executable = null,
                    .args = empty_args,
                    .language = null,
                    .description = null,
                    .function_name = null,
                };
            } else if (std.mem.startsWith(u8, trimmed, "[pipeline]")) {
                current_section = "pipeline";
            } else if (std.mem.startsWith(u8, trimmed, "[options]")) {
                current_section = "options";
            } else {
                // Unknown section, skip
                current_section = "";
            }
            continue;
        }

        // Parse key = value
        if (std.mem.indexOf(u8, trimmed, "=")) |eq_pos| {
            const key = std.mem.trim(u8, trimmed[0..eq_pos], " \t");
            var value = std.mem.trim(u8, trimmed[eq_pos + 1 ..], " \t");

            // Remove quotes from value if present
            if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"') {
                value = value[1 .. value.len - 1];
            }

            // Handle based on current section
            if (std.mem.eql(u8, current_section, "pipeline")) {
                if (std.mem.eql(u8, key, "input")) {
                    allocator.free(config.input);
                    config.input = try allocator.dupe(u8, value);
                } else if (std.mem.eql(u8, key, "output_format")) {
                    allocator.free(config.output_format);
                    config.output_format = try allocator.dupe(u8, value);
                } else if (std.mem.eql(u8, key, "output_path")) {
                    allocator.free(config.output_path);
                    config.output_path = try allocator.dupe(u8, value);
                } else if (std.mem.eql(u8, key, "verbose")) {
                    config.verbose = std.mem.eql(u8, value, "true");
                }
            } else if (std.mem.eql(u8, current_section, "options")) {
                try config.options.put(try allocator.dupe(u8, key), try allocator.dupe(u8, value));
            } else if (std.mem.eql(u8, current_section, "stage")) {
                if (current_stage) |*stage| {
                    if (std.mem.eql(u8, key, "name")) {
                        allocator.free(stage.name);
                        stage.name = try allocator.dupe(u8, value);
                    } else if (std.mem.eql(u8, key, "type")) {
                        if (std.mem.eql(u8, value, "builtin")) {
                            stage.stage_type = .builtin;
                        } else {
                            stage.stage_type = .external;
                        }
                    } else if (std.mem.eql(u8, key, "executable")) {
                        if (stage.executable) |exe| allocator.free(exe);
                        stage.executable = try allocator.dupe(u8, value);
                    } else if (std.mem.eql(u8, key, "language")) {
                        if (stage.language) |lang| allocator.free(lang);
                        stage.language = try allocator.dupe(u8, value);
                    } else if (std.mem.eql(u8, key, "description")) {
                        if (stage.description) |desc| allocator.free(desc);
                        stage.description = try allocator.dupe(u8, value);
                    } else if (std.mem.eql(u8, key, "function")) {
                        if (stage.function_name) |func| allocator.free(func);
                        stage.function_name = try allocator.dupe(u8, value);
                    } else if (std.mem.eql(u8, key, "args")) {
                        // Parse args array: ["arg1", "arg2"]
                        var args_list: std.ArrayList([]const u8) = .empty;
                        if (value.len >= 2 and value[0] == '[' and value[value.len - 1] == ']') {
                            const args_content = value[1 .. value.len - 1];
                            var args_iter = std.mem.splitScalar(u8, args_content, ',');
                            while (args_iter.next()) |arg| {
                                var arg_trimmed = std.mem.trim(u8, arg, " \t");
                                // Remove quotes
                                if (arg_trimmed.len >= 2 and arg_trimmed[0] == '"' and arg_trimmed[arg_trimmed.len - 1] == '"') {
                                    arg_trimmed = arg_trimmed[1 .. arg_trimmed.len - 1];
                                }
                                if (arg_trimmed.len > 0) {
                                    try args_list.append(allocator, try allocator.dupe(u8, arg_trimmed));
                                }
                            }
                        }
                        const new_args = try args_list.toOwnedSlice(allocator);
                        for (stage.args) |arg| allocator.free(arg);
                        allocator.free(stage.args);
                        stage.args = new_args;
                    }
                }
            }
        }
    }

    // Save last stage if exists
    if (current_stage) |stage| {
        try stages.append(allocator, stage);
    }

    config.stages = try stages.toOwnedSlice(allocator);
    return config;
}
