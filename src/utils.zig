threadlocal var dummy_message: ?zimq.Message = null;

/// Get all message parts from the socket
pub fn consumeAll(socket: *zimq.Socket) zimq.Socket.RecvError!void {
    if (dummy_message == null) {
        dummy_message = .empty();
    }
    while (true) {
        _ = socket.recvMsg(
            &dummy_message.?,
            .{},
        ) catch |err| return @errorCast(err);
        if (!dummy_message.?.more()) {
            break;
        }
    }
}

pub fn StructAsTaggedUnion(Data: type) type {
    const info = @typeInfo(Data).@"struct";
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
