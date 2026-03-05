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

pub fn writeText(
    allocator: std.mem.Allocator,
    io: std.Io,
    directives: []const proto.Directive,
    errors: []const proto.Error,
    input_path: []const u8,
    path: []const u8,
) !void {
    // Build text output in memory
    var text_buffer = std.ArrayList(u8){
        .items = &[_]u8{},
        .capacity = 0,
    };
    defer text_buffer.deinit(allocator);

    // Header
    try text_buffer.appendSlice(allocator, "=== Pipeline Results ===\n");
    const header_input = try std.fmt.allocPrint(allocator, "Input: {s}\n", .{input_path});
    defer allocator.free(header_input);
    try text_buffer.appendSlice(allocator, header_input);
    try text_buffer.appendSlice(allocator, "\n");

    // Directives section
    const directive_header = try std.fmt.allocPrint(allocator, "--- Directives ({d}) ---\n\n", .{directives.len});
    defer allocator.free(directive_header);
    try text_buffer.appendSlice(allocator, directive_header);

    for (directives) |directive| {
        try writeDirectiveTextToBuffer(allocator, &text_buffer, directive);
        try text_buffer.appendSlice(allocator, "\n");
    }

    // Errors section
    const error_header = try std.fmt.allocPrint(allocator, "--- Errors ({d}) ---\n\n", .{errors.len});
    defer allocator.free(error_header);
    try text_buffer.appendSlice(allocator, error_header);

    for (errors) |err| {
        try writeErrorTextToBuffer(allocator, &text_buffer, err);
        try text_buffer.appendSlice(allocator, "\n");
    }

    // Write to file
    const cwd_dir = std.Io.Dir.cwd();
    var file = try cwd_dir.createFile(io, path, .{});
    defer file.close(io);

    try file.writeStreamingAll(io, text_buffer.items);
}

fn writeDirectiveTextToBuffer(allocator: std.mem.Allocator, buffer: *std.ArrayList(u8), directive: proto.Directive) !void {
    switch (directive.directive_type) {
        .transaction => |txn| {
            // Transaction header with date, flag, payee, narration
            var line: std.ArrayList(u8) = .empty;
            defer line.deinit(allocator);

            const date_str = try std.fmt.allocPrint(allocator, "{d}-{d:0>2}-{d:0>2}", .{
                txn.date.year,
                txn.date.month,
                txn.date.day,
            });
            defer allocator.free(date_str);
            try line.appendSlice(allocator, date_str);

            if (txn.flag) |flag| {
                try line.appendSlice(allocator, " ");
                try line.appendSlice(allocator, flag);
            }

            if (txn.payee) |payee| {
                const payee_str = try std.fmt.allocPrint(allocator, " \"{s}\"", .{payee});
                defer allocator.free(payee_str);
                try line.appendSlice(allocator, payee_str);
            }

            const narration_str = try std.fmt.allocPrint(allocator, " \"{s}\"\n", .{txn.narration});
            defer allocator.free(narration_str);
            try line.appendSlice(allocator, narration_str);

            try buffer.appendSlice(allocator, line.items);

            // Postings
            for (txn.postings) |posting| {
                var posting_line: std.ArrayList(u8) = .empty;
                defer posting_line.deinit(allocator);

                const posting_str = try std.fmt.allocPrint(
                    allocator,
                    "  {s:<40}",
                    .{posting.account},
                );
                defer allocator.free(posting_str);
                try posting_line.appendSlice(allocator, posting_str);

                if (posting.amount) |amount| {
                    const amount_str = try std.fmt.allocPrint(
                        allocator,
                        "{s:>10} {s}\n",
                        .{ amount.number, amount.currency },
                    );
                    defer allocator.free(amount_str);
                    try posting_line.appendSlice(allocator, amount_str);
                } else {
                    try posting_line.appendSlice(allocator, "\n");
                }

                try buffer.appendSlice(allocator, posting_line.items);
            }

            // Location
            const location_str = try std.fmt.allocPrint(
                allocator,
                "  [{s}:{d}]\n",
                .{ txn.location.filename, txn.location.line },
            );
            defer allocator.free(location_str);
            try buffer.appendSlice(allocator, location_str);
        },
        .balance => |bal| {
            const text_str = try std.fmt.allocPrint(
                allocator,
                "{d}-{d:0>2}-{d:0>2} balance {s} {s} {s}\n  [{s}:{d}]\n",
                .{
                    bal.date.year,
                    bal.date.month,
                    bal.date.day,
                    bal.account,
                    bal.amount.number,
                    bal.amount.currency,
                    bal.location.filename,
                    bal.location.line,
                },
            );
            defer allocator.free(text_str);
            try buffer.appendSlice(allocator, text_str);
        },
        .open => |open| {
            var currencies_str: std.ArrayList(u8) = .empty;
            defer currencies_str.deinit(allocator);

            for (open.currencies, 0..) |currency, i| {
                try currencies_str.appendSlice(allocator, currency);
                if (i < open.currencies.len - 1) {
                    try currencies_str.appendSlice(allocator, ", ");
                }
            }

            const text_str = try std.fmt.allocPrint(
                allocator,
                "{d}-{d:0>2}-{d:0>2} open {s} {s}\n  [{s}:{d}]\n",
                .{
                    open.date.year,
                    open.date.month,
                    open.date.day,
                    open.account,
                    currencies_str.items,
                    open.location.filename,
                    open.location.line,
                },
            );
            defer allocator.free(text_str);
            try buffer.appendSlice(allocator, text_str);
        },
        .close => |close| {
            const text_str = try std.fmt.allocPrint(
                allocator,
                "{d}-{d:0>2}-{d:0>2} close {s}\n  [{s}:{d}]\n",
                .{
                    close.date.year,
                    close.date.month,
                    close.date.day,
                    close.account,
                    close.location.filename,
                    close.location.line,
                },
            );
            defer allocator.free(text_str);
            try buffer.appendSlice(allocator, text_str);
        },
        .pad => |pad| {
            const text_str = try std.fmt.allocPrint(
                allocator,
                "{d}-{d:0>2}-{d:0>2} pad {s} {s}\n  [{s}:{d}]\n",
                .{
                    pad.date.year,
                    pad.date.month,
                    pad.date.day,
                    pad.account,
                    pad.source_account,
                    pad.location.filename,
                    pad.location.line,
                },
            );
            defer allocator.free(text_str);
            try buffer.appendSlice(allocator, text_str);
        },
    }
}

fn writeErrorTextToBuffer(allocator: std.mem.Allocator, buffer: *std.ArrayList(u8), err: proto.Error) !void {
    var error_str: std.ArrayList(u8) = .empty;
    defer error_str.deinit(allocator);

    try error_str.appendSlice(allocator, "[ERROR] ");
    try error_str.appendSlice(allocator, err.message);
    try error_str.appendSlice(allocator, "\n");

    if (err.location) |loc| {
        const location_str = try std.fmt.allocPrint(allocator, "  Location: {s}:{d}:{d}\n", .{
            loc.filename,
            loc.line,
            loc.column,
        });
        defer allocator.free(location_str);
        try error_str.appendSlice(allocator, location_str);
    }

    try buffer.appendSlice(allocator, error_str.items);
}
