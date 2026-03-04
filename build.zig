const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Main executable
    const exe = b.addExecutable(.{
        .name = "beancount-runner",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Install the executable
    b.installArtifact(exe);

    // Create run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    // Allow passing arguments to run step
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the beancount-runner");
    run_step.dependOn(&run_cmd.step);

    // Test executable
    const test_exe = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/validator_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_test = b.addRunArtifact(test_exe);

    // Deserialization tests
    const deserialization_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/test_deserialization.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_deserial_test = b.addRunArtifact(deserialization_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_test.step);
    test_step.dependOn(&run_deserial_test.step);
}
