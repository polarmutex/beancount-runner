const std = @import("std");
const config = @import("config.zig");
const PluginManager = @import("plugin_manager.zig").PluginManager;
const validator = @import("validator.zig");
const proto = @import("proto.zig");

pub const Orchestrator = struct {
    allocator: std.mem.Allocator,
    config: config.PipelineConfig,
    plugin_manager: PluginManager,
    verbose: bool,

    pub fn init(
        allocator: std.mem.Allocator,
        pipeline_config: config.PipelineConfig,
        verbose: bool,
    ) !Orchestrator {
        const plugin_manager = try PluginManager.init(allocator);

        return Orchestrator{
            .allocator = allocator,
            .config = pipeline_config,
            .plugin_manager = plugin_manager,
            .verbose = verbose,
        };
    }

    pub fn deinit(self: *Orchestrator) void {
        self.plugin_manager.deinit();
    }

    pub fn run(self: *Orchestrator, input_file: []const u8) !PipelineResult {
        if (self.verbose) {
            std.debug.print("▶️  Starting pipeline execution...\n\n", .{});
        }

        // Initialize result
        var directives: std.ArrayList(proto.Directive) = .empty;
        var errors: std.ArrayList(proto.Error) = .empty;
        var options = std.StringHashMap([]const u8).init(self.allocator);

        // Copy initial options from config
        var iter = self.config.options.iterator();
        while (iter.next()) |entry| {
            try options.put(
                try self.allocator.dupe(u8, entry.key_ptr.*),
                try self.allocator.dupe(u8, entry.value_ptr.*),
            );
        }

        // Execute each stage in order
        for (self.config.stages, 0..) |stage, idx| {
            if (self.verbose) {
                std.debug.print("📍 Stage {d}/{d}: {s}\n", .{
                    idx + 1,
                    self.config.stages.len,
                    stage.name,
                });
                if (stage.description) |desc| {
                    std.debug.print("   {s}\n", .{desc});
                }
            }

            switch (stage.stage_type) {
                .external => {
                    const result = try self.runExternalStage(
                        stage,
                        directives.items,
                        options,
                        input_file,
                    );

                    // Replace directives with plugin output
                    directives.clearRetainingCapacity();
                    try directives.appendSlice(self.allocator, result.directives);

                    // Accumulate errors
                    try errors.appendSlice(self.allocator, result.errors);

                    // Update options if plugin modified them
                    var opt_iter = result.updated_options.iterator();
                    while (opt_iter.next()) |entry| {
                        try options.put(entry.key_ptr.*, entry.value_ptr.*);
                    }
                },
                .builtin => {
                    if (std.mem.eql(u8, stage.function_name.?, "validate_all")) {
                        const val_result = try self.runValidator(directives.items);
                        try errors.appendSlice(self.allocator, val_result.errors);
                    }
                },
            }

            if (self.verbose) {
                std.debug.print("   ✓ Directives: {d}, Errors: {d}\n\n", .{
                    directives.items.len,
                    errors.items.len,
                });
            }
        }

        return PipelineResult{
            .directives = try directives.toOwnedSlice(self.allocator),
            .errors = try errors.toOwnedSlice(self.allocator),
            .options = options,
        };
    }

    fn runExternalStage(
        self: *Orchestrator,
        stage: config.StageConfig,
        current_directives: []const proto.Directive,
        options: std.StringHashMap([]const u8),
        input_file: []const u8,
    ) !StageResult {
        _ = stage;
        _ = current_directives;
        _ = options;
        _ = input_file;

        // TODO: Implement external plugin execution
        // 1. Spawn subprocess
        // 2. Send InitRequest
        // 3. Send ProcessRequest with current directives
        // 4. Receive ProcessResponse
        // 5. Send ShutdownRequest
        // 6. Parse and return results

        return StageResult{
            .directives = &[_]proto.Directive{},
            .errors = &[_]proto.Error{},
            .updated_options = std.StringHashMap([]const u8).init(self.allocator),
        };
    }

    fn runValidator(
        self: *Orchestrator,
        directives: []const proto.Directive,
    ) !validator.ValidationResult {
        var val = validator.Validator.init(self.allocator);
        return try val.validate(directives);
    }
};

pub const PipelineResult = struct {
    directives: []proto.Directive,
    errors: []proto.Error,
    options: std.StringHashMap([]const u8),

    pub fn deinit(self: *PipelineResult, allocator: std.mem.Allocator) void {
        allocator.free(self.directives);
        allocator.free(self.errors);

        var iter = self.options.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        self.options.deinit();
    }
};

const StageResult = struct {
    directives: []const proto.Directive,
    errors: []const proto.Error,
    updated_options: std.StringHashMap([]const u8),
};
