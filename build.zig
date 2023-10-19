const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) !void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "my-wtf-project",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = .{ .path = "testzon.zig" },
        .target = target,
        .optimize = optimize,
    });

    const duck = b.dependency("duck", .{
        .target = target,
        .optimize = optimize,
    });
    exe.addModule("duck", duck.module("duck"));
    exe.linkLibrary(duck.artifact("duck"));

    exe.addIncludePath(.{ .path = duck.builder.pathFromRoot(
        duck.module("libduckdb.include").source_file.path,
    ) });
    exe.addLibraryPath(.{ .path = duck.builder.pathFromRoot(
        duck.module("libduckdb.lib").source_file.path,
    ) });
    //  You'll get segmentation fault if you don't link with libC
    exe.linkLibC();
    exe.linkSystemLibraryName("duckdb");

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // you must set the LD_LIBRARY_PATH to find libduckdb.so
    run_cmd.setEnvironmentVariable("LD_LIBRARY_PATH", duck.builder.pathFromRoot(
        duck.module("libduckdb.lib").source_file.path,
    ));

    const run_step = b.step("run", "Run the test");
    run_step.dependOn(&run_cmd.step);
}
