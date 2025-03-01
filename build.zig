const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const flake_module = b.addModule("flake", .{
        .root_source_file = .{ .cwd_relative = "src/flake.zig" },
    });

    const default_gen_module = b.addModule("default_gen", .{
        .root_source_file = .{ .cwd_relative = "src/default_gen.zig" },
        .imports = &.{
            .{ .name = "flake", .module = flake_module },
        },
    });

    const lib = b.addStaticLibrary(.{
        .name = "flake",
        .root_source_file = .{ .cwd_relative = "src/flake.zig" },
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);

    const main_tests = b.addTest(.{
        .root_source_file = .{ .cwd_relative = "src/flake_test.zig" },
        .target = target,
        .optimize = optimize,
    });
    main_tests.root_module.addImport("flake", flake_module);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);

    const exe = b.addExecutable(.{
        .name = "flake-example",
        .root_source_file = .{ .cwd_relative = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("flake", flake_module);
    exe.root_module.addImport("default_gen", default_gen_module);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    const run_step = b.step("run", "Run the example");
    run_step.dependOn(&run_cmd.step);
}
