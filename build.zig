const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const goose_dep = b.dependency("goose", .{
        .target = target,
        .optimize = optimize,
    });
    const goose_mod = goose_dep.module("goose");

    const lib_mod = b.addModule("conch", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "goose", .module = goose_mod },
        },
    });

    // Tests still run against the library.
    const tests = b.addTest(.{ .root_module = lib_mod });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
