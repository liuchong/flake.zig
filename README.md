# Flake ID Generator for Zig

A highly optimized, thread-safe, and distributed unique ID generator for Zig, inspired by Twitter's Snowflake.

## Features

- 64-bit unique ID generation
- Time-based ordering
- Configurable worker ID (0-1023)
- Custom epoch support
- Thread-safe implementation
- Bulk ID generation with SIMD support
- Zero-allocation string encoding/decoding
- High performance (millions of IDs per second)
- Comprehensive test suite

## Installation

Add the following to your `build.zig`:

```zig
const flake_dep = b.dependency("flake", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("flake", flake_dep.module("flake"));
```

And in your `build.zig.zon`:

```zig
.{
    .name = "your-project",
    .version = "0.1.0",
    .dependencies = .{
        .flake = .{
            .url = "https://github.com/liuchong/flake.zig/archive/v1.0.0.tar.gz",
            .hash = "...", // Replace with actual hash
        },
    },
}
```

## Usage

### Basic Usage

```zig
const flake = @import("flake");

// Initialize a generator with worker ID 1
var gen = try flake.Generator.init(1, 0);

// Generate a unique ID
const id = try gen.nextId();

// Convert ID to string
var str_buf: [12]u8 = undefined;
try flake.Generator.idToStringBuf(id, &str_buf);

// Convert string back to ID
const decoded = try flake.Generator.idFromStringBuf(&str_buf);
```

### Bulk Generation

```zig
// Generate multiple IDs at once (with SIMD support)
var buf: [1024 * 8]u8 = undefined; // Buffer for 1024 IDs
const written = try gen.genMulti(&buf);
```

## ID Structure

Each ID is a 64-bit integer composed of:

- 41 bits for timestamp (milliseconds since epoch)
- 10 bits for worker ID (0-1023)
- 13 bits for sequence number (0-8191)

This structure allows for:
- 69 years of unique timestamps
- 1024 unique worker IDs
- 8192 IDs per millisecond per worker

## Performance

Benchmark results on M1 Max:

- Single ID Generation: ~5 million ops/sec
- Bulk ID Generation: ~50 million IDs/sec
- ID to String Conversion: ~10 million ops/sec
- String to ID Conversion: ~8 million ops/sec

## API Reference

### Generator

```zig
pub const Generator = struct {
    // Initialize a new generator
    pub fn init(worker_id: i64, epoch: i64) !Generator

    // Generate a single ID
    pub fn nextId(self: *Generator) !FlakeID

    // Generate multiple IDs at once
    pub fn genMulti(self: *Generator, buf: []u8) !usize

    // Convert ID to string
    pub fn idToStringBuf(id: FlakeID, buf: []u8) !void

    // Convert string back to ID
    pub fn idFromStringBuf(str: []const u8) !FlakeID
};
```

### Error Handling

The following errors may be returned:

- `error.InvalidWorkerId`: Worker ID is outside valid range (0-1023)
- `error.InvalidEpoch`: Epoch is in the future
- `error.BufferTooSmall`: Buffer is too small for operation
- `error.InvalidLength`: String length is invalid for conversion
- `error.InvalidBase64`: String contains invalid base64 characters

## Testing

Run the test suite:

```bash
zig build test
```

Run benchmarks:

```bash
zig build bench
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under either:

- MIT License
- Apache License Version 2.0

at your option. 