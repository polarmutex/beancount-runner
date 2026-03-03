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

pub fn loadConfig(allocator: std.mem.Allocator, path: []const u8) !PipelineConfig {
    // Read config file
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024); // 1MB max
    defer allocator.free(content);

    // Parse TOML (simplified parser for now)
    return try parseToml(allocator, content);
}

fn parseToml(allocator: std.mem.Allocator, content: []const u8) !PipelineConfig {
    _ = content;

    // TODO: Implement proper TOML parser
    // For now, return hardcoded config matching pipeline.toml

    var options = std.StringHashMap([]const u8).init(allocator);
    try options.put(try allocator.dupe(u8, "operating_currency"), try allocator.dupe(u8, "USD"));
    try options.put(try allocator.dupe(u8, "tolerance_default"), try allocator.dupe(u8, "0.005"));

    const stages = try allocator.alloc(StageConfig, 3);

    // Parser stage
    stages[0] = StageConfig{
        .name = try allocator.dupe(u8, "parser"),
        .stage_type = .external,
        .executable = try allocator.dupe(u8, "./plugins/parser-lima/target/release/parser-lima"),
        .args = &[_][]const u8{},
        .language = try allocator.dupe(u8, "rust"),
        .description = try allocator.dupe(u8, "Parse beancount file using lima parser"),
        .function_name = null,
    };

    // Auto-balance plugin stage
    stages[1] = StageConfig{
        .name = try allocator.dupe(u8, "auto-balance"),
        .stage_type = .external,
        .executable = try allocator.dupe(u8, "python"),
        .args = try allocator.dupe([]const u8, &[_][]const u8{
            try allocator.dupe(u8, "./plugins/auto-balance/auto_balance.py"),
        }),
        .language = try allocator.dupe(u8, "python"),
        .description = try allocator.dupe(u8, "Generate padding entries for balance assertions"),
        .function_name = null,
    };

    // Validator stage
    stages[2] = StageConfig{
        .name = try allocator.dupe(u8, "validator"),
        .stage_type = .builtin,
        .executable = null,
        .args = &[_][]const u8{},
        .language = null,
        .description = try allocator.dupe(u8, "Validate transactions and accounts"),
        .function_name = try allocator.dupe(u8, "validate_all"),
    };

    return PipelineConfig{
        .input = try allocator.dupe(u8, "examples/sample.beancount"),
        .output_format = try allocator.dupe(u8, "json"),
        .output_path = try allocator.dupe(u8, "output.json"),
        .verbose = false,
        .stages = stages,
        .options = options,
    };
}
