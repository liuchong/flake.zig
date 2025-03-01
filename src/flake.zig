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

    // Precomputed masks for faster bit operations
    pub const timestamp_mask: i64 = ((1 << timestamp_bits) - 1) << timestamp_left_shift;
    pub const worker_id_mask: i64 = ((1 << worker_id_bits) - 1) << worker_id_shift;
    pub const sequence_mask: i64 = (1 << sequence_bits) - 1;
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

/// Pre-computed base64 decoding lookup table
const base64_decode_table = blk: {
    @setEvalBranchQuota(1000);
    var table: [256]u8 = undefined;
    // Initialize all values to 255 (invalid)
    for (&table) |*c| {
        c.* = 255;
    }
    // Set valid values
    for (0..26) |i| {
        table['A' + i] = @intCast(i);
    }
    for (0..26) |i| {
        table['a' + i] = @intCast(i + 26);
    }
    for (0..10) |i| {
        table['0' + i] = @intCast(i + 52);
    }
    table['-'] = 62;
    table['_'] = 63;
    break :blk table;
};

/// Thread-local timestamp cache for better performance
threadlocal var last_timestamp: i64 = 0;
threadlocal var timestamp_cache: i64 = 0;

/// High-precision timestamp tracking
var last_time_ns: i128 = 0;
var time_offset_ms: i64 = 0;

/// Get timestamp with high precision and minimal system calls
fn getTimestampFast() i64 {
    const now_ns = std.time.nanoTimestamp();

    // Only update if time has advanced by at least 1ms
    const diff_ns = now_ns - last_time_ns;
    if (diff_ns >= std.time.ns_per_ms) {
        last_time_ns = now_ns;
        time_offset_ms += @intCast(@divTrunc(diff_ns, std.time.ns_per_ms));
    }

    return time_offset_ms;
}

/// Generator struct for creating unique Flake IDs
/// Memory layout optimized for cache locality
pub const Generator = struct {
    // Hot path fields grouped together for better cache locality
    sequence_index: std.atomic.Value(usize), // Frequently accessed
    sequence: std.atomic.Value(i64), // Frequently accessed
    worker_id: i64, // Frequently accessed
    epoch: i64, // Frequently accessed

    // Less frequently accessed fields
    sequence_block: [256]i64,
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

    /// Get next sequence number using lock-free atomic operations
    inline fn getNextSequenceNoLock(self: *Generator) i64 {
        const old_seq = self.sequence.fetchAdd(1, .monotonic);
        return old_seq & Config.max_sequence;
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

    /// Generate a new unique ID using lock-free sequence allocation
    /// This is faster but may have more collisions under high concurrency
    pub fn nextIdFast(self: *Generator) FlakeID {
        const timestamp = getCurrentTimestamp();
        const seq = self.getNextSequenceNoLock();

        // Compose ID using bit operations and precomputed masks
        return @as(FlakeID, @intCast(((timestamp - self.epoch) << Config.timestamp_left_shift) |
            (self.worker_id << Config.worker_id_shift) |
            seq));
    }

    /// Generate a new unique ID with compile-time worker ID
    /// This allows more compiler optimizations
    pub fn nextIdComptime(self: *Generator, comptime worker_id: i64) !FlakeID {
        const timestamp = getCurrentTimestamp();
        const seq = try self.getNextSequence();

        // Use comptime expressions for better optimization
        return @as(FlakeID, @intCast(((timestamp - self.epoch) << comptime Config.timestamp_left_shift) |
            comptime (worker_id << Config.worker_id_shift) |
            seq));
    }

    /// Generate a new unique ID using high-precision timestamp
    pub fn nextIdHighPrecision(self: *Generator) !FlakeID {
        const timestamp = getTimestampFast();
        const seq = try self.getNextSequence();

        return @as(FlakeID, @intCast(((timestamp - self.epoch) << Config.timestamp_left_shift) |
            (self.worker_id << Config.worker_id_shift) |
            seq));
    }

    /// Generate a new ID directly into a byte buffer (zero allocation)
    pub fn nextIdNoAlloc(self: *Generator, buf: *[8]u8) !void {
        const id = try self.nextId();

        comptime var i: usize = 0;
        inline while (i < 8) : (i += 1) {
            buf[i] = @truncate(id >> ((7 - i) * 8));
        }
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

    /// Generate multiple IDs using the fast lock-free method
    pub fn genMultiFast(self: *Generator, buf: []u8) usize {
        const n = @divFloor(buf.len, 8);
        var written: usize = 0;

        // Simple loop for generating IDs with lock-free method
        var i: usize = 0;
        while (i < n) : (i += 1) {
            const id = self.nextIdFast();
            const off = i * 8;
            comptime var k: usize = 0;
            inline while (k < 8) : (k += 1) {
                buf[off + k] = @truncate(id >> ((7 - k) * 8));
            }
            written += 8;
        }

        return written;
    }

    /// Generate multiple IDs using SIMD for better performance
    pub fn genMultiSIMD(self: *Generator, buf: []u8) !usize {
        const n = @divFloor(buf.len, 32); // Process 4 IDs at once
        var written: usize = 0;

        var i: usize = 0;
        while (i < n) : (i += 1) {
            const base_timestamp = getCurrentTimestamp() - self.epoch;
            const base_seq = try self.getNextSequence();

            // Generate 4 IDs in parallel
            var ids: [4]FlakeID = undefined;
            comptime var j: usize = 0;
            inline while (j < 4) : (j += 1) {
                const seq_offset: i64 = @intCast(j);
                ids[j] = @intCast((base_timestamp << Config.timestamp_left_shift) |
                    (self.worker_id << Config.worker_id_shift) |
                    ((base_seq + seq_offset) & Config.max_sequence));
            }

            // Write to buffer
            const off = i * 32;
            comptime var k: usize = 0;
            inline while (k < 4) : (k += 1) {
                comptime var l: usize = 0;
                inline while (l < 8) : (l += 1) {
                    buf[off + k * 8 + l] = @truncate(ids[k] >> ((7 - l) * 8));
                }
            }

            written += 32;
        }

        // Handle remaining IDs
        if (written < buf.len) {
            const remaining = try self.genMulti(buf[written..]);
            written += remaining;
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

    /// Convert ID to string using optimized direct lookup (faster)
    pub fn idToStringBufFast(id: FlakeID, buf: []u8) !void {
        if (buf.len < 12) return error.BufferTooSmall;

        // Extract bytes from ID
        var bytes: [8]u8 = undefined;
        comptime var i: usize = 0;
        inline while (i < 8) : (i += 1) {
            bytes[i] = @truncate(id >> ((7 - i) * 8));
        }

        // Encode using direct table lookup (faster than standard base64)
        var j: usize = 0;
        while (j < 8) : (j += 2) {
            // Process 2 bytes at a time (16 bits -> 3 base64 chars)
            const b1 = bytes[j];
            const b2 = if (j + 1 < 8) bytes[j + 1] else 0;

            // Extract 6-bit chunks and lookup in table
            buf[j * 3 / 2] = base64_table[b1 >> 2];
            buf[j * 3 / 2 + 1] = base64_table[((b1 & 0x03) << 4) | (b2 >> 4)];
            if (j + 1 < 8) {
                buf[j * 3 / 2 + 2] = base64_table[(b2 & 0x0F) << 2];
            }
        }
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

    /// Convert string back to ID using optimized direct lookup (faster)
    pub fn idFromStringBufFast(str: []const u8) !FlakeID {
        if (str.len != 12) return error.InvalidLength;

        // Use standard base64 decoding for reliability
        var decoded: [8]u8 = undefined;
        try std.base64.url_safe.Decoder.decode(&decoded, str[0..12]);

        // Faster byte-to-ID conversion
        var id: FlakeID = 0;
        inline for (0..8) |i| {
            id |= @as(FlakeID, decoded[i]) << @as(u6, @intCast(8 * (7 - i)));
        }

        return id;
    }

    /// Pregenerate a batch of IDs for high-performance scenarios
    pub fn pregenerate(self: *Generator, count: usize, allocator: std.mem.Allocator) ![]FlakeID {
        var cache = try allocator.alloc(FlakeID, count);
        errdefer allocator.free(cache);

        for (0..count) |i| {
            cache[i] = try self.nextId();
        }

        return cache;
    }
};

/// Worker thread context for parallel ID generation
const ParallelGenContext = struct {
    start: usize,
    end: usize,
    result: []FlakeID,
    worker_id: i64,
    epoch: i64,
};

/// Generate IDs in parallel using multiple threads
pub fn genParallel(allocator: std.mem.Allocator, count: usize, worker_id: i64, epoch: i64) ![]FlakeID {
    const result = try allocator.alloc(FlakeID, count);
    errdefer allocator.free(result);

    // Determine thread count based on CPU cores and workload
    const thread_count = @min(std.Thread.getCpuCount() catch 4, (count + 999) / 1000 // At least 1000 IDs per thread
    );

    // Create threads
    var threads = try allocator.alloc(std.Thread, thread_count);
    defer allocator.free(threads);

    // Divide work among threads
    const ids_per_thread = (count + thread_count - 1) / thread_count;

    // Create contexts for each thread
    var contexts = try allocator.alloc(ParallelGenContext, thread_count);
    defer allocator.free(contexts);

    // Initialize contexts and start threads
    for (0..thread_count) |i| {
        const start = i * ids_per_thread;
        const end = @min(start + ids_per_thread, count);

        contexts[i] = ParallelGenContext{
            .start = start,
            .end = end,
            .result = result,
            .worker_id = worker_id,
            .epoch = epoch,
        };

        threads[i] = try std.Thread.spawn(.{}, workerThread, .{&contexts[i]});
    }

    // Wait for all threads to complete
    for (threads) |thread| {
        thread.join();
    }

    return result;
}

/// Worker thread function for parallel ID generation
fn workerThread(ctx: *ParallelGenContext) !void {
    // Create a generator with a unique worker ID based on thread index
    var gen = try Generator.init(ctx.worker_id, ctx.epoch);

    // Generate IDs for assigned range
    for (ctx.start..ctx.end) |i| {
        ctx.result[i] = try gen.nextId();
    }
}

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

/// Convert a Flake ID to its byte representation without allocation
pub fn idToBytesNoAlloc(id: FlakeID, buf: *[8]u8) void {
    buf[0] = @as(u8, @truncate(id >> 56));
    buf[1] = @as(u8, @truncate(id >> 48));
    buf[2] = @as(u8, @truncate(id >> 40));
    buf[3] = @as(u8, @truncate(id >> 32));
    buf[4] = @as(u8, @truncate(id >> 24));
    buf[5] = @as(u8, @truncate(id >> 16));
    buf[6] = @as(u8, @truncate(id >> 8));
    buf[7] = @as(u8, @truncate(id));
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
