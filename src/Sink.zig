const Sink = @This();

ping: *zimq.Socket,
noti: *zimq.Socket,

message: zimq.Message,

connected: bool = false,

pub const InitError = zimq.Socket.InitError || zimq.Socket.ConnectError || zimq.Socket.SetError;
pub const ProcessError = zimq.Socket.RecvMsgError || std.mem.Allocator.Error || mzg.UnpackError;

pub const Endpoints = struct {
    ping: [:0]const u8,
    noti: [:0]const u8,
};
pub fn init(context: *zimq.Context, endpoints: Endpoints) InitError!Sink {
    const result: Sink = .{
        .ping = try .init(context, .push),
        .noti = try .init(context, .sub),
        .message = .empty(),
    };

    try result.noti.set(.subscribe, "\x92\x00");
    try result.noti.set(.subscribe, "\x92\x01");
    try result.noti.set(.subscribe, "\x92\x02");

    try result.ping.connect(endpoints.ping);
    try result.noti.connect(endpoints.noti);

    return result;
}

pub fn deinit(self: *Sink) void {
    self.ping.deinit();
    self.noti.deinit();
    self.message.deinit();
}

pub fn sendPing(self: *Sink) zimq.Socket.SendError!void {
    try self.ping.sendConstSlice("", .noblock);
}

pub fn process(self: *Sink, comptime Data: type) ProcessError!Noti(Data) {
    _ = try self.noti.recvMsg(&self.message, .noblock);

    var noti: Noti(Data) = undefined;
    _ = try zic.unpack(self.message.slice(), &noti);

    self.connected = true;

    return noti;
}

const std = @import("std");
const Allocator = std.mem.Allocator;

const zimq = @import("zimq");
const mzg = @import("mzg");

const zic = @import("root.zig");
const Source = zic.Source;
const Part = Source.Part;
const Noti = Source.Noti;
