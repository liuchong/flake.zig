const std = @import("std");
const testing = std.testing;
const flake = @import("flake");

test "flake id generation" {
    var gen = try flake.Generator.init(1, 0);
    const id = try gen.nextId();
    try testing.expect(id > 0);
}

test "flake id uniqueness" {
    var gen = try flake.Generator.init(1, 0);
    var seen = std.AutoHashMap(flake.FlakeID, void).init(testing.allocator);
    defer seen.deinit();

    // Generate and check 10000 IDs for uniqueness
    for (0..10000) |_| {
        const id = try gen.nextId();
        try testing.expect(!seen.contains(id));
        try seen.put(id, {});
    }
}

test "flake id ordering" {
    var gen = try flake.Generator.init(1, 0);
    var last_id: flake.FlakeID = 0;

    // Generate and check 10000 IDs for ordering
    for (0..10000) |_| {
        const id = try gen.nextId();
        try testing.expect(id > last_id);
        last_id = id;
    }
}

test "bulk id generation" {
    var gen = try flake.Generator.init(1, 0);
    var buf: [1024 * 8]u8 = undefined;
    const written = try gen.genMulti(&buf);
    try testing.expectEqual(written, buf.len);
}

test "id to string conversion" {
    var gen = try flake.Generator.init(1, 0);
    const id = try gen.nextId();
    var str_buf: [12]u8 = undefined;
    try flake.Generator.idToStringBuf(id, &str_buf);

    // Test string format
    for (str_buf) |c| {
        try testing.expect(switch (c) {
            'A'...'Z', 'a'...'z', '0'...'9', '-', '_' => true,
            else => false,
        });
    }
}

test "string to id conversion" {
    var gen = try flake.Generator.init(1, 0);
    const original_id = try gen.nextId();
    var str_buf: [12]u8 = undefined;
    try flake.Generator.idToStringBuf(original_id, &str_buf);

    const decoded_id = try flake.Generator.idFromStringBuf(&str_buf);
    try testing.expectEqual(original_id, decoded_id);
}

test "invalid worker id" {
    try testing.expectError(error.InvalidWorkerId, flake.Generator.init(1024, 0));
    try testing.expectError(error.InvalidWorkerId, flake.Generator.init(-1, 0));
}

test "invalid epoch" {
    const future_epoch = @divFloor(std.time.nanoTimestamp(), std.time.ns_per_ms) + 1000000;
    try testing.expectError(error.InvalidEpoch, flake.Generator.init(1, future_epoch));
}

test "sequence overflow handling" {
    var gen = try flake.Generator.init(1, 0);
    var last_id: flake.FlakeID = 0;

    // Generate IDs rapidly to force sequence overflow
    for (0..10000) |_| {
        const id = try gen.nextId();
        try testing.expect(id > last_id);
        last_id = id;
    }
}

test "concurrent id generation" {
    const ThreadContext = struct {
        gen: *flake.Generator,
        count: usize,
        seen: *std.AutoHashMap(flake.FlakeID, void),
        mutex: *std.Thread.Mutex,
    };

    fn generateIds(ctx: *ThreadContext) !void {
        for (0..ctx.count) |_| {
            const id = try ctx.gen.nextId();
            ctx.mutex.lock();
            defer ctx.mutex.unlock();
            try testing.expect(!ctx.seen.contains(id));
            try ctx.seen.put(id, {});
        }
    }

    var gen = try flake.Generator.init(1, 0);
    var seen = std.AutoHashMap(flake.FlakeID, void).init(testing.allocator);
    defer seen.deinit();
    var mutex = std.Thread.Mutex{};

    const thread_count = 4;
    const ids_per_thread = 1000;
    var threads: [thread_count]std.Thread = undefined;
    var contexts: [thread_count]ThreadContext = undefined;

    // Start threads
    for (&threads, 0..) |*thread, i| {
        contexts[i] = ThreadContext{
            .gen = &gen,
            .count = ids_per_thread,
            .seen = &seen,
            .mutex = &mutex,
        };
        thread.* = try std.Thread.spawn(.{}, generateIds, .{&contexts[i]});
    }

    // Wait for all threads
    for (threads) |thread| {
        thread.join();
    }

    // Verify total number of unique IDs
    try testing.expectEqual(seen.count(), thread_count * ids_per_thread);
}
