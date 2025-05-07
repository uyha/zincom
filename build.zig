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

    const integration_tests = b.addTest(.{
        .root_source_file = b.path(b.pathJoin(&.{ "tests", "all.zig" })),
        .target = target,
        .optimize = optimize,
    });
    integration_tests.root_module.addImport("zic", lib.root_module);
    const run_integration_tests = b.addRunArtifact(integration_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_integration_tests.step);

    if (b.lazyDependency("zimq", .{
        .target = target,
        .optimize = optimize,
    })) |dep| {
        const module = dep.module("zimq");
        zincom.addImport("zimq", module);
        integration_tests.root_module.addImport("zimq", module);
    }
    if (b.lazyDependency("mzg", .{
        .target = target,
        .optimize = optimize,
    })) |dep| {
        const module = dep.module("mzg");
        zincom.addImport("mzg", module);
        integration_tests.root_module.addImport("mzg", module);
    }
}
