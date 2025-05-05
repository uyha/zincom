const Info = @This();

name: []const u8,
ping_interval: u64,
endpoints: Endpoints,

pub fn deinit(self: *Info, allocator: Allocator) void {
    self.endpoints.deinit(allocator);
}

pub const Unpacker = struct {
    out: *Info,
    allocator: Allocator,

    pub fn init(out: *Info, allocator: Allocator) Unpacker {
        return .{ .out = out, .allocator = allocator };
    }

    pub fn mzgUnpack(
        self: *const Unpacker,
        buffer: []const u8,
    ) mzg.UnpackError!usize {
        var consumed: usize = 0;

        var size: usize = undefined;
        consumed += try mzg.unpackArray(buffer[consumed..], &size);

        if (size != 3) {
            return mzg.UnpackError.TypeIncompatible;
        }

        consumed += try mzg.unpack(buffer[consumed..], &self.out.name);
        consumed += try mzg.unpack(buffer[consumed..], &self.out.ping_interval);

        self.out.endpoints = .empty;

        consumed += try mzg.unpack(
            buffer[consumed..],
            unpackMap(&self.out.endpoints, .@"error", self.allocator),
        );

        return consumed;
    }
};

pub fn mzgUnpacker(self: *Info, allocator: Allocator) Unpacker {
    return .init(self, allocator);
}

test Info {
    const t = std.testing;

    const content = "\x93\xA3led\xCE\x77\x35\x94\x00\x81\xA3led\xABinproc://#2";
    var info: Info = undefined;
    defer info.deinit(t.allocator);

    try t.expectEqual(
        content.len,
        try mzg.unpack(content, info.mzgUnpacker(t.allocator)),
    );
    try t.expectEqualStrings("led", info.name);
    try t.expectEqual(2 * std.time.ns_per_s, info.ping_interval);
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const Endpoints = std.StringArrayHashMapUnmanaged([]const u8);

const mzg = @import("mzg");
const unpackArray = mzg.adapter.unpackArray;
const unpackMap = mzg.adapter.unpackMap;
