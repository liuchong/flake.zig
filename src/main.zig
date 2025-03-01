const std = @import("std");
const flake = @import("flake");
const default_gen = @import("default_gen");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get default generator
    const gen = try default_gen.getDefault();

    // Generate a new ID
    const id = try gen.nextId();
    const str = try flake.idToString(id, allocator);
    defer allocator.free(str);

    // Print the ID
    std.debug.print("Generated ID: {s}\n", .{str});
}
