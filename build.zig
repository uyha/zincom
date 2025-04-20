const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zincom = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libcpp = true,
    });
    if (b.lazyDependency("zimq", .{
        .target = target,
        .optimize = optimize,
    })) |zimq| {
        zincom.addImport("zimq", zimq.module("zimq"));
    }
    if (b.lazyDependency("mzg", .{
        .target = target,
        .optimize = optimize,
    })) |zimq| {
        zincom.addImport("mzg", zimq.module("mzg"));
    }

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "zincom",
        .root_module = zincom,
    });
    b.installArtifact(lib);

    const lib_unit_tests = b.addTest(.{
        .root_module = zincom,
        .target = target,
        .optimize = optimize,
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
