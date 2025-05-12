const utils = @import("utils.zig");

const std = @import("std");
const Allocator = std.mem.Allocator;

const mzg = @import("mzg");

const pack_map = .{
    .{ std.ArrayListUnmanaged([]const u8), mzg.adapter.packArray },
    .{ std.ArrayListUnmanaged(u8), mzg.adapter.packArray },
    .{ std.StringArrayHashMapUnmanaged([]const u8), mzg.adapter.packMap },
    .{ std.StaticStringMap([]const u8), mzg.adapter.packMap },
};
pub fn pack(
    value: anytype,
    writer: anytype,
) mzg.PackError(@TypeOf(writer))!void {
    return mzg.packAdapted(value, pack_map, writer);
}

const unpack_map = .{
    .{ std.ArrayListUnmanaged([]const u8), mzg.adapter.unpackArray },
    .{ std.ArrayListUnmanaged(u8), mzg.adapter.unpackArray },
    .{ std.StringArrayHashMapUnmanaged([]const u8), mzg.adapter.unpackMap },
    .{ std.StaticStringMap([]const u8), mzg.adapter.unpackStaticStringMap },
};
pub fn unpack(
    buffer: []const u8,
    out: anytype,
) mzg.UnpackError!usize {
    return mzg.unpackAdapted(unpack_map, buffer, out);
}
pub fn unpackAllocate(
    allocator: Allocator,
    buffer: []const u8,
    out: anytype,
) mzg.UnpackAllocateError!usize {
    return mzg.unpackAdaptedAllocate(allocator, unpack_map, buffer, out);
}

pub const consumeAll = utils.consumeAll;

pub const Source = @import("Source.zig");
pub const Sink = @import("Sink.zig");

pub const Head = @import("Head.zig");
pub const Nerve = @import("Nerve.zig");
pub const Watch = @import("Watch.zig");

comptime {
    const t = @import("std").testing;

    t.refAllDecls(Source);
    t.refAllDecls(Sink);
    t.refAllDecls(Head);
    t.refAllDecls(Nerve);
}
