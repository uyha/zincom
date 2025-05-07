pub const Join = enum { success, duplicate };
pub const Ping = enum { success, absence };
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

    pub fn mzgPack(
        self: *const Query,
        writer: anytype,
    ) mzg.PackError(@TypeOf(writer))!void {
        switch (self.*) {
            .endpoints => |*value| {
                try mzg.packArray(2, writer);
                try mzg.pack(activeTag(self.*));
                try mzg.pack(adapter.packMap(value), writer);
            },
            else => {
                try mzg.packArray(1, writer);
                try mzg.pack(activeTag(self.*));
            },
        }
    }

    pub fn mzgUnpacker(self: *Query, allocator: Allocator) Query.MzgUnpacker {
        return .{ .allocator = allocator, .out = self };
    }
    const MzgUnpacker = struct {
        allocator: Allocator,
        out: *Query,

        pub fn mzgUnpack(
            self: *const Query.MzgUnpacker,
            buffer: []const u8,
        ) mzg.UnpackError!usize {
            var len: usize = undefined;
            var consumed = try mzg.unpackArray(buffer, &len);

            if (len != 1 and len != 2) {
                return mzg.UnpackError.TypeIncompatible;
            }

            var tag: Tag(Query) = undefined;
            consumed += try mzg.unpack(buffer[consumed..], &tag);

            switch (tag) {
                .endpoints => {
                    self.out.* = .{ .endpoints = .empty };
                    consumed += try mzg.unpack(
                        buffer[consumed..],
                        adapter.unpackMap(
                            self.allocator,
                            &self.out.endpoints,
                            .@"error",
                        ),
                    );
                },
                .absence => self.out.* = .{ .absence = {} },
            }

            return consumed;
        }
    };
};

pub const Resp = union(enum) {
    join: Join,
    ping: Ping,
    down: Down,
    query: Query,

    pub fn deinit(self: *Resp, allocator: Allocator) void {
        switch (self.*) {
            .query => |*query| query.deinit(allocator),
            else => {},
        }
    }

    pub const Error = mzg.UnpackError || error{HeaderInvalid};
    const MzgUnpacker = struct {
        allocator: Allocator,
        out: *Resp,

        pub fn mzgUnpack(self: *const MzgUnpacker, buffer: []const u8) mzg.UnpackError!usize {
            var header: []const u8 = undefined;
            var consumed = try mzg.unpack(buffer, &header);

            if (eql(u8, header, "join")) {
                self.out.* = .{ .join = undefined };
                consumed += try mzg.unpack(buffer[consumed..], &self.out.join);
                return consumed;
            }
            if (eql(u8, header, "ping")) {
                self.out.* = .{ .ping = undefined };
                consumed += try mzg.unpack(buffer[consumed..], &self.out.ping);
                return consumed;
            }
            if (eql(u8, header, "down")) {
                self.out.* = .{ .down = undefined };
                consumed += try mzg.unpack(buffer[consumed..], &self.out.down);
                return consumed;
            }
            if (eql(u8, header, "query")) {
                self.out.* = .{ .query = undefined };
                consumed += try mzg.unpack(
                    buffer[consumed..],
                    self.out.query.mzgUnpacker(self.allocator),
                );
                return consumed;
            }

            return mzg.UnpackError.TypeIncompatible;
        }
    };

    pub fn parse(
        allocator: Allocator,
        buffer: []const u8,
    ) mzg.UnpackError!Resp {
        var result: Resp = undefined;
        _ = try mzg.unpack(buffer, result.mzgUnpacker(allocator));
        return result;
    }
    pub fn mzgUnpacker(self: *Resp, allocator: Allocator) MzgUnpacker {
        return .{ .allocator = allocator, .out = self };
    }
};

test Resp {
    const t = std.testing;
    const allocator = t.allocator;

    try t.expectEqual(
        Resp{ .join = .success },
        try Resp.parse(t.allocator, "\xA4join\x00"),
    );
    try t.expectEqual(
        Resp{ .join = .duplicate },
        try Resp.parse(t.allocator, "\xA4join\x01"),
    );
    try t.expectEqual(
        Resp{ .ping = .success },
        try Resp.parse(t.allocator, "\xA4ping\x00"),
    );
    try t.expectEqual(
        Resp{ .ping = .absence },
        try Resp.parse(t.allocator, "\xA4ping\x01"),
    );
    try t.expectEqual(
        Resp{ .down = .success },
        try Resp.parse(t.allocator, "\xA4down\x00"),
    );
    try t.expectEqual(
        Resp{ .down = .absence },
        try Resp.parse(t.allocator, "\xA4down\x01"),
    );

    try t.expectEqual(
        Resp{ .query = .absence },
        try Resp.parse(t.allocator, "\xA5query\x91\x01"),
    );
    {
        var expected = Resp{
            .query = .{ .endpoints = try .init(allocator, &.{"te"}, &.{"te"}) },
        };
        defer expected.deinit(allocator);

        var actual = try Resp.parse(allocator, "\xA5query\x92\x00\x81\xA2te\xA2te");
        defer actual.deinit(allocator);

        for (expected.query.endpoints.keys()) |key| {
            try t.expect(actual.query.endpoints.contains(key));

            try t.expectEqualStrings(
                expected.query.endpoints.get(key).?,
                actual.query.endpoints.get(key).?,
            );
        }
    }
}

const std = @import("std");
const StringArrayHashMapUnmanaged = std.StringArrayHashMapUnmanaged;
const Allocator = std.mem.Allocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const eql = std.mem.eql;
const activeTag = std.meta.activeTag;
const Tag = std.meta.Tag;

const mzg = @import("mzg");
const adapter = mzg.adapter;
