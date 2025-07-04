/// Get all message parts from the socket
pub fn consumeAll(socket: *zimq.Socket) zimq.Socket.RecvError!void {
    const static = struct {
        threadlocal var buffer: ?zimq.Message = null;
    };
    if (static.buffer == null) {
        static.buffer = .empty();
    }

    while (true) {
        _ = socket.recvMsg(
            &static.buffer.?,
            .{},
        ) catch |err| return @errorCast(err);
        if (!static.buffer.?.more()) {
            break;
        }
    }
}

test consumeAll {
    var context: *zimq.Context = try .init();
    defer context.deinit();

    var push: *zimq.Socket = try .init(context, .push);
    defer push.deinit();

    var pull: *zimq.Socket = try .init(context, .pull);
    defer pull.deinit();

    try push.bind("inproc://#1");
    try pull.connect("inproc://#1");

    try push.sendConstSlice("", .more);
    try push.sendConstSlice("", .{});

    try consumeAll(pull);
}

const std = @import("std");
const t = std.testing;
const zimq = @import("zimq");
const mzg = @import("mzg");
