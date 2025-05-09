pub const Join = enum { success, duplicate };
pub const Pulse = enum { success, absence };
pub const Down = enum { success, absence };
pub const Query = union(enum) {
    endpoints: StringArrayHashMapUnmanaged([]const u8),
    absence: void,

    pub fn deinit(self: *Query, allocator: Allocator) void {
        switch (self.*) {
            .endpoints => |*value| value.deinit(allocator),
            else => {},
        }
    }
};

pub const Resp = union(enum) {
    join: Join,
    pulse: Pulse,
    down: Down,
    query: Query,

    pub fn deinit(self: *Resp, allocator: Allocator) void {
        switch (self.*) {
            .query => |*query| query.deinit(allocator),
            else => {},
        }
    }
};

test Resp {
    const t = std.testing;
    const allocator = t.allocator;

    inline for (.{
        .{ "\x92\x00\x00", Resp{ .join = .success } },
        .{ "\x92\x00\x01", Resp{ .join = .duplicate } },
        .{ "\x92\x01\x00", Resp{ .pulse = .success } },
        .{ "\x92\x01\x01", Resp{ .pulse = .absence } },
        .{ "\x92\x02\x00", Resp{ .down = .success } },
        .{ "\x92\x02\x01", Resp{ .down = .absence } },
        .{ "\x92\x03\x92\x01\xC0", Resp{ .query = .absence } },
    }) |row| {
        const raw, const expected = row;

        var actual: Resp = undefined;
        try t.expectEqual(raw.len, try zic.unpackAllocate(allocator, raw, &actual));
        try t.expectEqual(expected, actual);
    }

    {
        var actual: Resp = undefined;
        try t.expectEqual(11, try zic.unpackAllocate(
            allocator,
            "\x92\x03\x92\x00\x81\xA2te\xA2te",
            &actual,
        ));
        defer actual.deinit(allocator);

        try t.expectEqualStrings("te", actual.query.endpoints.get("te").?);
    }
}

const std = @import("std");
const StringArrayHashMapUnmanaged = std.StringArrayHashMapUnmanaged;
const Allocator = std.mem.Allocator;

const zic = @import("root.zig");
