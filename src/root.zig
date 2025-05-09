const utils = @import("utils.zig");

const std = @import("std");
const Allocator = std.mem.Allocator;

const mzg = @import("mzg");

const pack_map = .{
    .{ std.ArrayListUnmanaged(u8), mzg.adapter.packArray },
    .{ std.StringArrayHashMapUnmanaged([]const u8), mzg.adapter.packMap },
};
pub fn pack(
    value: anytype,
    writer: anytype,
) mzg.PackError(@TypeOf(writer))!void {
    return mzg.packAdapted(value, pack_map, writer);
}

const unpack_map = .{
    .{ std.ArrayListUnmanaged(u8), mzg.adapter.unpackArray },
    .{ std.StringArrayHashMapUnmanaged([]const u8), mzg.adapter.unpackMap },
};
pub fn unpack(
    buffer: []const u8,
    out: anytype,
) mzg.UnpackAllocateError!usize {
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
pub const StructAsTaggedUnion = utils.StructAsTaggedUnion;
pub const AsOptional = utils.AsOptional;

const source = @import("source.zig");
pub const Source = source.Source;

const sink = @import("sink.zig");
pub const Sink = source.Sink;

const resp = @import("resp.zig");
pub const Join = resp.Join;
pub const Pulse = resp.Pulse;
pub const Down = resp.Down;
pub const Query = resp.Query;
pub const Resp = resp.Resp;

// pub const Head = @import("Head.zig");
// pub const Nerve = @import("Nerve.zig");

comptime {
    const t = @import("std").testing;

    t.refAllDecls(source);
    t.refAllDecls(sink);
    t.refAllDecls(resp);
    // t.refAllDecls(Head);
    // t.refAllDecls(Nerve);
}
