const std = @import("std");

/// Compile-time constants for bit manipulation
pub const Config = struct {
    /// Number of bits allocated for worker ID
    pub const worker_id_bits: u6 = 10;
    /// Number of bits allocated for sequence number
    pub const sequence_bits: u6 = 13;
    /// Number of bits allocated for timestamp
    pub const timestamp_bits: u6 = 41;
    /// Maximum worker ID value (10 bits: 0-1023)
    pub const max_worker_id: i64 = (1 << worker_id_bits) - 1;
    /// Maximum sequence number (13 bits: 0-8191)
    pub const max_sequence: i64 = (1 << sequence_bits) - 1;
    /// Bit shift for worker ID in the final ID
    pub const worker_id_shift: u6 = sequence_bits;
    /// Bit shift for timestamp in the final ID
    pub const timestamp_left_shift: u6 = worker_id_bits + sequence_bits;
};

/// FlakeID is a 64-bit unique identifier
pub const FlakeID = u64;

/// Pre-computed base64 encoding table
const base64_table = blk: {
    @setEvalBranchQuota(1000);
    var table: [64]u8 = undefined;
    for (&table, 0..) |*c, i| {
        c.* = switch (i) {
            0...25 => 'A' + @as(u8, i),
            26...51 => 'a' + @as(u8, i - 26),
            52...61 => '0' + @as(u8, i - 52),
            62 => '-',
            63 => '_',
            else => unreachable,
        };
    }
    break :blk table;
};

/// Thread-local timestamp cache
threadlocal var last_timestamp: i64 = 0;
threadlocal var timestamp_cache: i64 = 0;

/// Generator struct for creating unique Flake IDs
pub const Generator = struct {
    /// The ID of this generator instance (0-1023)
    worker_id: i64,
    /// Custom epoch in milliseconds
    epoch: i64,
    /// Atomic sequence counter
    sequence: std.atomic.Value(i64),
    /// Pre-allocated sequence block
    sequence_block: [256]i64,
    /// Current index in sequence block
    sequence_index: std.atomic.Value(usize),
    /// Mutex for sequence block allocation
    sequence_mutex: std.Thread.Mutex,

    /// Initialize a new Generator with the given worker ID and epoch
    pub fn init(worker_id: i64, fepoch: i64) !Generator {
        if (worker_id < 0 or worker_id > Config.max_worker_id) {
            return error.InvalidWorkerId;
        }

        const current = getCurrentTimestamp();
        if (fepoch > current) {
            return error.InvalidEpoch;
        }

        const epoch = if (fepoch <= 0)
            @as(i64, 1234567891011) // 2009-02-13T23:31:31.011Z
        else
            fepoch;

        var gen = Generator{
            .worker_id = worker_id,
            .epoch = epoch,
            .sequence = std.atomic.Value(i64).init(0),
            .sequence_block = undefined,
            .sequence_index = std.atomic.Value(usize).init(256), // Force initial block allocation
            .sequence_mutex = .{},
        };

        // Initialize sequence block
        try gen.allocateSequenceBlock();
        return gen;
    }

    /// Get current timestamp with caching
    inline fn getCurrentTimestamp() i64 {
        // Always get a fresh timestamp to avoid infinite loops
        const nano = std.time.nanoTimestamp();
        const current_time = @divTrunc(nano, std.time.ns_per_ms);
        const ms = @as(i64, @intCast(current_time));

        // Only update cache if newer
        if (ms > last_timestamp) {
            timestamp_cache = ms;
            last_timestamp = ms;
            return ms; // Return the fresh timestamp
        }

        // Return the cached timestamp + 1 to ensure progress
        // This prevents infinite loops when system time doesn't change fast enough
        return last_timestamp + 1;
    }

    /// Allocate a new block of sequence numbers
    fn allocateSequenceBlock(self: *Generator) !void {
        self.sequence_mutex.lock();
        defer self.sequence_mutex.unlock();

        const base_sequence = self.sequence.load(.unordered);
        var i: usize = 0;
        while (i < 256) : (i += 1) {
            const i_i64: i64 = @intCast(i);
            self.sequence_block[i] = (base_sequence + i_i64) & Config.max_sequence;
        }
        self.sequence.store(base_sequence + 256, .unordered);
        self.sequence_index.store(0, .unordered);
    }

    /// Get next sequence number from pre-allocated block
    inline fn getNextSequence(self: *Generator) !i64 {
        const index = self.sequence_index.load(.unordered);
        if (index >= 256) {
            try self.allocateSequenceBlock();
            return self.sequence_block[0];
        }
        const seq = self.sequence_block[index];
        self.sequence_index.store(index + 1, .unordered);
        return seq;
    }

    /// Generate a new unique ID
    pub fn nextId(self: *Generator) !FlakeID {
        const timestamp = getCurrentTimestamp();
        const seq = try self.getNextSequence();

        // Compose ID using bit operations
        return @as(FlakeID, @intCast(((timestamp - self.epoch) << Config.timestamp_left_shift) |
            (self.worker_id << Config.worker_id_shift) |
            seq));
    }

    /// Generate multiple unique IDs at once
    pub fn genMulti(self: *Generator, buf: []u8) !usize {
        const n = @divFloor(buf.len, 8);
        var written: usize = 0;

        // Simple loop for generating IDs
        var i: usize = 0;
        while (i < n) : (i += 1) {
            const id = try self.nextId();
            const off = i * 8;
            comptime var k: usize = 0;
            inline while (k < 8) : (k += 1) {
                buf[off + k] = @truncate(id >> ((7 - k) * 8));
            }
            written += 8;
        }

        return written;
    }

    /// Convert ID to string using pre-computed table
    pub fn idToStringBuf(id: FlakeID, buf: []u8) !void {
        if (buf.len < 12) return error.BufferTooSmall;

        // Use standard base64 encoding for reliability
        var tmp: [8]u8 = undefined;
        comptime var i: usize = 0;
        inline while (i < 8) : (i += 1) {
            tmp[i] = @truncate(id >> ((7 - i) * 8));
        }

        // Ensure all 12 characters are valid base64
        _ = std.base64.url_safe.Encoder.encode(buf[0..12], &tmp);
    }

    /// Convert string back to ID
    pub fn idFromStringBuf(str: []const u8) !FlakeID {
        if (str.len != 12) return error.InvalidLength;

        // Use standard base64 decoding for reliability
        var decoded: [8]u8 = undefined;
        try std.base64.url_safe.Decoder.decode(&decoded, str[0..12]);

        var id: FlakeID = 0;
        for (decoded, 0..) |byte, idx| {
            const shift_amount: u6 = @intCast(8 * (7 - idx));
            id |= @as(FlakeID, byte) << shift_amount;
        }

        return id;
    }
};

/// Get base64 value for a character
inline fn base64Value(c: u8) !u6 {
    return switch (c) {
        'A'...'Z' => @intCast(c - 'A'),
        'a'...'z' => @intCast(c - 'a' + 26),
        '0'...'9' => @intCast(c - '0' + 52),
        '-' => 62,
        '_' => 63,
        else => error.InvalidBase64,
    };
}

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
    if (decoded_len != 8) return error.InvalidLength;

    const decoded = try allocator.alloc(u8, decoded_len);
    defer allocator.free(decoded);
    try std.base64.url_safe.Decoder.decode(decoded, str);

    var id: FlakeID = 0;
    id |= @as(FlakeID, decoded[0]) << 56;
    id |= @as(FlakeID, decoded[1]) << 48;
    id |= @as(FlakeID, decoded[2]) << 40;
    id |= @as(FlakeID, decoded[3]) << 32;
    id |= @as(FlakeID, decoded[4]) << 24;
    id |= @as(FlakeID, decoded[5]) << 16;
    id |= @as(FlakeID, decoded[6]) << 8;
    id |= @as(FlakeID, decoded[7]);

    return id;
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
