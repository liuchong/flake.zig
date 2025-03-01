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

    const main_exe = b.addExecutable(.{
        .name = "flake",
        .root_source_file = .{ .cwd_relative = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    main_exe.root_module.addImport("flake", flake_module);
    main_exe.root_module.addImport("default_gen", default_gen_module);
    b.installArtifact(main_exe);

    const bench_exe = b.addExecutable(.{
        .name = "bench",
        .root_source_file = .{ .cwd_relative = "src/bench.zig" },
        .target = target,
        .optimize = optimize,
    });
    bench_exe.root_module.addImport("flake", flake_module);
    b.installArtifact(bench_exe);

    const run_bench = b.addRunArtifact(bench_exe);
    const bench_step = b.step("bench", "Run benchmark");
    bench_step.dependOn(&run_bench.step);

    const lib_unit_tests = b.addTest(.{
        .root_source_file = .{ .cwd_relative = "src/flake.zig" },
        .target = target,
        .optimize = optimize,
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
