const std = @import("std");
const zgl = @import("ziogameloop");

pub fn main() !void {
    var loop = zgl.GameLoop.init(.{ .tick_rate = 60, .max_catchup = 5 });
    
    // Simulate 5 frames
    var frame: u32 = 0;
    var ns: u64 = 0;
    while (frame < 5) : (frame += 1) {
        ns += std.time.ns_per_s / 60;
        const result = loop.tick(ns);
        std.debug.print("Frame {d}: updates={}, alpha={d:.2}\n", .{ frame, result.updates, result.alpha });
    }
}
