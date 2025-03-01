const std = @import("std");
const flake = @import("flake.zig");
const FlakeID = flake.FlakeID;

const BenchConfig = struct {
    num_ids: usize = 10000,
    worker_id: i64 = 1,
    epoch: i64 = 1234567891011,
};

const BenchResult = struct {
    elapsed_ns: i128,
    ops_per_sec: f64,
};

fn runBench(config: BenchConfig) !BenchResult {
    std.debug.print("Starting single ID benchmark...\n", .{});
    var gen = try flake.Generator.init(config.worker_id, config.epoch);
    var timer = try std.time.Timer.start();

    timer.reset(); // Reset timer to avoid overflow
    const start = timer.read();
    var i: usize = 0;
    while (i < config.num_ids) : (i += 1) {
        _ = try gen.nextId();
        if (i % 1000 == 999) {
            std.debug.print("Generated {} IDs...\n", .{i + 1});
        }
    }
    const end = timer.read();
    const elapsed: i128 = @intCast(end - start);

    std.debug.print("Single ID benchmark completed.\n", .{});
    const ops_per_sec = @as(f64, @floatFromInt(config.num_ids)) / (@as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(std.time.ns_per_s)));
    return BenchResult{
        .elapsed_ns = elapsed,
        .ops_per_sec = ops_per_sec,
    };
}

fn runFastBench(config: BenchConfig) !BenchResult {
    std.debug.print("Starting fast ID benchmark...\n", .{});
    var gen = try flake.Generator.init(config.worker_id, config.epoch);
    var timer = try std.time.Timer.start();

    timer.reset(); // Reset timer to avoid overflow
    const start = timer.read();
    var i: usize = 0;
    while (i < config.num_ids) : (i += 1) {
        _ = gen.nextIdFast();
        if (i % 1000 == 999) {
            std.debug.print("Generated {} IDs (fast)...\n", .{i + 1});
        }
    }

    const end = timer.read();
    const elapsed: i128 = @intCast(end - start);
    const ops_per_sec = @as(f64, @floatFromInt(config.num_ids)) / (@as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(std.time.ns_per_s)));

    std.debug.print("Fast ID benchmark completed.\n", .{});
    return BenchResult{
        .elapsed_ns = elapsed,
        .ops_per_sec = ops_per_sec,
    };
}

fn runHighPrecisionBench(config: BenchConfig) !BenchResult {
    std.debug.print("Starting high-precision ID benchmark...\n", .{});
    var gen = try flake.Generator.init(config.worker_id, config.epoch);
    var timer = try std.time.Timer.start();

    timer.reset(); // Reset timer to avoid overflow
    const start = timer.read();
    var i: usize = 0;
    while (i < config.num_ids) : (i += 1) {
        _ = try gen.nextIdHighPrecision();
        if (i % 1000 == 999) {
            std.debug.print("Generated {} IDs (high-precision)...\n", .{i + 1});
        }
    }

    const end = timer.read();
    const elapsed: i128 = @intCast(end - start);
    const ops_per_sec = @as(f64, @floatFromInt(config.num_ids)) / (@as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(std.time.ns_per_s)));

    std.debug.print("High-precision ID benchmark completed.\n", .{});
    return BenchResult{
        .elapsed_ns = elapsed,
        .ops_per_sec = ops_per_sec,
    };
}

fn runSIMDBench(config: BenchConfig) !BenchResult {
    std.debug.print("Starting SIMD batch generation benchmark...\n", .{});
    var gen = try flake.Generator.init(config.worker_id, config.epoch);
    var timer = try std.time.Timer.start();

    const batch_size = 32 * 128; // 4096 bytes (128 batches of 4 IDs)
    var buffer = try std.heap.page_allocator.alloc(u8, batch_size);
    defer std.heap.page_allocator.free(buffer);

    timer.reset(); // Reset timer to avoid overflow
    const start = timer.read();
    var remaining = config.num_ids * 8; // Each ID is 8 bytes
    var total_written: usize = 0;

    while (remaining > 0) {
        const to_write = @min(remaining, batch_size);
        const written = try gen.genMultiSIMD(buffer[0..to_write]);
        total_written += written;
        remaining -= written;

        if (total_written % 8000 == 0) {
            std.debug.print("Generated {} IDs (SIMD)...\n", .{total_written / 8});
        }
    }
    const end = timer.read();
    const elapsed: i128 = @intCast(end - start);

    std.debug.print("SIMD batch generation benchmark completed.\n", .{});
    const ops_per_sec = @as(f64, @floatFromInt(config.num_ids)) / (@as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(std.time.ns_per_s)));
    return BenchResult{
        .elapsed_ns = elapsed,
        .ops_per_sec = ops_per_sec,
    };
}

fn runBulkBench(config: BenchConfig) !BenchResult {
    std.debug.print("Starting bulk ID benchmark...\n", .{});
    var gen = try flake.Generator.init(config.worker_id, config.epoch);
    var timer = try std.time.Timer.start();

    const batch_size = 8 * 128; // 1024 bytes (128 IDs)
    var buffer = try std.heap.page_allocator.alloc(u8, batch_size);
    defer std.heap.page_allocator.free(buffer);

    timer.reset(); // Reset timer to avoid overflow
    const start = timer.read();
    var remaining = config.num_ids * 8; // Each ID is 8 bytes
    var total_written: usize = 0;

    while (remaining > 0) {
        const to_write = @min(remaining, batch_size);
        const written = try gen.genMulti(buffer[0..to_write]);
        total_written += written;
        remaining -= written;
    }
    const end = timer.read();
    const elapsed: i128 = @intCast(end - start);

    std.debug.print("Bulk ID benchmark completed.\n", .{});
    const ops_per_sec = @as(f64, @floatFromInt(config.num_ids)) / (@as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(std.time.ns_per_s)));
    return BenchResult{
        .elapsed_ns = elapsed,
        .ops_per_sec = ops_per_sec,
    };
}

fn runBulkFastBench(config: BenchConfig) !BenchResult {
    std.debug.print("Starting fast bulk ID benchmark...\n", .{});
    var gen = try flake.Generator.init(config.worker_id, config.epoch);
    var timer = try std.time.Timer.start();

    const batch_size = 8 * 128; // 1024 bytes (128 IDs)
    var buffer = try std.heap.page_allocator.alloc(u8, batch_size);
    defer std.heap.page_allocator.free(buffer);

    timer.reset(); // Reset timer to avoid overflow
    const start = timer.read();
    var remaining = config.num_ids * 8; // Each ID is 8 bytes
    var total_written: usize = 0;

    while (remaining > 0) {
        const to_write = @min(remaining, batch_size);
        const written = gen.genMultiFast(buffer[0..to_write]);
        total_written += written;
        remaining -= written;
    }
    const end = timer.read();
    const elapsed: i128 = @intCast(end - start);

    std.debug.print("Fast bulk ID benchmark completed.\n", .{});
    const ops_per_sec = @as(f64, @floatFromInt(config.num_ids)) / (@as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(std.time.ns_per_s)));
    return BenchResult{
        .elapsed_ns = elapsed,
        .ops_per_sec = ops_per_sec,
    };
}

fn runStringBench(config: BenchConfig) !BenchResult {
    std.debug.print("Starting string conversion benchmark...\n", .{});
    var gen = try flake.Generator.init(config.worker_id, config.epoch);
    var timer = try std.time.Timer.start();

    var ids = try std.heap.page_allocator.alloc(flake.FlakeID, config.num_ids);
    defer std.heap.page_allocator.free(ids);

    // Generate IDs first
    for (0..config.num_ids) |i| {
        ids[i] = try gen.nextId();
    }

    // Now benchmark string conversion
    var buf: [12]u8 = undefined;
    timer.reset(); // Reset timer to avoid overflow
    const start = timer.read();
    var i: usize = 0;
    while (i < config.num_ids) : (i += 1) {
        try flake.Generator.idToStringBuf(ids[i], &buf);
        if (i % 1000 == 999) {
            std.debug.print("Converted {} IDs to strings...\n", .{i + 1});
        }
    }
    const end = timer.read();
    const elapsed: i128 = @intCast(end - start);

    std.debug.print("String conversion benchmark completed.\n", .{});
    const ops_per_sec = @as(f64, @floatFromInt(config.num_ids)) / (@as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(std.time.ns_per_s)));
    return BenchResult{
        .elapsed_ns = elapsed,
        .ops_per_sec = ops_per_sec,
    };
}

fn runStringFastBench(config: BenchConfig) !BenchResult {
    std.debug.print("Starting fast string conversion benchmark...\n", .{});
    var gen = try flake.Generator.init(config.worker_id, config.epoch);
    var timer = try std.time.Timer.start();

    var ids = try std.heap.page_allocator.alloc(flake.FlakeID, config.num_ids);
    defer std.heap.page_allocator.free(ids);

    // Generate IDs first
    for (0..config.num_ids) |i| {
        ids[i] = try gen.nextId();
    }

    // Now benchmark fast string conversion
    var buf: [12]u8 = undefined;
    timer.reset(); // Reset timer to avoid overflow
    const start = timer.read();
    var i: usize = 0;
    while (i < config.num_ids) : (i += 1) {
        try flake.Generator.idToStringBufFast(ids[i], &buf);
        if (i % 1000 == 999) {
            std.debug.print("Converted {} IDs to strings (fast)...\n", .{i + 1});
        }
    }
    const end = timer.read();
    const elapsed: i128 = @intCast(end - start);

    std.debug.print("Fast string conversion benchmark completed.\n", .{});
    const ops_per_sec = @as(f64, @floatFromInt(config.num_ids)) / (@as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(std.time.ns_per_s)));
    return BenchResult{
        .elapsed_ns = elapsed,
        .ops_per_sec = ops_per_sec,
    };
}

fn runParsingBench(config: BenchConfig) !BenchResult {
    std.debug.print("Starting string parsing benchmark...\n", .{});
    var gen = try flake.Generator.init(config.worker_id, config.epoch);
    var timer = try std.time.Timer.start();

    var ids = try std.heap.page_allocator.alloc(flake.FlakeID, config.num_ids);
    defer std.heap.page_allocator.free(ids);

    // Generate IDs first
    for (0..config.num_ids) |i| {
        ids[i] = try gen.nextId();
    }

    // Convert to strings
    var strings = try std.heap.page_allocator.alloc([12]u8, config.num_ids);
    defer std.heap.page_allocator.free(strings);

    for (0..config.num_ids) |i| {
        try flake.Generator.idToStringBuf(ids[i], &strings[i]);
    }

    // Now benchmark parsing
    timer.reset(); // Reset timer to avoid overflow
    const start = timer.read();
    var i: usize = 0;
    while (i < config.num_ids) : (i += 1) {
        _ = try flake.Generator.idFromStringBuf(&strings[i]);
        if (i % 1000 == 999) {
            std.debug.print("Parsed {} strings back to IDs...\n", .{i + 1});
        }
    }
    const end = timer.read();
    const elapsed: i128 = @intCast(end - start);

    std.debug.print("String parsing benchmark completed.\n", .{});
    const ops_per_sec = @as(f64, @floatFromInt(config.num_ids)) / (@as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(std.time.ns_per_s)));
    return BenchResult{
        .elapsed_ns = elapsed,
        .ops_per_sec = ops_per_sec,
    };
}

fn runParsingFastBench(config: BenchConfig) !BenchResult {
    std.debug.print("Starting fast string parsing benchmark...\n", .{});
    var gen = try flake.Generator.init(config.worker_id, config.epoch);
    var timer = try std.time.Timer.start();

    var ids = try std.heap.page_allocator.alloc(flake.FlakeID, config.num_ids);
    defer std.heap.page_allocator.free(ids);

    // Generate IDs first
    for (0..config.num_ids) |i| {
        ids[i] = try gen.nextId();
    }

    // Convert to strings
    var strings = try std.heap.page_allocator.alloc([12]u8, config.num_ids);
    defer std.heap.page_allocator.free(strings);

    for (0..config.num_ids) |i| {
        try flake.Generator.idToStringBuf(ids[i], &strings[i]);
    }

    // Now benchmark fast parsing
    timer.reset(); // Reset timer to avoid overflow
    const start = timer.read();
    var i: usize = 0;
    while (i < config.num_ids) : (i += 1) {
        _ = try flake.Generator.idFromStringBufFast(&strings[i]);
        if (i % 1000 == 999) {
            std.debug.print("Parsed {} strings back to IDs (fast)...\n", .{i + 1});
        }
    }
    const end = timer.read();
    const elapsed: i128 = @intCast(end - start);

    std.debug.print("Fast string parsing benchmark completed.\n", .{});
    const ops_per_sec = @as(f64, @floatFromInt(config.num_ids)) / (@as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(std.time.ns_per_s)));
    return BenchResult{
        .elapsed_ns = elapsed,
        .ops_per_sec = ops_per_sec,
    };
}

pub fn main() !void {
    const config = BenchConfig{};

    std.debug.print("\nRunning benchmarks with {} operations...\n", .{config.num_ids});

    // Standard benchmarks
    std.debug.print("\n=== STANDARD METHODS ===\n", .{});
    const single_result = try runBench(config);
    std.debug.print("Single ID generation: {d:.2} ops/sec\n", .{single_result.ops_per_sec});

    const bulk_result = try runBulkBench(config);
    std.debug.print("Bulk ID generation: {d:.2} ops/sec\n", .{bulk_result.ops_per_sec});

    const string_result = try runStringBench(config);
    std.debug.print("String conversion: {d:.2} ops/sec\n", .{string_result.ops_per_sec});

    const parsing_result = try runParsingBench(config);
    std.debug.print("String parsing: {d:.2} ops/sec\n", .{parsing_result.ops_per_sec});

    // Optimized benchmarks
    std.debug.print("\n=== OPTIMIZED METHODS ===\n", .{});
    const fast_result = try runFastBench(config);
    std.debug.print("Fast ID generation: {d:.2} ops/sec\n", .{fast_result.ops_per_sec});

    const high_precision_result = try runHighPrecisionBench(config);
    std.debug.print("High-precision ID generation: {d:.2} ops/sec\n", .{high_precision_result.ops_per_sec});

    const simd_result = try runSIMDBench(config);
    std.debug.print("SIMD batch generation: {d:.2} ops/sec\n", .{simd_result.ops_per_sec});

    const bulk_fast_result = try runBulkFastBench(config);
    std.debug.print("Fast bulk ID generation: {d:.2} ops/sec\n", .{bulk_fast_result.ops_per_sec});

    const string_fast_result = try runStringFastBench(config);
    std.debug.print("Fast string conversion: {d:.2} ops/sec\n", .{string_fast_result.ops_per_sec});

    const parsing_fast_result = try runParsingFastBench(config);
    std.debug.print("Fast string parsing: {d:.2} ops/sec\n", .{parsing_fast_result.ops_per_sec});

    // Print performance improvements
    std.debug.print("\n=== PERFORMANCE IMPROVEMENTS ===\n", .{});
    std.debug.print("ID generation: {d:.2}x faster\n", .{fast_result.ops_per_sec / single_result.ops_per_sec});
    std.debug.print("High-precision ID generation: {d:.2}x faster\n", .{high_precision_result.ops_per_sec / single_result.ops_per_sec});
    std.debug.print("SIMD batch generation: {d:.2}x faster\n", .{simd_result.ops_per_sec / bulk_result.ops_per_sec});
    std.debug.print("Fast bulk generation: {d:.2}x faster\n", .{bulk_fast_result.ops_per_sec / bulk_result.ops_per_sec});
    std.debug.print("Fast string conversion: {d:.2}x faster\n", .{string_fast_result.ops_per_sec / string_result.ops_per_sec});
    std.debug.print("Fast string parsing: {d:.2}x faster\n", .{parsing_fast_result.ops_per_sec / parsing_result.ops_per_sec});
}
