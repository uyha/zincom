test "zeromq" {
    const context: *zimq.Context = try .init();
    defer context.deinit();

    try t.expect(false);
}

const std = @import("std");
const t = std.testing;
const zimq = @import("zimq");
