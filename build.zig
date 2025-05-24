const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "zincom",
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);

    const docs = b.addInstallDirectory(.{
        .install_dir = .prefix,
        .install_subdir = "docs",
        .source_dir = lib.getEmittedDocs(),
    });
    const docs_step = b.step("docs", "Emit documentation");
    docs_step.dependOn(&docs.step);

    const unit_tests = b.addTest(.{
        .root_module = lib.root_module,
        .target = target,
        .optimize = optimize,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);

    const integration_tests = b.addTest(.{
        .root_source_file = b.path("tests/all.zig"),
        .target = target,
        .optimize = optimize,
    });
    integration_tests.root_module.addImport("zic", lib.root_module);
    const run_integration_tests = b.addRunArtifact(integration_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
    test_step.dependOn(&run_integration_tests.step);

    const all_step = b.step("all", "Run all steps");
    all_step.dependOn(test_step);
    all_step.dependOn(docs_step);

    if (b.lazyDependency("zimq", .{
        .target = target,
        .optimize = optimize,
    })) |dep| {
        const module = dep.module("zimq");
        lib.root_module.addImport("zimq", module);
        integration_tests.root_module.addImport("zimq", module);
    }
    if (b.lazyDependency("mzg", .{
        .target = target,
        .optimize = optimize,
    })) |dep| {
        const module = dep.module("mzg");
        lib.root_module.addImport("mzg", module);
        integration_tests.root_module.addImport("mzg", module);
    }
}
