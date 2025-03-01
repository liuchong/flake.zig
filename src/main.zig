const std = @import("std");
const flake = @import("flake");
const default_gen = @import("default_gen.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Using custom generator
    var gen = try flake.Generator.init(1, 0);
    const id = gen.nextId();
    std.debug.print("Custom generator ID: {}\n", .{id});

    const str = try flake.idToString(id, allocator);
    defer allocator.free(str);
    std.debug.print("As string: {s}\n", .{str});

    const decoded_id = try flake.idFromString(str, allocator);
    std.debug.print("Decoded back: {}\n", .{decoded_id});

    // Using default generator (based on machine's IP)
    const default_id = try default_gen.getDefault();
    std.debug.print("\nDefault generator ID: {}\n", .{default_id});

    const default_str = try flake.idToString(default_id, allocator);
    defer allocator.free(default_str);
    std.debug.print("As string: {s}\n", .{default_str});
}
