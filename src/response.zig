pub const Response = union(enum) {
    pub const Join = enum { success, duplicate };
    pub const Ping = enum { success, absence };
    pub const Down = enum { success, absence };

    join: Join,
    ping: Ping,
    down: Down,

    pub const Error = mzg.UnpackError || error{HeaderInvalid};
    pub fn parse(buffer: []const u8) Error!Response {
        if (startsWith(u8, buffer, "join")) {
            var result: Response = .{ .join = undefined };
            _ = try mzg.unpack(buffer[4..], &result.join);
            return result;
        }
        if (startsWith(u8, buffer, "ping")) {
            var result: Response = .{ .ping = undefined };
            _ = try mzg.unpack(buffer[4..], &result.ping);
            return result;
        }
        if (startsWith(u8, buffer, "down")) {
            var result: Response = .{ .down = undefined };
            _ = try mzg.unpack(buffer[4..], &result.down);
            return result;
        }

        return Error.HeaderInvalid;
    }
};

test Response {
    const t = std.testing;

    try t.expectEqual(Response{ .join = .success }, Response.parse("join\x00"));
    try t.expectEqual(Response{ .join = .duplicate }, Response.parse("join\x01"));
    try t.expectEqual(Response{ .ping = .success }, Response.parse("ping\x00"));
    try t.expectEqual(Response{ .ping = .absence }, Response.parse("ping\x01"));
    try t.expectEqual(Response{ .down = .success }, Response.parse("down\x00"));
    try t.expectEqual(Response{ .down = .absence }, Response.parse("down\x01"));
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const startsWith = std.mem.startsWith;

const mzg = @import("mzg");
const unpackArray = mzg.adapter.unpackArray;
const unpackMap = mzg.adapter.unpackMap;
