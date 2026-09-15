const std = @import("std");
const process = std.process;
const mem = std.mem;
const heap = std.heap;
const fmt = std.fmt;
const Io = std.Io;

const interpereter = @import("interpereter.zig");

pub fn main(init: process.Init) !void {
    const io = init.io;
    var gpa = heap.DebugAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("TEST FAIL");
    }

    var memory_size: u32 = 4096;
    var width: u8 = 1;

    var args = init.minimal.args.iterate();
    _ = args.skip();
    while (args.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "-w")) {
            if (std.mem.endsWith(u8, arg, "2")) { // 16 bit memory
                width = 2;
                continue;
            } else if (std.mem.endsWith(u8, arg, "4")) { // 32 bit memory
                width = 3;
                continue;
            } else if (std.mem.endsWith(u8, arg, "8")) { // 64 bit memory
                width = 8;
                continue;
            } else { // unkown / 8 bit memory
                width = 1;
                continue;
            }
        } else if (std.mem.startsWith(u8, arg, "-m")) {
            const memory_size_string = arg[2..];
            memory_size = try fmt.parseInt(u32, memory_size_string, 10);
        }
    }

    //var memory: interpereter.Memory()
}

pub fn buildInstructionArray(allocator: mem.Allocator, io: Io) []interpereter.Instruction {
    // read instruction pipe and build instructions from there
}
