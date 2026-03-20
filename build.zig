const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ========================================================================
    // Test Executable: exo_ws_test (legacy, tests raw streaming)
    // ========================================================================
    const exo_ws_test = b.addExecutable(.{
        .name = "exo_ws_test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/exo/exo_ws.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    exo_ws_test.linkLibC();

    const run_test = b.addRunArtifact(exo_ws_test);
    const test_step = b.step("test", "Run WebSocket tests");
    test_step.dependOn(&run_test.step);

    b.installArtifact(exo_ws_test);

    // ========================================================================
    // Server Executable: exo_server (Day 5 Frontend)
    // ========================================================================
    const exo_server = b.addExecutable(.{
        .name = "exo_server",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/exo/exo_server.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    exo_server.linkLibC();
    // OpenSSL linking - required for WSS/TLS support
    exo_server.linkSystemLibrary("ssl");
    exo_server.linkSystemLibrary("crypto");

    b.installArtifact(exo_server);

    // ========================================================================
    // Default step: build all
    // ========================================================================
    const build_all = b.step("build-all", "Build all executables");
    build_all.dependOn(&exo_ws_test.step);
    build_all.dependOn(&exo_server.step);

    // Note: SDK files (Zig, C headers, JavaScript) are provided in sdk/ directory
    // Users can import sdk/zig/exogrid.zig in their projects
    // C headers in sdk/c/ are ready to use with the compiled library
    // JavaScript SDK in sdk/js/ can be published to npm
}
