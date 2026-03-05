const std = @import("std");
const testing = std.testing;
const Orchestrator = @import("orchestrator.zig").Orchestrator;
const config = @import("config.zig");

test "Orchestrator.init rejects config without parsing stage" {
    const allocator = testing.allocator;

    // Create config with no parsing stage (only validation stage)
    var stages = try allocator.alloc(config.StageConfig, 1);
    errdefer {
        for (stages) |*stage| stage.deinit(allocator);
        allocator.free(stages);
    }

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
        .output_path = try allocator.dupe(u8, "output.json"),
        .verbose = false,
        .stages = stages,
        .options = std.StringHashMap([]const u8).init(allocator),
    };
    defer pipeline_config.deinit(allocator);

    // Use undefined for io since we're only testing validation, not IO operations
    // The validation happens before any IO is used
    const io: std.Io = undefined;

    // Expect NoParsingStageDefined error
    try testing.expectError(
        error.NoParsingStageDefined,
        Orchestrator.init(allocator, pipeline_config, io, false),
    );
}
