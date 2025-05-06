const Self = @This();

head: *zimq.Socket,
buffer: ArrayListUnmanaged(u8) = .empty,
message: zimq.Message,

pub const InitError = zimq.Socket.InitError || zimq.Socket.ConnectError;
pub fn init(context: *zimq.Context, prefix: []const u8) InitError!Self {
    const result: Self = .{
        .head = try .init(context, .req),
        .message = .empty(),
    };

    var buffer: [1024]u8 = undefined;

    try result.head.connect(std.fmt.bufPrintZ(
        &buffer,
        "{s}/head",
        .{prefix},
    ) catch @panic("buffer too small"));

    return result;
}

pub fn deinit(self: *Self, allocator: Allocator) void {
    self.head.deinit();
    self.buffer.deinit(allocator);
}

pub const SendError = zimq.Socket.SendError || mzg.PackError(ArrayListUnmanaged(u8).Writer);

pub fn sendPing(self: *Self, allocator: Allocator, name: []const u8) SendError!void {
    self.buffer.clearRetainingCapacity();

    const writer = self.buffer.writer(allocator);
    try writer.writeAll("ping");
    try mzg.pack(name, writer);

    try self.head.sendSlice(self.buffer.items, .{});
}

pub fn sendJoin(
    self: *Self,
    allocator: Allocator,
    name: []const u8,
    ping_interval: u64,
    endpoints: StaticStringMap([]const u8),
) SendError!void {
    self.buffer.clearRetainingCapacity();

    const writer = self.buffer.writer(allocator);
    try writer.writeAll("join");
    try mzg.pack(
        .{ name, ping_interval, packMap(&endpoints) },
        writer,
    );

    try self.head.sendSlice(self.buffer.items, .{});
}

pub fn sendDown(self: *Self, allocator: Allocator, name: []const u8) SendError!void {
    self.buffer.clearRetainingCapacity();

    const writer = self.buffer.writer(allocator);
    try writer.writeAll("down");
    try mzg.pack(name, writer);

    try self.head.sendSlice(self.buffer.items, .{});
}

pub const ResponseError = zimq.Socket.RecvMsgError || Response.Error;
pub fn getHeadReponse(self: *Self) ResponseError!Response {
    _ = try self.head.recvMsg(&self.message, .{});

    return Response.parse(self.message.slice());
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

    var nerve: Self = try .init(context, "inproc://#1");
    defer nerve.deinit(t.allocator);

    try nerve.sendJoin(
        t.allocator,
        "led",
        2 * ns_per_s,
        .initComptime(&.{.{ "led", "inproc://#2" }}),
    );

    _ = try head.recvMsg(&message, .{});
    try t.expectEqualStrings(
        "join\x93\xA3led\xCE\x77\x35\x94\x00\x81\xA3led\xABinproc://#2",
        message.slice(),
    );
    try t.expect(!message.more());

    try head.sendConstSlice("join\x00", .{});
    const response = try nerve.getHeadReponse();
    try t.expectEqual(Response{ .join = .success }, response);
}

test sendPing {
    const t = std.testing;

    var context: *zimq.Context = try .init();
    defer context.deinit();

    var head: *zimq.Socket = try .init(context, .rep);
    defer head.deinit();

    try head.bind("inproc://#1/head");

    var nerve: Self = try .init(context, "inproc://#1");
    defer nerve.deinit(t.allocator);

    var message: zimq.Message = .empty();
    defer message.deinit();

    try nerve.sendPing(t.allocator, "led");

    _ = try head.recvMsg(&message, .{});
    try t.expectEqualStrings("ping\xA3led", message.slice());
    try t.expect(!message.more());

    try head.sendConstSlice("ping\x00", .{});
    const response = try nerve.getHeadReponse();
    try t.expectEqual(Response{ .ping = .success }, response);
}

test sendDown {
    const t = std.testing;

    var context: *zimq.Context = try .init();
    defer context.deinit();

    var head: *zimq.Socket = try .init(context, .rep);
    defer head.deinit();

    try head.bind("inproc://#1/head");

    var nerve: Self = try .init(context, "inproc://#1");
    defer nerve.deinit(t.allocator);

    var message: zimq.Message = .empty();
    defer message.deinit();

    try nerve.sendDown(t.allocator, "led");

    _ = try head.recvMsg(&message, .{});
    try t.expectEqualStrings("down\xA3led", message.slice());
    try t.expect(!message.more());

    try head.sendConstSlice("down\x00", .{});
    const response = try nerve.getHeadReponse();
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
const Response = zic.Response;
