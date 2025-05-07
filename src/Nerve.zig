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

pub fn sendPulse(self: *Nerve, allocator: Allocator, name: []const u8) SendError!void {
    self.buffer.clearRetainingCapacity();

    const writer = self.buffer.writer(allocator);
    try mzg.pack("pulse", writer);
    try mzg.pack(name, writer);

    try self.head.sendSlice(self.buffer.items, .{});
}

pub fn sendJoin(
    self: *Nerve,
    allocator: Allocator,
    name: []const u8,
    interval: u64,
    endpoints: StaticStringMap([]const u8),
) SendError!void {
    self.buffer.clearRetainingCapacity();

    const writer = self.buffer.writer(allocator);
    try mzg.pack("join", writer);
    try mzg.pack(
        .{ name, interval, packMap(&endpoints) },
        writer,
    );

    try self.head.sendSlice(self.buffer.items, .{});
}

pub fn sendDown(self: *Nerve, allocator: Allocator, name: []const u8) SendError!void {
    self.buffer.clearRetainingCapacity();

    const writer = self.buffer.writer(allocator);
    try mzg.pack("down", writer);
    try mzg.pack(name, writer);

    try self.head.sendSlice(self.buffer.items, .{});
}

pub const ResponseError = zimq.Socket.RecvMsgError || Response.Error;
pub fn getResponse(self: *Nerve, allocator: Allocator) ResponseError!Response {
    _ = try self.head.recvMsg(&self.message, .{});

    return Response.parse(allocator, self.message.slice());
}

test sendJoin {
    const t = std.testing;

    var context: *zimq.Context = try .init();
    defer context.deinit();

    var message: zimq.Message = .empty();
    defer message.deinit();

    var head: *zimq.Socket = try .init(context, .rep);
    defer head.deinit();

    try head.bind("inproc://#1/head");

    var nerve: Nerve = try .init(context, "inproc://#1/head");
    defer nerve.deinit(t.allocator);

    try nerve.sendJoin(
        t.allocator,
        "led",
        2 * ns_per_s,
        .initComptime(&.{.{ "led", "inproc://#2" }}),
    );

    _ = try head.recvMsg(&message, .{});
    try t.expectEqualStrings(
        "\xA4join\x93\xA3led\xCE\x77\x35\x94\x00\x81\xA3led\xABinproc://#2",
        message.slice(),
    );
    try t.expect(!message.more());

    try head.sendConstSlice("\xA4join\x00", .{});
    var response = try nerve.getResponse(t.allocator);
    defer response.deinit(t.allocator);
    try t.expectEqual(Response{ .join = .success }, response);
}

test sendPulse {
    const t = std.testing;

    var context: *zimq.Context = try .init();
    defer context.deinit();

    var head: *zimq.Socket = try .init(context, .rep);
    defer head.deinit();

    try head.bind("inproc://#1/head");

    var nerve: Nerve = try .init(context, "inproc://#1/head");
    defer nerve.deinit(t.allocator);

    var message: zimq.Message = .empty();
    defer message.deinit();

    try nerve.sendPulse(t.allocator, "led");

    _ = try head.recvMsg(&message, .{});
    try t.expectEqualStrings("\xA5pulse\xA3led", message.slice());
    try t.expect(!message.more());

    try head.sendConstSlice("\xA5pulse\x00", .{});
    var response = try nerve.getResponse(t.allocator);
    defer response.deinit(t.allocator);
    try t.expectEqual(Response{ .pulse = .success }, response);
}

test sendDown {
    const t = std.testing;

    var context: *zimq.Context = try .init();
    defer context.deinit();

    var head: *zimq.Socket = try .init(context, .rep);
    defer head.deinit();

    try head.bind("inproc://#1/head");

    var nerve: Nerve = try .init(context, "inproc://#1/head");
    defer nerve.deinit(t.allocator);

    var message: zimq.Message = .empty();
    defer message.deinit();

    try nerve.sendDown(t.allocator, "led");

    _ = try head.recvMsg(&message, .{});
    try t.expectEqualStrings("\xA4down\xA3led", message.slice());
    try t.expect(!message.more());

    try head.sendConstSlice("\xA4down\x00", .{});
    var response = try nerve.getResponse(t.allocator);
    defer response.deinit(t.allocator);
    try t.expectEqual(Response{ .down = .success }, response);
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
const Response = zic.Resp;
