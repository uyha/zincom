comptime {
    const std = @import("std");
    const t = std.testing;

    t.refAllDecls(@import("head_nerve.zig"));
    t.refAllDecls(@import("source_sink.zig"));
}
