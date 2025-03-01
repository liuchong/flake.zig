const std = @import("std");
const flake = @import("flake");
const FlakeID = flake.FlakeID;

const BenchConfig = struct {
    num_ids: usize = 10_000,
    worker_id: i64 = 1,
    epoch: i64 = 0,
};

const BenchResult = struct {
    elapsed_ns: u64,
    ops_per_sec: f64,
};

fn runBench(config: BenchConfig) !BenchResult {
    std.debug.print("Starting single ID benchmark...\n", .{});
    var gen = try flake.Generator.init(config.worker_id, config.epoch);
    var timer = try std.time.Timer.start();
    const start = timer.lap();

    var i: usize = 0;
    while (i < config.num_ids) : (i += 1) {
        _ = try gen.nextId();
        if (i % 1000 == 0 and i > 0) {
            std.debug.print("Generated {d} IDs...\n", .{i});
        }
    }

    const end = timer.read();
    const elapsed = end - start;
    const ops_per_sec = @as(f64, @floatFromInt(config.num_ids)) / (@as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(std.time.ns_per_s)));

    std.debug.print("Single ID benchmark completed.\n", .{});
    return BenchResult{
        .elapsed_ns = elapsed,
        .ops_per_sec = ops_per_sec,
    };
}

fn runBulkBench(config: BenchConfig) !BenchResult {
    std.debug.print("Starting bulk ID benchmark...\n", .{});
    var gen = try flake.Generator.init(config.worker_id, config.epoch);
    const bulk_buf = try std.heap.page_allocator.alloc(u8, 1024 * 8);
    defer std.heap.page_allocator.free(bulk_buf);

    var timer = try std.time.Timer.start();
    const start = timer.lap();

    var i: usize = 0;
    const batch_size = 1024;
    while (i < config.num_ids) : (i += batch_size) {
        _ = try gen.genMulti(bulk_buf);
        if (i % 1000 == 0 and i > 0) {
            std.debug.print("Generated {d} bulk IDs...\n", .{i});
        }
    }

    const end = timer.read();
    const elapsed = end - start;
    const ops_per_sec = @as(f64, @floatFromInt(config.num_ids)) / (@as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(std.time.ns_per_s)));

    std.debug.print("Bulk ID benchmark completed.\n", .{});
    return BenchResult{
        .elapsed_ns = elapsed,
        .ops_per_sec = ops_per_sec,
    };
}

fn runStringBench(config: BenchConfig) !BenchResult {
    std.debug.print("Starting string conversion benchmark...\n", .{});
    var gen = try flake.Generator.init(config.worker_id, config.epoch);
    var str_buf: [12]u8 = undefined;

    var timer = try std.time.Timer.start();
    const start = timer.lap();

    var i: usize = 0;
    while (i < config.num_ids) : (i += 1) {
        const test_id = try gen.nextId();
        try flake.Generator.idToStringBuf(test_id, &str_buf);
        if (i % 1000 == 0 and i > 0) {
            std.debug.print("Converted {d} IDs to strings...\n", .{i});
        }
    }

    const end = timer.read();
    const elapsed = end - start;
    const ops_per_sec = @as(f64, @floatFromInt(config.num_ids)) / (@as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(std.time.ns_per_s)));

    std.debug.print("String conversion benchmark completed.\n", .{});
    return BenchResult{
        .elapsed_ns = elapsed,
        .ops_per_sec = ops_per_sec,
    };
}

fn runParsingBench(config: BenchConfig) !BenchResult {
    std.debug.print("Starting string parsing benchmark...\n", .{});
    var gen = try flake.Generator.init(config.worker_id, config.epoch);
    var str_buf: [12]u8 = undefined;

    var timer = try std.time.Timer.start();
    const start = timer.lap();

    var i: usize = 0;
    while (i < config.num_ids) : (i += 1) {
        const test_id = try gen.nextId();
        try flake.Generator.idToStringBuf(test_id, &str_buf);
        _ = try flake.Generator.idFromStringBuf(&str_buf);
        if (i % 1000 == 0 and i > 0) {
            std.debug.print("Parsed {d} strings back to IDs...\n", .{i});
        }
    }

    const end = timer.read();
    const elapsed = end - start;
    const ops_per_sec = @as(f64, @floatFromInt(config.num_ids)) / (@as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(std.time.ns_per_s)));

    std.debug.print("String parsing benchmark completed.\n", .{});
    return BenchResult{
        .elapsed_ns = elapsed,
        .ops_per_sec = ops_per_sec,
    };
}

pub fn main() !void {
    const config = BenchConfig{};

    std.debug.print("\nRunning benchmarks with {d} operations...\n", .{config.num_ids});

    const single_result = try runBench(config);
    std.debug.print("Single ID generation: {d:.2} ops/sec\n", .{single_result.ops_per_sec});

    const bulk_result = try runBulkBench(config);
    std.debug.print("Bulk ID generation: {d:.2} ops/sec\n", .{bulk_result.ops_per_sec});

    const string_result = try runStringBench(config);
    std.debug.print("String conversion: {d:.2} ops/sec\n", .{string_result.ops_per_sec});

    const parsing_result = try runParsingBench(config);
    std.debug.print("String parsing: {d:.2} ops/sec\n", .{parsing_result.ops_per_sec});
}
