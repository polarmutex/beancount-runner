const std = @import("std");
const config = @import("config.zig");
const PluginManager = @import("plugin_manager.zig").PluginManager;
const validator = @import("validator.zig");
const proto = @import("proto.zig");
const protobuf = @import("protobuf.zig");

pub const Orchestrator = struct {
    allocator: std.mem.Allocator,
    config: config.PipelineConfig,
    plugin_manager: PluginManager,
    io: std.Io,
    verbose: bool,

    pub fn init(
        allocator: std.mem.Allocator,
        pipeline_config: config.PipelineConfig,
        io: std.Io,
        verbose: bool,
    ) !Orchestrator {
        const plugin_manager = try PluginManager.init(allocator);

        return Orchestrator{
            .allocator = allocator,
            .config = pipeline_config,
            .plugin_manager = plugin_manager,
            .io = io,
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
        _: []const proto.Directive,
        options: std.StringHashMap([]const u8),
        input_file: []const u8,
    ) !StageResult {
        // Spawn plugin subprocess
        var plugin = try self.plugin_manager.spawn(
            self.io,
            stage.executable.?,
            stage.args,
        );
        defer plugin.deinit(self.io);

        // Send init request (protobuf encoded)
        const init_req = try protobuf.encodeInitRequest(
            self.allocator,
            stage.name,
            "plugin",
            options,
        );
        defer self.allocator.free(init_req);
        try plugin.sendMessage(self.io, init_req);

        // Receive init response
        const init_resp = try plugin.receiveMessage(self.io, self.allocator);
        defer self.allocator.free(init_resp);

        // Parse response and check success
        const success = try protobuf.decodeInitResponse(init_resp);
        if (!success) {
            return error.PluginInitFailed;
        }

        // Send process request with input_file and options
        var options_with_input = try options.clone();
        defer {
            var iter = options_with_input.iterator();
            while (iter.next()) |entry| {
                if (!options.contains(entry.key_ptr.*)) {
                    self.allocator.free(entry.key_ptr.*);
                    self.allocator.free(entry.value_ptr.*);
                }
            }
            options_with_input.deinit();
        }

        const proc_req = try protobuf.encodeProcessRequest(
            self.allocator,
            input_file,
            options_with_input,
        );
        defer self.allocator.free(proc_req);
        try plugin.sendMessage(self.io, proc_req);

        // Receive process response
        const proc_resp = try plugin.receiveMessage(self.io, self.allocator);
        defer self.allocator.free(proc_resp);

        // Parse response to get counts (full parsing would require complete protobuf decoder)
        const response_info = try protobuf.decodeProcessResponse(proc_resp);

        if (self.verbose) {
            std.debug.print("   📊 Plugin returned {d} directives, {d} errors\n", .{
                response_info.directive_count,
                response_info.error_count,
            });
        }

        // Send shutdown request
        const shutdown_req = try protobuf.encodeShutdownRequest(
            self.allocator,
            "pipeline_complete",
        );
        defer self.allocator.free(shutdown_req);
        try plugin.sendMessage(self.io, shutdown_req);

        // For MVP: Return empty results with counts logged
        // TODO: Implement full protobuf -> proto.Directive parsing for complete integration
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

// Note: Protobuf encoding is now handled by protobuf.zig module
