pub fn Source(comptime TData: type) type {
    return struct {
        const Self = @This();

        pub const Data = TData;
        pub const Event = StructAsTaggedUnion(Data);

        ping: *zimq.Socket,
        noti: *zimq.Socket,

        message: zimq.Message,
        buffer: std.ArrayListUnmanaged(u8) = .empty,

        current: Data,

        pub const InitError = zimq.Socket.InitError || zimq.Socket.BindError;
        pub const SendError = zimq.Socket.SendError || std.mem.Allocator.Error || mzg.PackError(std.ArrayListUnmanaged(u8).Writer);
        pub const PingError = SendError || zimq.Socket.RecvError;

        pub const Endpoints = struct {
            ping: [:0]const u8,
            noti: [:0]const u8,
        };
        pub fn init(
            context: *zimq.Context,
            endpoints: Endpoints,
            inital_data: Data,
        ) InitError!Self {
            const result: Self = .{
                .ping = try zimq.Socket.init(context, .pull),
                .noti = try zimq.Socket.init(context, .@"pub"),
                .message = .empty(),
                .current = inital_data,
            };

            try result.ping.bind(endpoints.ping);
            try result.noti.bind(endpoints.noti);

            return result;
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            self.ping.deinit();
            self.noti.deinit();
            self.message.deinit();
            self.buffer.deinit(allocator);
        }

        pub fn processPing(
            self: *Self,
            allocator: Allocator,
        ) PingError!void {
            try consumeAll(self.ping);
            try self.sendPing(allocator);
        }

        pub fn setCurrent(
            self: *Self,
            current: Data,
            allocator: std.mem.Allocator,
        ) SendError!void {
            self.current = current;
            try self.sendPing(allocator);
        }

        pub fn setField(
            self: *Self,
            field: Event,
            allocator: Allocator,
        ) SendError!void {
            const current = switch (@typeInfo(Data)) {
                .optional => if (self.current) |*current| current else return,
                else => &self.current,
            };
            switch (field) {
                inline else => |value, tag| {
                    @field(current, @tagName(tag)) = value;
                },
            }

            self.buffer.clearRetainingCapacity();

            const writer = self.buffer.writer(allocator);
            try writer.writeAll("noti");
            try mzg.pack(field, writer);

            try self.noti.sendSlice(self.buffer.items, .{});
        }

        inline fn sendPing(self: *Self, allocator: Allocator) SendError!void {
            self.buffer.clearRetainingCapacity();

            const writer = self.buffer.writer(allocator);
            try writer.writeAll("ping");
            try mzg.pack(self.current, writer);

            try self.noti.sendSlice(self.buffer.items, .{});
        }
    };
}

test Source {
    const t = std.testing;
    const context: *zimq.Context = try .init();
    defer context.deinit();

    var poller: *zimq.Poller = try .init();
    defer poller.deinit();

    const Data = struct { a: u8, @"1": u8, @"2": u8 };
    var source: Source(?Data) = try .init(
        context,
        .{ .ping = "inproc://#1/ping", .noti = "inproc://#1/noti" },
        null,
    );
    defer source.deinit(t.allocator);
    const Event = @TypeOf(source).Event;

    const noti: *zimq.Socket = try .init(context, .sub);
    defer noti.deinit();
    try noti.set(.subscribe, "");
    try noti.connect("inproc://#1/noti");

    const ping: *zimq.Socket = try .init(context, .push);
    defer ping.deinit();
    try ping.connect("inproc://#1/ping");
    try ping.sendSlice("", .{});

    try poller.add(source.ping, null, .in);

    var events: [4]zimq.Poller.Event = undefined;
    const len = try poller.wait_all(&events, -1);
    try t.expectEqual(1, len);
    try t.expectEqual(source.ping, events[0].socket);
    try source.processPing(t.allocator);

    var message: zimq.Message = .empty();
    defer message.deinit();

    _ = try noti.recvMsg(&message, .{});
    try t.expectEqualStrings("ping\xc0", message.slice());
    try t.expect(!message.more());

    {
        // Since currently the data is null, no event will be sent
        try source.setField(.{ .@"1" = 1 }, t.allocator);

        try t.expectError(
            error.WouldBlock,
            noti.recvMsg(&message, .noblock),
        );
    }

    {
        try source.setCurrent(
            .{ .a = 3, .@"1" = 1, .@"2" = 2 },
            t.allocator,
        );

        const received = try noti.recvMsg(&message, .noblock);
        try t.expectEqual(8, received);
        try t.expectEqualStrings("ping\x93\x03\x01\x02", message.slice());
    }

    {
        try source.setField(.{ .@"2" = 1 }, t.allocator);

        const received = try noti.recvMsg(&message, .noblock);
        try t.expectEqual(7, received);
        try t.expectEqualStrings("noti\x92\x02\x01", message.slice());
        var event: Event = undefined;
        _ = try mzg.unpack(message.slice()[4..], &event);
        try t.expectEqual(Event{ .@"2" = 1 }, event);
        try t.expect(!message.more());
    }
}

const std = @import("std");
const Allocator = std.mem.Allocator;

const zimq = @import("zimq");
const mzg = @import("mzg");
const zincom = @import("root.zig");

const consumeAll = zincom.consumeAll;
const StructAsTaggedUnion = zincom.StructAsTaggedUnion;
