comptime {
    const std = @import("std");
    const t = std.testing;

    t.refAllDecls(@import("head_nerve.zig"));
}
