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

        pub fn init(context: *zimq.Context, prefix: []const u8) InitError!Self {
            const result: Self = .{
                .ping = try zimq.Socket.init(context, .push),
                .noti = try zimq.Socket.init(context, .sub),
                .message = .empty(),
            };

            try result.noti.set(.subscribe, "ping");
            try result.noti.set(.subscribe, "noti");

            var buffer: [1024]u8 = undefined;

            try result.ping.connect(std.fmt.bufPrintZ(
                &buffer,
                "{s}/ping",
                .{prefix},
            ) catch @panic("buffer too small"));
            try result.noti.connect(std.fmt.bufPrintZ(
                &buffer,
                "{s}/noti",
                .{prefix},
            ) catch @panic("buffer too small"));

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

            const header = self.message.slice().?;

            if (std.mem.eql(u8, "ping", header)) {
                try self.processPing();
                return;
            }

            if (std.mem.eql(u8, "noti", header)) {
                try self.processNoti();
                return;
            }

            return ProcessError.HeaderInvalid;
        }

        fn processPing(self: *Self) ProcessError!void {
            if (!self.message.more()) {
                return ProcessError.PartMissing;
            }

            _ = try self.noti.recvMsg(&self.message, .noblock);
            _ = try mzg.unpack(self.message.slice().?, &self.current);
        }

        fn processNoti(self: *Self) ProcessError!void {
            if (!self.message.more()) {
                return ProcessError.PartMissing;
            }

            var event: Event = undefined;
            if (self.current) |*current| {
                const received = try self.noti.recvMsg(&self.message, .noblock);
                var consumed: usize = 0;

                while (consumed < received) {
                    consumed += try mzg.unpack(
                        self.message.slice().?[consumed..],
                        &event,
                    );

                    switch (event) {
                        inline else => |value, tag| {
                            @field(current, @tagName(tag)) = value;
                        },
                    }
                }

                if (self.message.more()) {
                    return consumeAll(self.noti);
                }
            } else {
                return consumeAll(self.noti);
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

    const prefix = "inproc://#1";

    const Data = struct { a: u8, @"1": u8, @"2": u8 };
    const init_data: Data = .{ .a = 1, .@"1" = 1, .@"2" = 1 };
    var source: zincom.Source(?Data) = try .init(context, prefix, init_data);
    defer source.deinit(t.allocator);

    var sink: Sink(Data) = try .init(context, prefix);
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
