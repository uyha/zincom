const Self = @This();

head: *zimq.Socket,
buffer: ArrayListUnmanaged(u8) = .empty,

pub const InitError = zimq.Socket.InitError || zimq.Socket.ConnectError;
pub fn init(context: *zimq.Context, prefix: []const u8) InitError!Self {
    const result: Self = .{
        .head = try .init(context, .req),
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

pub fn sendPing(self: *Self, name: []const u8, allocator: Allocator) SendError!void {
    self.buffer.clearRetainingCapacity();

    const writer = self.buffer.writer(allocator);
    try writer.writeAll("ping");
    try mzg.pack(name, writer);

    try self.head.sendSlice(self.buffer.items, .{});
}

pub fn sendInfo(
    self: *Self,
    name: []const u8,
    ping_interval: u64,
    endpoints: StaticStringMap([]const u8),
    allocator: Allocator,
) SendError!void {
    self.buffer.clearRetainingCapacity();

    const writer = self.buffer.writer(allocator);
    try writer.writeAll("info");
    try mzg.pack(
        .{ name, ping_interval, packMap(&endpoints) },
        writer,
    );

    try self.head.sendSlice(self.buffer.items, .{});
}

pub fn sendDown(self: *Self, name: []const u8, allocator: Allocator) SendError!void {
    self.buffer.clearRetainingCapacity();

    const writer = self.buffer.writer(allocator);
    try writer.writeAll("down");
    try mzg.pack(name, writer);

    try self.head.sendSlice(self.buffer.items, .{});
}

pub const HeadError = zimq.Socket.RecvError;
pub fn processHead(self: *Self) HeadError!void {
    try consumeAll(self.head);
}

test sendInfo {
    const t = std.testing;

    var context: *zimq.Context = try .init();
    defer context.deinit();

    var head: *zimq.Socket = try .init(context, .rep);
    defer head.deinit();

    try head.bind("inproc://#1/head");

    var nerve: Self = try .init(context, "inproc://#1");
    defer nerve.deinit(t.allocator);

    try nerve.sendInfo(
        "led",
        2 * ns_per_s,
        .initComptime(&.{.{ "led", "inproc://#2" }}),
        t.allocator,
    );

    var message: zimq.Message = .empty();
    defer message.deinit();

    _ = try head.recvMsg(&message, .{});
    try t.expectEqualStrings(
        "info\x93\xA3led\xCE\x77\x35\x94\x00\x81\xA3led\xABinproc://#2",
        message.slice(),
    );
    try t.expect(!message.more());

    try head.sendConstSlice("", .{});
    try nerve.processHead();
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

    try nerve.sendPing("led", t.allocator);

    _ = try head.recvMsg(&message, .{});
    try t.expectEqualStrings("ping\xA3led", message.slice());
    try t.expect(!message.more());

    try head.sendConstSlice("", .{});
    try nerve.processHead();
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

    try nerve.sendDown("led", t.allocator);

    _ = try head.recvMsg(&message, .{});
    try t.expectEqualStrings("down\xA3led", message.slice());
    try t.expect(!message.more());

    try head.sendConstSlice("", .{});
    try nerve.processHead();
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
