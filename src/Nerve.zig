const Nerve = @This();

head: *zimq.Socket,
buffer: ArrayListUnmanaged(u8) = .empty,
message: zimq.Message,

pub const InitError = zimq.Socket.InitError || zimq.Socket.ConnectError;
pub fn init(context: *zimq.Context, endpoint: [:0]const u8) InitError!Nerve {
    const result: Nerve = .{
        .head = try .init(context, .req),
        .message = .empty(),
    };

    try result.head.connect(endpoint);

    return result;
}

pub fn deinit(self: *Nerve, allocator: Allocator) void {
    self.head.deinit();
    self.buffer.deinit(allocator);
}

pub const SendError =
    zimq.Socket.SendError || mzg.PackError(ArrayListUnmanaged(u8).Writer);

pub fn sendPulse(
    self: *Nerve,
    allocator: Allocator,
    name: []const u8,
) SendError!void {
    return self.sendRequest(allocator, Req{ .pulse = name });
}

pub fn sendJoin(
    self: *Nerve,
    allocator: Allocator,
    name: []const u8,
    interval: u64,
    endpoints: StaticStringMap([]const u8),
) SendError!void {
    return self.sendRequest(allocator, Req{
        .join = .{
            .name = name,
            .interval = interval,
            .endpoints = endpoints,
        },
    });
}

pub fn sendDown(self: *Nerve, allocator: Allocator, name: []const u8) SendError!void {
    return self.sendRequest(allocator, Req{ .down = name });
}

pub fn sendQuery(self: *Nerve, allocator: Allocator, name: []const u8) SendError!void {
    return self.sendRequest(allocator, Req{ .query = name });
}

inline fn sendRequest(
    self: *Nerve,
    allocator: Allocator,
    req: Req,
) SendError!void {
    self.buffer.clearRetainingCapacity();

    const writer = self.buffer.writer(allocator);
    try zic.pack(req, writer);

    try self.head.sendSlice(self.buffer.items, .{});
}

pub const ResponseError = zimq.Socket.RecvMsgError || mzg.UnpackAllocateError;
pub fn getResponse(self: *Nerve, allocator: Allocator) ResponseError!Resp {
    _ = try self.head.recvMsg(&self.message, .{});

    var resp: Resp = undefined;
    _ = try zic.unpackAllocate(
        allocator,
        self.message.slice(),
        &resp,
    );
    return resp;
}

const std = @import("std");
const StaticStringMap = std.StaticStringMap;
const Allocator = std.mem.Allocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const ns_per_s = std.time.ns_per_s;

const zimq = @import("zimq");

const mzg = @import("mzg");
const packMap = mzg.adapter.packMap;

const zic = @import("root.zig");
const consumeAll = zic.consumeAll;
const Req = zic.Head.Req;
const Resp = zic.Head.Resp;
