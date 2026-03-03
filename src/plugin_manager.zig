const std = @import("std");

pub const PluginManager = struct {
    allocator: std.mem.Allocator,
    plugins: std.ArrayList(Plugin),

    pub fn init(allocator: std.mem.Allocator) !PluginManager {
        return PluginManager{
            .allocator = allocator,
            .plugins = std.ArrayList(Plugin).init(allocator),
        };
    }

    pub fn deinit(self: *PluginManager) void {
        for (self.plugins.items) |*plugin| {
            plugin.deinit();
        }
        self.plugins.deinit();
    }

    pub fn spawn(
        self: *PluginManager,
        executable: []const u8,
        args: []const []const u8,
    ) !*Plugin {
        var plugin = Plugin{
            .allocator = self.allocator,
            .process = undefined,
            .stdin = undefined,
            .stdout = undefined,
        };

        // Spawn subprocess
        const argv = try self.buildArgv(executable, args);
        defer self.allocator.free(argv);

        plugin.process = try std.ChildProcess.init(argv, self.allocator);
        plugin.process.stdin_behavior = .Pipe;
        plugin.process.stdout_behavior = .Pipe;
        plugin.process.stderr_behavior = .Inherit;

        try plugin.process.spawn();

        plugin.stdin = plugin.process.stdin.?;
        plugin.stdout = plugin.process.stdout.?;

        try self.plugins.append(plugin);
        return &self.plugins.items[self.plugins.items.len - 1];
    }

    fn buildArgv(
        self: *PluginManager,
        executable: []const u8,
        args: []const []const u8,
    ) ![]const []const u8 {
        const argv = try self.allocator.alloc([]const u8, args.len + 1);
        argv[0] = executable;
        for (args, 0..) |arg, i| {
            argv[i + 1] = arg;
        }
        return argv;
    }
};

pub const Plugin = struct {
    allocator: std.mem.Allocator,
    process: std.ChildProcess,
    stdin: std.fs.File,
    stdout: std.fs.File,

    pub fn deinit(self: *Plugin) void {
        _ = self.process.kill() catch {};
    }

    pub fn sendMessage(self: *Plugin, message: []const u8) !void {
        // Write length prefix (4 bytes, little-endian)
        const len: u32 = @intCast(message.len);
        const len_bytes = std.mem.toBytes(len);
        try self.stdin.writeAll(&len_bytes);

        // Write message
        try self.stdin.writeAll(message);
    }

    pub fn receiveMessage(self: *Plugin, allocator: std.mem.Allocator) ![]u8 {
        // Read length prefix
        var len_bytes: [4]u8 = undefined;
        const bytes_read = try self.stdout.readAll(&len_bytes);
        if (bytes_read != 4) return error.UnexpectedEOF;

        const len = std.mem.readIntLittle(u32, &len_bytes);

        // Read message
        const message = try allocator.alloc(u8, len);
        errdefer allocator.free(message);

        const msg_bytes_read = try self.stdout.readAll(message);
        if (msg_bytes_read != len) return error.UnexpectedEOF;

        return message;
    }
};
