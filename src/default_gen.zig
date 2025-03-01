const std = @import("std");
const flake = @import("flake");

/// Get a random worker ID between 0 and max_worker_id
fn getRandomWorkerId() !i64 {
    var prng = std.rand.DefaultPrng.init(@intCast(std.time.timestamp()));
    const random = prng.random().int(i64);
    return @mod(@as(i64, random), flake.Config.max_worker_id + 1);
}

/// Default generator instance
var default_gen: ?flake.Generator = null;
var default_gen_mutex: std.Thread.Mutex = .{};

/// Initialize the default generator with a random worker ID
pub fn initDefaultGen() !void {
    default_gen_mutex.lock();
    defer default_gen_mutex.unlock();

    if (default_gen == null) {
        const worker_id = try getRandomWorkerId();
        default_gen = try flake.Generator.init(worker_id, 0);
    }
}

/// Get the default generator instance
pub fn getDefault() !*flake.Generator {
    if (default_gen == null) {
        try initDefaultGen();
    }
    return &default_gen.?;
}
