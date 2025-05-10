pub fn Sink(comptime T: type) type {
    return struct {
        const Self = @This();

        const Source = zic.Source(T);

        pub const Data = Source.Data;
        pub const Noti = Source.Noti;

        ping: *zimq.Socket,
        noti: *zimq.Socket,

        message: zimq.Message,

        connected: bool = false,
        data: Data = if (@typeInfo(Data) == .optional) null else undefined,

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

            try result.noti.set(.subscribe, "\x92\x00");
            try result.noti.set(.subscribe, "\x92\x01");

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

            var noti: Noti = undefined;
            _ = try zic.unpack(self.message.slice(), &noti);

            self.connected = true;

            switch (noti) {
                .whole => |whole| {
                    self.data = whole;
                },
                .part => |part| if (self.connected) switch (@typeInfo(Data)) {
                    .optional => if (self.data) |*data| switch (part) {
                        inline else => |value, tag| {
                            @field(data, @tagName(tag)) = value;
                        },
                    },
                    .@"struct" => switch (part) {
                        inline else => |value, tag| {
                            @field(self.data, @tagName(tag)) = value;
                        },
                    },
                    else => @compileError(@typeName(T) ++ " is not supported"),
                },
            }
        }
    };
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const hasFn = std.meta.hasFn;

const zimq = @import("zimq");
const mzg = @import("mzg");
const zic = @import("root.zig");

const consumeAll = zic.consumeAll;
const StructAsTaggedUnion = zic.StructAsTaggedUnion;
const AsOptional = zic.AsOptional;
