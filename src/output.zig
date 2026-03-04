const std = @import("std");
const proto = @import("proto.zig");

pub fn writeJson(
    allocator: std.mem.Allocator,
    io: std.Io,
    directives: []const proto.Directive,
    errors: []const proto.Error,
    path: []const u8,
) !void {
    // Build JSON string in memory
    var json_buffer = std.ArrayList(u8){
        .items = &[_]u8{},
        .capacity = 0,
    };
    defer json_buffer.deinit(allocator);

    try json_buffer.appendSlice(allocator, "{\n");
    try json_buffer.appendSlice(allocator, "  \"directives\": [\n");

    for (directives, 0..) |directive, i| {
        try writeDirectiveJsonToBuffer(allocator, &json_buffer, directive);
        if (i < directives.len - 1) {
            try json_buffer.appendSlice(allocator, ",\n");
        }
    }

    try json_buffer.appendSlice(allocator, "\n  ],\n");
    try json_buffer.appendSlice(allocator, "  \"errors\": [\n");

    for (errors, 0..) |err, i| {
        try writeErrorJsonToBuffer(allocator, &json_buffer, err);
        if (i < errors.len - 1) {
            try json_buffer.appendSlice(allocator, ",\n");
        }
    }

    try json_buffer.appendSlice(allocator, "\n  ]\n");
    try json_buffer.appendSlice(allocator, "}\n");

    // Write to file
    const cwd_dir = std.Io.Dir.cwd();
    var file = try cwd_dir.createFile(io, path, .{});
    defer file.close(io);

    try file.writeStreamingAll(io, json_buffer.items);
}

fn writeDirectiveJsonToBuffer(allocator: std.mem.Allocator, buffer: *std.ArrayList(u8), directive: proto.Directive) !void {
    const json_str = switch (directive.directive_type) {
        .transaction => |txn| try std.fmt.allocPrint(allocator, "    {{\"type\": \"transaction\", \"date\": \"{d}-{d:0>2}-{d:0>2}\", \"narration\": \"{s}\"}}", .{
            txn.date.year,
            txn.date.month,
            txn.date.day,
            txn.narration,
        }),
        .balance => |bal| try std.fmt.allocPrint(allocator, "    {{\"type\": \"balance\", \"account\": \"{s}\", \"amount\": \"{s} {s}\"}}", .{
            bal.account,
            bal.amount.number,
            bal.amount.currency,
        }),
        .open => |open| try std.fmt.allocPrint(allocator, "    {{\"type\": \"open\", \"date\": \"{d}-{d:0>2}-{d:0>2}\", \"account\": \"{s}\"}}", .{
            open.date.year,
            open.date.month,
            open.date.day,
            open.account,
        }),
        .close => |close| try std.fmt.allocPrint(allocator, "    {{\"type\": \"close\", \"date\": \"{d}-{d:0>2}-{d:0>2}\", \"account\": \"{s}\"}}", .{
            close.date.year,
            close.date.month,
            close.date.day,
            close.account,
        }),
        .pad => |pad| try std.fmt.allocPrint(allocator, "    {{\"type\": \"pad\", \"date\": \"{d}-{d:0>2}-{d:0>2}\", \"account\": \"{s}\", \"source_account\": \"{s}\"}}", .{
            pad.date.year,
            pad.date.month,
            pad.date.day,
            pad.account,
            pad.source_account,
        }),
    };
    defer allocator.free(json_str);
    try buffer.appendSlice(allocator, json_str);
}

fn writeErrorJsonToBuffer(allocator: std.mem.Allocator, buffer: *std.ArrayList(u8), err: proto.Error) !void {
    const json_str = try std.fmt.allocPrint(allocator, "    {{\"message\": \"{s}\", \"source\": \"{s}\"}}", .{
        err.message,
        err.source,
    });
    defer allocator.free(json_str);
    try buffer.appendSlice(allocator, json_str);
}
