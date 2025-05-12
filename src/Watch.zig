const Watch = @This();

noti: *zimq.Socket,
ping: *zimq.Socket,

message: zimq.Message,

connected: bool = false,

pub const Endpoints = struct {
    noti: [:0]const u8,
    ping: [:0]const u8,
};
pub const InitError = zimq.Socket.InitError || zimq.Socket.ConnectError || zimq.Socket.SetError;
pub fn init(context: *zimq.Context, endpoints: Endpoints) InitError!Watch {
    var result: Watch = .{
        .ping = try .init(context, .push),
        .noti = try .init(context, .sub),
        .message = .empty(),
    };
    errdefer result.deinit();

    try result.noti.set(.subscribe, "\x92\x00");
    try result.noti.set(.subscribe, "\x92\x01");
    try result.noti.set(.subscribe, "\x92\x02");

    try result.noti.connect(endpoints.noti);
    try result.ping.connect(endpoints.ping);

    return result;
}

pub fn deinit(self: *Watch) void {
    self.noti.deinit();
    self.ping.deinit();
    self.message.deinit();
}

pub fn sendPing(self: *Watch) zimq.Socket.SendError!void {
    try self.ping.sendConstSlice("", .{});
}

pub const ProcessError = zimq.Socket.RecvMsgError || mzg.UnpackAllocateError;
pub fn process(self: *Watch, allocator: Allocator) ProcessError!Noti {
    _ = try self.noti.recvMsg(&self.message, .noblock);

    self.connected = true;

    var noti: Noti = undefined;
    _ = try zic.unpackAllocate(allocator, self.message.slice(), &noti);
    return noti;
}

const std = @import("std");
const Allocator = std.mem.Allocator;

const zimq = @import("zimq");
const mzg = @import("mzg");

const zic = @import("root.zig");
const Noti = zic.Head.Noti;
