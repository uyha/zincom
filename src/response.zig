pub const Response = union(enum) {
    pub const Join = enum { success, duplicate };
    pub const Ping = enum { success, absence };
    pub const Down = enum { success, absence };
    pub const Query = StringArrayHashMapUnmanaged([]const u8);

    join: Join,
    ping: Ping,
    down: Down,
    query: Query,

    pub fn deinit(self: *Response, allocator: Allocator) void {
        switch (self.*) {
            .query => |*query| query.deinit(allocator),
            else => {},
        }
    }

    pub const Error = mzg.UnpackError || error{HeaderInvalid};
    pub fn parse(allocator: Allocator, buffer: []const u8) Error!Response {
        var header: []const u8 = undefined;
        const consumed = try mzg.unpack(buffer, &header);

        if (eql(u8, header, "join")) {
            var result: Response = .{ .join = undefined };
            _ = try mzg.unpack(buffer[consumed..], &result.join);
            return result;
        }
        if (eql(u8, header, "ping")) {
            var result: Response = .{ .ping = undefined };
            _ = try mzg.unpack(buffer[consumed..], &result.ping);
            return result;
        }
        if (eql(u8, header, "down")) {
            var result: Response = .{ .down = undefined };
            _ = try mzg.unpack(buffer[consumed..], &result.down);
            return result;
        }
        if (eql(u8, header, "query")) {
            var result: Response = .{ .query = .empty };
            _ = try mzg.unpack(
                buffer[consumed..],
                unpackMap(allocator, &result.query, .@"error"),
            );
            return result;
        }

        return Error.HeaderInvalid;
    }
};

test Response {
    const t = std.testing;
    const allocator = t.allocator;

    try t.expectEqual(
        Response{ .join = .success },
        try Response.parse(t.allocator, "\xA4join\x00"),
    );
    try t.expectEqual(
        Response{ .join = .duplicate },
        try Response.parse(t.allocator, "\xA4join\x01"),
    );
    try t.expectEqual(
        Response{ .ping = .success },
        try Response.parse(t.allocator, "\xA4ping\x00"),
    );
    try t.expectEqual(
        Response{ .ping = .absence },
        try Response.parse(t.allocator, "\xA4ping\x01"),
    );
    try t.expectEqual(
        Response{ .down = .success },
        try Response.parse(t.allocator, "\xA4down\x00"),
    );
    try t.expectEqual(
        Response{ .down = .absence },
        try Response.parse(t.allocator, "\xA4down\x01"),
    );

    {
        var expected = Response{
            .query = try .init(allocator, &.{"te"}, &.{"te"}),
        };
        defer expected.deinit(allocator);

        var actual = try Response.parse(allocator, "\xA5query\x81\xA2te\xA2te");
        defer actual.deinit(allocator);

        for (expected.query.keys()) |key| {
            try t.expect(actual.query.contains(key));

            try t.expectEqualStrings(
                expected.query.get(key).?,
                actual.query.get(key).?,
            );
        }
    }
}

const std = @import("std");
const StringArrayHashMapUnmanaged = std.StringArrayHashMapUnmanaged;
const Allocator = std.mem.Allocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const eql = std.mem.eql;

const mzg = @import("mzg");
const unpackArray = mzg.adapter.unpackArray;
const unpackMap = mzg.adapter.unpackMap;
