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
    // TODO: Create proper test transaction structure
    // This will be implemented once we have actual protobuf types
    // For now, this is a placeholder that will always return an empty directive
    return Directive{};
}

// Import placeholder types from validator module
const Directive = validator.Directive;
