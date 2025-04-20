const zincom = @import("root.zig");

const consumeAll = zincom.consumeAll;
const StructAsTaggedUnion = zincom.StructAsTaggedUnion;

const Header = zincom.Header;

pub fn Publisher(comptime TData: type) type {
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

        pub fn init(context: *zimq.Context, prefix: []const u8, inital_data: Data) InitError!Self {
            const result: Self = .{
                .ping = try zimq.Socket.init(context, .pull),
                .noti = try zimq.Socket.init(context, .@"pub"),
                .message = .empty(),
                .current = inital_data,
            };

            var buffer: [1024]u8 = undefined;

            try result.ping.bind(std.fmt.bufPrintZ(
                &buffer,
                "{s}/ping",
                .{prefix},
            ) catch @panic("buffer too small"));
            try result.noti.bind(std.fmt.bufPrintZ(
                &buffer,
                "{s}/noti",
                .{prefix},
            ) catch @panic("buffer too small"));

            return result;
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            self.ping.deinit();
            self.noti.deinit();
            self.message.deinit();
            self.buffer.deinit(allocator);
        }

        pub fn handlePing(
            self: *Self,
            allocator: std.mem.Allocator,
        ) PingError!void {
            try consumeAll(self.ping);

            try self.sendHeader(.ping);
            try self.sendBody(self.current, allocator);
        }
        pub fn set(
            self: *Self,
            event: Event,
            allocator: std.mem.Allocator,
        ) SendError!void {
            switch (event) {
                inline else => |value, tag| {
                    @field(self.current, @tagName(tag)) = value;
                },
            }

            try self.sendHeader(.noti);
            try self.sendBody(event, allocator);
        }
        pub fn notifyLive(self: *Self) zimq.Socket.SendError!void {
            try self.sendHeader(.live);
        }
        pub fn notifyDown(self: *Self) zimq.Socket.SendError!void {
            try self.sendHeader(.down);
        }

        inline fn sendHeader(
            self: *Self,
            header: Header,
        ) zimq.Socket.SendError!void {
            try self.noti.sendConstSlice(
                @tagName(header),
                .{ .send_more = header == .noti or header == .ping },
            );
        }
        inline fn sendBody(
            self: *Self,
            body: anytype,
            allocator: std.mem.Allocator,
        ) SendError!void {
            switch (@TypeOf(body)) {
                Data, Event => {},
                else => @compileError("buggy implementation, only Data or Event can be sent"),
            }

            try self.buffer.resize(allocator, 0);
            try mzg.pack(body, self.buffer.writer(allocator));

            try self.noti.sendSlice(self.buffer.items, .{});
        }
    };
}

test Publisher {
    const context: *zimq.Context = try .init();
    defer context.deinit();

    // var poller: *zimq.Poller = try .init();
    // defer poller.deinit();
    //
    // const Data = struct { @"1": u8, @"2": u8 };
    // const Event = StructAsTaggedUnion(Data);
    // var source: Publisher(Data) = try .init(
    //     context,
    //     "inproc://#1",
    //     .{ .@"1" = 0, .@"2" = 0 },
    // );
    // defer source.deinit(t.allocator);
    //
    // const noti: *zimq.Socket = try .init(context, .sub);
    // defer noti.deinit();
    // try noti.set(.subscribe, "");
    // try noti.connect("inproc://#1/noti");
    //
    // const ping: *zimq.Socket = try .init(context, .push);
    // defer ping.deinit();
    // try ping.connect("inproc://#1/ping");
    // try ping.sendSlice("", .{});
    //
    // try poller.add(source.ping, null, .in);
    //
    // var events: [4]zimq.Poller.Event = undefined;
    // const len = try poller.wait_all(&events, -1);
    // try t.expectEqual(1, len);
    // try t.expectEqual(source.ping, events[0].socket);
    // try source.handlePing(t.allocator);
    //
    // var message: zimq.Message = .empty();
    // defer message.deinit();
    //
    // _ = try noti.recvMsg(&message, .{});
    // try t.expectEqualStrings("ping", message.slice().?);
    // try t.expect(message.more());
    //
    // _ = try noti.recvMsg(&message, .{});
    // try t.expectEqualStrings("\x92\x00\x00", message.slice().?);
    // try t.expect(!message.more());
    //
    // {
    //     try source.set(.{ .@"1" = 1 }, t.allocator);
    //
    //     _ = try noti.recvMsg(&message, .{});
    //     try t.expectEqualStrings("noti", message.slice().?);
    //     try t.expect(message.more());
    //
    //     _ = try noti.recvMsg(&message, .{});
    //     try t.expectEqualStrings("\x92\x00\x01", message.slice().?);
    //     var event: Event = undefined;
    //     _ = try mzg.unpack(message.slice().?, &event);
    //     try t.expectEqual(Event{ .@"1" = 1 }, event);
    //     try t.expect(!message.more());
    // }
    //
    // {
    //     try source.set(.{ .@"2" = 1 }, t.allocator);
    //
    //     _ = try noti.recvMsg(&message, .{});
    //     try t.expectEqualStrings("noti", message.slice().?);
    //     try t.expect(message.more());
    //
    //     _ = try noti.recvMsg(&message, .{});
    //     try t.expectEqualStrings("\x92\x01\x01", message.slice().?);
    //     var event: Event = undefined;
    //     _ = try mzg.unpack(message.slice().?, &event);
    //     try t.expectEqual(Event{ .@"2" = 1 }, event);
    //     try t.expect(!message.more());
    // }
}

const std = @import("std");
const t = std.testing;
const zimq = @import("zimq");
const mzg = @import("mzg");
