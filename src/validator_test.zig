// src/validator_test.zig
const std = @import("std");
const validator = @import("validator.zig");
const testing = std.testing;

test "empty directive list passes validation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var val = validator.Validator.init(allocator);

    // Validate empty list of directives
    const result = try val.validate(&[_]Directive{});
    defer allocator.free(result.errors);

    try testing.expect(result.is_valid);
    try testing.expectEqual(@as(usize, 0), result.errors.len);
}

test "single empty directive passes validation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create an empty directive (no transaction)
    const txn = createTestDirective(allocator);

    var val = validator.Validator.init(allocator);
    const result = try val.validate(&[_]Directive{txn});
    defer allocator.free(result.errors);

    // Empty directive should pass validation (no transaction to check)
    try testing.expect(result.is_valid);
    try testing.expectEqual(@as(usize, 0), result.errors.len);
}

fn createTestDirective(allocator: std.mem.Allocator) Directive {
    _ = allocator;
    // Create a minimal test transaction
    return Directive{
        .directive_type = .{
            .transaction = proto.Transaction{
                .date = proto.Date{ .year = 2024, .month = 1, .day = 1 },
                .flag = null,
                .payee = null,
                .narration = "",
                .tags = &[_][]const u8{},
                .links = &[_][]const u8{},
                .postings = &[_]proto.Posting{},
                .location = proto.Location{ .filename = "", .line = 0, .column = 0 },
            },
        },
    };
}

// Import Directive from proto module
const proto = @import("proto.zig");
const Directive = proto.Directive;
