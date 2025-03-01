const std = @import("std");

/// Number of bits allocated for worker ID
pub const worker_id_bits: u64 = 10;
/// Maximum worker ID value (10 bits: 0-1023)
pub const max_worker_id: i64 = -1 ^ (-1 << worker_id_bits);
/// Number of bits allocated for sequence number
pub const sequence_bits: u64 = 13;
/// Bit shift for worker ID in the final ID
pub const worker_id_shift: u64 = sequence_bits;
/// Bit shift for timestamp in the final ID
pub const timestamp_left_shift: u64 = sequence_bits + worker_id_bits;
/// Mask for extracting sequence number
pub const sequence_mask: i64 = -1 ^ (-1 << sequence_bits);

/// FlakeID is a 64-bit unique identifier
pub const FlakeID = u64;

/// Generator struct for creating unique Flake IDs
/// Each instance is tied to a specific worker ID and custom epoch
pub const Generator = struct {
    /// Mutex for thread-safe ID generation
    mutex: std.Thread.Mutex = .{},
    /// Sequence counter for IDs generated in the same millisecond
    seq: i64 = -1,
    /// Last timestamp used for ID generation
    ts: i64 = -1,
    /// Custom epoch in milliseconds
    fepoch: i64,
    /// The ID of this generator instance (0-1023)
    worker_id: i64,

    /// Initialize a new Generator with the given worker ID and epoch
    /// worker_id must be between 0 and 1023
    /// epoch must be a past timestamp in milliseconds
    pub fn init(worker_id: i64, fepoch: i64) !Generator {
        const now = getTsInfo()[0];

        if (worker_id < 0 or worker_id > max_worker_id) {
            return error.InvalidWorkerId;
        }

        if (now < fepoch) {
            return error.InvalidEpoch;
        }

        const epoch = if (fepoch <= 0)
            @as(i64, 1234567891011) // 2009-02-13T23:31:31.011Z
        else
            fepoch;

        return Generator{
            .fepoch = epoch,
            .worker_id = worker_id,
        };
    }

    /// Generate a new unique ID
    /// Thread-safe and handles clock drift
    pub fn nextId(self: *Generator) FlakeID {
        self.mutex.lock();
        defer self.mutex.unlock();

        const ts_info = getTsInfo();
        var ts = ts_info[0];
        const rem = ts_info[1];
        const last_ts = self.ts;
        var seq = self.seq;

        if (ts == last_ts) {
            seq = (seq + 1) & sequence_mask;
            if (seq == 0) {
                while (ts <= last_ts) {
                    std.time.sleep(@as(u64, @intCast(rem)));
                    const new_ts_info = getTsInfo();
                    ts = new_ts_info[0];
                }
            }
        } else {
            seq = 0;
        }

        self.ts = ts;
        self.seq = seq;

        return @as(FlakeID, @intCast((ts - self.fepoch) << timestamp_left_shift |
            (self.worker_id << worker_id_shift) |
            seq));
    }

    /// Generate multiple unique IDs at once
    /// Returns a byte array containing n IDs, each 8 bytes long
    pub fn genMulti(self: *Generator, n: u32, allocator: std.mem.Allocator) ![]u8 {
        var buf = try allocator.alloc(u8, n * 8);
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            const id = self.nextId();
            const off = i * 8;
            buf[off + 0] = @as(u8, @truncate(id >> 56));
            buf[off + 1] = @as(u8, @truncate(id >> 48));
            buf[off + 2] = @as(u8, @truncate(id >> 40));
            buf[off + 3] = @as(u8, @truncate(id >> 32));
            buf[off + 4] = @as(u8, @truncate(id >> 24));
            buf[off + 5] = @as(u8, @truncate(id >> 16));
            buf[off + 6] = @as(u8, @truncate(id >> 8));
            buf[off + 7] = @as(u8, @truncate(id));
        }
        return buf;
    }
};

/// Convert a Flake ID to its byte representation
pub fn idToBytes(id: FlakeID, allocator: std.mem.Allocator) ![]u8 {
    var buf = try allocator.alloc(u8, 8);
    buf[0] = @as(u8, @truncate(id >> 56));
    buf[1] = @as(u8, @truncate(id >> 48));
    buf[2] = @as(u8, @truncate(id >> 40));
    buf[3] = @as(u8, @truncate(id >> 32));
    buf[4] = @as(u8, @truncate(id >> 24));
    buf[5] = @as(u8, @truncate(id >> 16));
    buf[6] = @as(u8, @truncate(id >> 8));
    buf[7] = @as(u8, @truncate(id));
    return buf;
}

/// Convert a Flake ID to its base64 string representation
pub fn idToString(id: FlakeID, allocator: std.mem.Allocator) ![]u8 {
    const bytes = try idToBytes(id, allocator);
    defer allocator.free(bytes);
    const encoded_len = std.base64.url_safe.Encoder.calcSize(bytes.len);
    const dest = try allocator.alloc(u8, encoded_len);
    _ = std.base64.url_safe.Encoder.encode(dest, bytes);
    return dest;
}

/// Convert a base64 string back to a Flake ID
pub fn idFromString(str: []const u8, allocator: std.mem.Allocator) !FlakeID {
    const decoded_len = try std.base64.url_safe.Decoder.calcSizeForSlice(str);
    const decoded = try allocator.alloc(u8, decoded_len);
    defer allocator.free(decoded);
    _ = try std.base64.url_safe.Decoder.decode(decoded, str);

    if (decoded.len != 8) return error.InvalidLength;

    return @as(FlakeID, @intCast((@as(u64, decoded[0]) << 56) |
        (@as(u64, decoded[1]) << 48) |
        (@as(u64, decoded[2]) << 40) |
        (@as(u64, decoded[3]) << 32) |
        (@as(u64, decoded[4]) << 24) |
        (@as(u64, decoded[5]) << 16) |
        (@as(u64, decoded[6]) << 8) |
        @as(u64, decoded[7])));
}

/// Get current timestamp information
/// Returns [timestamp_ms, remainder_ns]
fn getTsInfo() [2]i64 {
    const nano = std.time.nanoTimestamp();
    const div: i64 = 1_000_000;
    return .{
        @as(i64, @intCast(@divTrunc(nano, div))),
        div - @as(i64, @intCast(@mod(nano, div))),
    };
}
