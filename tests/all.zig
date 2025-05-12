comptime {
    const std = @import("std");
    const t = std.testing;

    t.refAllDecls(@import("Head.zig"));
    t.refAllDecls(@import("source_sink.zig"));
}
