const std = @import("std");
const config = @import("config.zig");
const Orchestrator = @import("orchestrator.zig").Orchestrator;
const output = @import("output.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();

    // Parse command line arguments - Zig 0.16 API
    const args = try init.minimal.args.toSlice(allocator);

    const cli_opts = try parseArgs(allocator, args);

    // Load pipeline configuration using init.io
    const config_path = cli_opts.config_path orelse "pipeline.toml";
    var pipeline_config = try config.loadConfig(allocator, &init.io, config_path);
    defer pipeline_config.deinit(allocator);

    // Override input file if specified on CLI
    const input_file = cli_opts.input_file orelse pipeline_config.input;

    if (cli_opts.verbose) {
        std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
        std.debug.print("🚀 Beancount Runner v0.1.0\n", .{});
        std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
        std.debug.print("📄 Input:  {s}\n", .{input_file});
        std.debug.print("⚙️  Config: {s}\n", .{config_path});
        std.debug.print("📊 Stages: {d}\n", .{pipeline_config.stages.len});
        std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n", .{});
    }

    // Create and run orchestrator
    var orchestrator = try Orchestrator.init(allocator, pipeline_config, init.io, cli_opts.verbose);
    defer orchestrator.deinit();

    var result = try orchestrator.run(input_file);
    defer result.deinit(allocator);

    // Output results
    try writeOutput(allocator, init.io, result, pipeline_config.output_format, pipeline_config.output_path);

    // Print summary
    if (cli_opts.verbose) {
        std.debug.print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
        std.debug.print("✅ Pipeline complete\n", .{});
        std.debug.print("📝 Directives: {d}\n", .{result.directives.len});

        // Show directive type breakdown
        if (result.directives.len > 0) {
            std.debug.print("\n📋 Directive breakdown:\n", .{});
            for (result.directives) |directive| {
                const type_name = switch (directive.directive_type) {
                    .transaction => "Transaction",
                    .balance => "Balance",
                    .open => "Open",
                    .close => "Close",
                    .pad => "Pad",
                };
                std.debug.print("  - {s}\n", .{type_name});
            }
        }

        std.debug.print("\n❌ Errors:     {d}\n", .{result.errors.len});
        std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    }

    // Exit with error code if validation failed
    if (result.errors.len > 0) {
        std.process.exit(1);
    }
}

const CliOptions = struct {
    input_file: ?[]const u8,
    config_path: ?[]const u8,
    verbose: bool,
};

fn parseArgs(allocator: std.mem.Allocator, args: []const []const u8) !CliOptions {
    _ = allocator;

    var opts = CliOptions{
        .input_file = null,
        .config_path = null,
        .verbose = false,
    };

    var i: usize = 1; // Skip program name
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--input") or std.mem.eql(u8, arg, "-i")) {
            i += 1;
            if (i >= args.len) {
                std.debug.print("Error: --input requires a value\n", .{});
                return error.InvalidArgument;
            }
            opts.input_file = args[i];
        } else if (std.mem.eql(u8, arg, "--config") or std.mem.eql(u8, arg, "-c")) {
            i += 1;
            if (i >= args.len) {
                std.debug.print("Error: --config requires a value\n", .{});
                return error.InvalidArgument;
            }
            opts.config_path = args[i];
        } else if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-v")) {
            opts.verbose = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printHelp();
            std.process.exit(0);
        } else {
            std.debug.print("Unknown argument: {s}\n", .{arg});
            return error.InvalidArgument;
        }
    }

    return opts;
}

fn printHelp() void {
    std.debug.print(
        \\Beancount Runner - Multi-language plugin pipeline for beancount files
        \\
        \\USAGE:
        \\    beancount-runner [OPTIONS]
        \\
        \\OPTIONS:
        \\    -i, --input <FILE>     Input beancount file
        \\    -c, --config <FILE>    Pipeline configuration file (default: pipeline.toml)
        \\    -v, --verbose          Enable verbose output
        \\    -h, --help             Print this help message
        \\
        \\EXAMPLES:
        \\    beancount-runner --input mybooks.beancount
        \\    beancount-runner -i books.beancount -v
        \\    beancount-runner --config custom-pipeline.toml
        \\
    , .{});
}

fn writeOutput(
    allocator: std.mem.Allocator,
    io: std.Io,
    result: anytype,
    format: []const u8,
    output_path: []const u8,
) !void {
    if (std.mem.eql(u8, format, "json")) {
        try output.writeJson(allocator, io, result.directives, result.errors, output_path);
    } else if (std.mem.eql(u8, format, "text")) {
        // Text format not implemented yet
        std.debug.print("Warning: Text output format not implemented, defaulting to JSON\n", .{});
        try output.writeJson(allocator, io, result.directives, result.errors, output_path);
    } else if (std.mem.eql(u8, format, "protobuf")) {
        // Protobuf format not implemented yet
        std.debug.print("Warning: Protobuf output format not implemented, defaulting to JSON\n", .{});
        try output.writeJson(allocator, io, result.directives, result.errors, output_path);
    } else {
        std.debug.print("Unsupported output format: {s}\n", .{format});
        return error.UnsupportedFormat;
    }
}
