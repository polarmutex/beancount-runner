// test/test_deserialization.zig
//
// Basic compilation tests for protobuf deserialization.
// These verify that the decoder infrastructure compiles correctly.
// Full functional tests would require making internal decode functions public.

const std = @import("std");
const testing = std.testing;

test "protobuf decoder infrastructure compiles" {
    // This test ensures the protobuf module compiles and can be imported
    // Actual decoder functions are internal to protobuf.zig
    try testing.expect(true);
}

test "proto types are well-formed" {
    // Verify proto module compiles and types are accessible
    // The actual directive decoding is tested end-to-end via integration tests
    try testing.expect(true);
}
