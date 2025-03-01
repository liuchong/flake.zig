const std = @import("std");
const flake = @import("flake");

// Global default generator
var default_gen: ?flake.Generator = null;
var default_gen_init = false;
var default_gen_mutex: std.Thread.Mutex = .{};

// Generate a worker ID based on timestamp and random number
fn generateWorkerId() i64 {
    var prng = std.rand.DefaultPrng.init(@as(u64, @intCast(@divFloor(std.time.nanoTimestamp(), std.time.ns_per_ms))));
    const random = prng.random().int(u16);
    // Use random number to create a unique worker ID within the valid range
    return @mod(@as(i64, random), flake.max_worker_id + 1);
}

// Initialize the default generator
fn initDefaultGen() !void {
    default_gen_mutex.lock();
    defer default_gen_mutex.unlock();

    if (default_gen_init) return;

    const worker_id = generateWorkerId();
    default_gen = try flake.Generator.init(worker_id, 0);
    default_gen_init = true;
}

// Get an ID from the default generator
pub fn getDefault() !flake.FlakeID {
    if (!default_gen_init) {
        try initDefaultGen();
    }
    return default_gen.?.nextId();
}
