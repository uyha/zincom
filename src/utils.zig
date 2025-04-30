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

pub fn StructAsTaggedUnion(Data: type) type {
    const info = switch (@typeInfo(Data)) {
        .optional => |info| @typeInfo(info.child).@"struct",
        else => |info| info.@"struct",
    };
    const tag_fields: [info.fields.len]std.builtin.Type.EnumField = blk: {
        var result: [info.fields.len]std.builtin.Type.EnumField = undefined;

        for (info.fields, 0..) |field, i| {
            result[i].name = field.name;
            result[i].value = i;
        }

        break :blk result;
    };
    const tag: std.builtin.Type.Enum = .{
        .tag_type = std.math.IntFittingRange(0, info.fields.len),
        .fields = &tag_fields,
        .decls = info.decls,
        .is_exhaustive = true,
    };

    const event_fields: [info.fields.len]std.builtin.Type.UnionField = blk: {
        var result: [info.fields.len]std.builtin.Type.UnionField = undefined;

        for (info.fields, 0..) |field, i| {
            result[i].name = field.name;
            result[i].type = field.type;
            result[i].alignment = field.alignment;
        }

        break :blk result;
    };
    const event: std.builtin.Type.Union = .{
        .layout = .auto,
        .tag_type = @Type(.{ .@"enum" = tag }),
        .fields = &event_fields,
        .decls = info.decls,
    };
    return @Type(.{ .@"union" = event });
}

const std = @import("std");
const t = std.testing;
const zimq = @import("zimq");
const mzg = @import("mzg");
