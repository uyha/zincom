pub fn Sink(comptime TData: type) type {
    return struct {
        const Self = @This();

        const Source = zincom.Source(TData);

        pub const Data = Source.Data;
        pub const Event = Source.Event;

        ping: *zimq.Socket,
        noti: *zimq.Socket,

        message: zimq.Message,

        current: AsOptional(TData) = null,

        pub const InitError = zimq.Socket.InitError || zimq.Socket.ConnectError || zimq.Socket.SetError;
        pub const ProcessError = zimq.Socket.RecvMsgError || std.mem.Allocator.Error || mzg.UnpackError || error{ PartMissing, HeaderInvalid };

        pub const Endpoints = struct {
            ping: [:0]const u8,
            noti: [:0]const u8,
        };
        pub fn init(context: *zimq.Context, endpoints: Endpoints) InitError!Self {
            const result: Self = .{
                .ping = try .init(context, .push),
                .noti = try .init(context, .sub),
                .message = .empty(),
            };

            try result.noti.set(.subscribe, "ping");
            try result.noti.set(.subscribe, "noti");

            try result.ping.connect(endpoints.ping);
            try result.noti.connect(endpoints.noti);

            return result;
        }

        pub fn deinit(self: *Self) void {
            self.ping.deinit();
            self.noti.deinit();
            self.message.deinit();
        }

        pub fn sendPing(self: *Self) zimq.Socket.SendError!void {
            try self.ping.sendConstSlice("", .noblock);
        }

        pub fn process(self: *Self) ProcessError!void {
            _ = try self.noti.recvMsg(&self.message, .noblock);

            const content = self.message.slice();

            if (std.mem.startsWith(u8, content, "ping")) {
                try self.processPing(content[4..]);
                return;
            }

            if (std.mem.startsWith(u8, content, "noti")) {
                try self.processNoti(content[4..]);
                return;
            }

            return ProcessError.HeaderInvalid;
        }

        fn processPing(self: *Self, slice: []const u8) ProcessError!void {
            _ = try mzg.unpack(slice, &self.current);
        }

        fn processNoti(self: *Self, slice: []const u8) ProcessError!void {
            var event: Event = undefined;
            if (self.current) |*current| {
                const total = slice.len;
                var consumed: usize = 0;

                while (consumed < total) {
                    consumed += try mzg.unpack(
                        slice[consumed..],
                        &event,
                    );

                    switch (event) {
                        inline else => |value, tag| {
                            @field(current, @tagName(tag)) = value;
                        },
                    }
                }
            }
        }
    };
}

test Sink {
    const t = std.testing;

    const context: *zimq.Context = try .init();
    defer context.deinit();

    var poller: *zimq.Poller = try .init();
    defer poller.deinit();

    const Data = struct { a: u8, @"1": u8, @"2": u8 };
    const init_data: Data = .{ .a = 1, .@"1" = 1, .@"2" = 1 };
    var source: zincom.Source(?Data) = try .init(
        context,
        .{ .ping = "inproc://#1/ping", .noti = "inproc://#1/noti" },
        init_data,
    );
    defer source.deinit(t.allocator);

    var sink: Sink(Data) = try .init(context, .{
        .ping = "inproc://#1/ping",
        .noti = "inproc://#1/noti",
    });
    defer sink.deinit();

    try poller.add(sink.noti, null, .in);
    try poller.add(source.ping, null, .in);

    var event: zimq.Poller.Event = undefined;

    var timer = try std.time.Timer.start();
    while (sink.current == null) {
        try sink.sendPing();

        poller.wait(&event, 100) catch if (timer.read() > 2 * std.time.ns_per_s) {
            try t.expect(false);
        } else {
            continue;
        };

        if (event.socket) |socket| {
            if (socket == source.ping) {
                try source.processPing(t.allocator);
            }

            if (socket == sink.noti) {
                try sink.process();
            }
        }
    }

    try t.expectEqual(init_data, sink.current);

    try source.setField(.{ .a = 3 }, t.allocator);

    _ = try sink.process();
    try t.expectEqual(source.current, sink.current);
}

const std = @import("std");
const zimq = @import("zimq");
const mzg = @import("mzg");
const zincom = @import("root.zig");

const consumeAll = zincom.consumeAll;
const StructAsTaggedUnion = zincom.StructAsTaggedUnion;
const AsOptional = zincom.AsOptional;

const Header = zincom.Header;
