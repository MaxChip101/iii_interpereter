const std = @import("std");
const mem = std.mem;
const heap = std.heap;
const Io = std.Io;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var gpa = heap.DebugAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("TEST FAIL");
    }

    const args = try std.process

}
