const std = @import("std");
const flake = @import("flake");

test "flake generator basic functionality" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Test generator initialization
    var gen = try flake.Generator.init(123, 0);
    try std.testing.expect(gen.worker_id == 123);

    // Test ID generation and uniqueness
    const id1 = gen.nextId();
    const id2 = gen.nextId();
    try std.testing.expect(id1 != id2);

    // Test string conversion
    const str1 = try flake.idToString(id1, allocator);
    const str2 = try flake.idToString(id2, allocator);
    try std.testing.expect(!std.mem.eql(u8, str1, str2));

    // Test decoding back
    const decoded1 = try flake.idFromString(str1, allocator);
    const decoded2 = try flake.idFromString(str2, allocator);
    try std.testing.expectEqual(id1, decoded1);
    try std.testing.expectEqual(id2, decoded2);
}

test "flake generator error cases" {
    // Test invalid worker ID
    try std.testing.expectError(error.InvalidWorkerId, flake.Generator.init(-1, 0));
    try std.testing.expectError(error.InvalidWorkerId, flake.Generator.init(1024, 0)); // max is 1023 (10 bits)

    // Test invalid epoch
    const timestamp_ms = @as(i64, @intCast(@divFloor(std.time.nanoTimestamp(), 1_000_000)));
    const far_future = timestamp_ms + 1_000_000_000;
    try std.testing.expectError(error.InvalidEpoch, flake.Generator.init(1, far_future));
}

test "flake ID string conversion" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var gen = try flake.Generator.init(1, 0);
    const id = gen.nextId();

    // Test round trip conversion
    const str = try flake.idToString(id, allocator);
    const decoded = try flake.idFromString(str, allocator);
    try std.testing.expectEqual(id, decoded);

    // Test invalid base64 string
    try std.testing.expectError(error.InvalidLength, flake.idFromString("invalid", allocator));
}

test "flake generator sequence overflow" {
    var gen = try flake.Generator.init(1, 0);
    var last_id: flake.FlakeID = 0;

    // Generate IDs rapidly to test sequence number handling
    for (0..10000) |_| {
        const id = gen.nextId();
        try std.testing.expect(id > last_id);
        last_id = id;
    }
}

test "flake ID multi generation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var gen = try flake.Generator.init(1, 0);
    const n: u32 = 100;
    const buf = try gen.genMulti(n, allocator);
    defer allocator.free(buf);

    try std.testing.expectEqual(buf.len, n * 8);

    // Check that each ID in the buffer is unique
    var seen = std.AutoHashMap(flake.FlakeID, void).init(allocator);
    defer seen.deinit();

    var i: usize = 0;
    while (i < n) : (i += 1) {
        const id = @as(flake.FlakeID, @intCast((@as(u64, buf[i * 8 + 0]) << 56) |
            (@as(u64, buf[i * 8 + 1]) << 48) |
            (@as(u64, buf[i * 8 + 2]) << 40) |
            (@as(u64, buf[i * 8 + 3]) << 32) |
            (@as(u64, buf[i * 8 + 4]) << 24) |
            (@as(u64, buf[i * 8 + 5]) << 16) |
            (@as(u64, buf[i * 8 + 6]) << 8) |
            @as(u64, buf[i * 8 + 7])));
        try std.testing.expect(!seen.contains(id));
        try seen.put(id, {});
    }
}
