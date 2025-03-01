# Flake.zig

A Zig implementation of Twitter's Snowflake ID generator, providing unique, time-based 64-bit IDs.

## Features

- 64-bit unique ID generation
- Time-based ordering
- Configurable worker ID
- Custom epoch support
- Thread-safe default generator
- Base64 string representation
- Bulk ID generation support

## Installation

Add as a dependency in your `build.zig`:

```zig
const flake = b.addModule("flake", .{
    .source_file = .{ .path = "path/to/flake.zig" },
});
exe.addModule("flake", flake);
```

## Usage

### Basic Usage

```zig
const std = @import("std");
const flake = @import("flake");

pub fn main() !void {
    // Initialize a generator with worker ID 1
    var gen = try flake.Generator.init(1, 0);
    
    // Generate a unique ID
    const id = gen.nextId();
    
    // Convert ID to string
    const str = try flake.idToString(id, allocator);
    defer allocator.free(str);
    
    std.debug.print("Generated ID: {d}\n", .{id});
    std.debug.print("String representation: {s}\n", .{str});
}
```

### Using Default Generator

```zig
const default_gen = @import("default_gen");

// Get an ID using the default generator
const id = try default_gen.getDefault();
```

### Bulk Generation

```zig
// Generate multiple IDs at once
const n: u32 = 100;
const buf = try gen.genMulti(n, allocator);
defer allocator.free(buf);
```

## ID Structure

Each generated ID is a 64-bit integer with the following structure:

- 41 bits: timestamp (milliseconds since epoch)
- 10 bits: worker ID (0-1023)
- 13 bits: sequence number (0-8191)

This allows for:
- 69 years of unique timestamps
- 1024 different worker IDs
- 8192 IDs per millisecond per worker

## API Reference

### Generator

```zig
pub const Generator = struct {
    pub fn init(worker_id: i64, epoch: i64) !Generator
    pub fn nextId(self: *Generator) FlakeID
    pub fn genMulti(self: *Generator, n: u32, allocator: std.mem.Allocator) ![]u8
}
```

### Utility Functions

```zig
pub fn idToString(id: FlakeID, allocator: std.mem.Allocator) ![]u8
pub fn idFromString(str: []const u8, allocator: std.mem.Allocator) !FlakeID
pub fn idToBytes(id: FlakeID, allocator: std.mem.Allocator) ![]u8
```

## Error Handling

The library can return the following errors:
- `error.InvalidWorkerId`: Worker ID is out of valid range (0-1023)
- `error.InvalidEpoch`: Epoch is set to a future timestamp
- `error.InvalidLength`: Invalid string length for ID parsing
- `error.InvalidBase64`: Invalid base64 encoding in string

## Testing

Run the test suite:

```bash
zig build test
```

## License

Licensed under either of these:

* Apache License Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE))
* MIT License ([LICENSE-MIT](LICENSE-MIT))

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request. 