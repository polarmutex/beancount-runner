const std = @import("std");

pub const PluginManager = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !PluginManager {
        return PluginManager{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *PluginManager) void {
        _ = self;
    }

    pub fn spawn(
        self: *PluginManager,
        io: std.Io,
        executable: []const u8,
        args: []const []const u8,
    ) !PluginProcess {
        return PluginProcess.spawn(self.allocator, io, executable, args);
    }
};

pub const PluginProcess = struct {
    allocator: std.mem.Allocator,
    child: std.process.Child,

    pub fn spawn(
        allocator: std.mem.Allocator,
        io: std.Io,
        executable: []const u8,
        args: []const []const u8,
    ) !PluginProcess {
        // Build full argv with executable as first element
        const argv = try allocator.alloc([]const u8, args.len + 1);
        argv[0] = executable;
        @memcpy(argv[1..], args);

        // Use std.process.spawn with Zig 0.16 API
        const child = try std.process.spawn(io, .{
            .argv = argv,
            .stdin = .pipe,
            .stdout = .pipe,
            .stderr = .pipe,
        });

        return PluginProcess{
            .allocator = allocator,
            .child = child,
        };
    }

    pub fn deinit(self: *PluginProcess, io: std.Io) void {
        _ = self.child.wait(io) catch {};
    }

    pub fn sendMessage(self: *PluginProcess, io: std.Io, message: []const u8) !void {
        const stdin = self.child.stdin.?;

        // Write length prefix (4 bytes, little endian)
        const len: u32 = @intCast(message.len);
        var len_bytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &len_bytes, len, .little);

        try stdin.writeStreamingAll(io, &len_bytes);
        try stdin.writeStreamingAll(io, message);
    }

    pub fn receiveMessage(self: *PluginProcess, io: std.Io, allocator: std.mem.Allocator) ![]u8 {
        const stdout = self.child.stdout.?;

        // Read length prefix (4 bytes, little endian)
        var len_bytes: [4]u8 = undefined;
        const len_slice: []u8 = &len_bytes;
        const len_buf_slice: []const []u8 = &[_][]u8{len_slice};
        const len_read = try stdout.readStreaming(io, len_buf_slice);
        if (len_read != 4) {
            return error.IncompleteMessage;
        }

        const len = std.mem.readInt(u32, &len_bytes, .little);

        // Read message data
        const message = try allocator.alloc(u8, len);
        errdefer allocator.free(message);

        const msg_buf_slice: []const []u8 = &[_][]u8{message};
        const msg_read = try stdout.readStreaming(io, msg_buf_slice);
        if (msg_read != len) {
            return error.IncompleteMessage;
        }

        return message;
    }
};
