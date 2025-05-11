const Source = @This();

ping: *zimq.Socket,
noti: *zimq.Socket,

message: zimq.Message,
buffer: std.ArrayListUnmanaged(u8) = .empty,

pub const SendError = zimq.Socket.SendError || std.mem.Allocator.Error || mzg.PackError(std.ArrayListUnmanaged(u8).Writer);
pub const PingError = SendError || zimq.Socket.RecvError;

pub const Endpoints = struct {
    ping: [:0]const u8,
    noti: [:0]const u8,
};
pub const InitError = zimq.Socket.InitError || zimq.Socket.BindError;
pub fn init(
    context: *zimq.Context,
    endpoints: Endpoints,
) InitError!Source {
    const result: Source = .{
        .ping = try zimq.Socket.init(context, .pull),
        .noti = try zimq.Socket.init(context, .@"pub"),
        .message = .empty(),
    };

    try result.ping.bind(endpoints.ping);
    try result.noti.bind(endpoints.noti);

    return result;
}

pub fn deinit(self: *Source, allocator: std.mem.Allocator) void {
    self.ping.deinit();
    self.noti.deinit();
    self.message.deinit();
    self.buffer.deinit(allocator);
}

pub fn broadcastWhole(
    self: *Source,
    allocator: Allocator,
    whole: anytype,
) SendError!void {
    self.buffer.clearRetainingCapacity();

    const writer = self.buffer.writer(allocator);
    try zic.pack(
        Noti(@TypeOf(whole)){ .whole = whole },
        writer,
    );

    try self.noti.sendSlice(self.buffer.items, .{});
}

pub fn broadcastPart(
    self: *Source,
    allocator: std.mem.Allocator,
    whole: anytype,
    part: Tag(Part(@TypeOf(whole))),
) SendError!void {
    const CurrentPart = @FieldType(Noti(@TypeOf(whole)), "part");
    self.buffer.clearRetainingCapacity();

    const writer = self.buffer.writer(allocator);
    switch (part) {
        inline else => |tag| try zic.pack(
            Noti(@TypeOf(whole)){
                .part = @unionInit(
                    CurrentPart,
                    @tagName(tag),
                    @field(whole, @tagName(tag)),
                ),
            },
            writer,
        ),
    }

    try self.noti.sendSlice(self.buffer.items, .{});
}

pub fn processPing(
    self: *Source,
    allocator: Allocator,
    current: anytype,
) PingError!void {
    try consumeAll(self.ping);
    try self.broadcastWhole(allocator, current);
}

fn Part(T: type) type {
    const info = @typeInfo(T).@"struct";

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

pub fn Noti(T: type) type {
    return union(enum) {
        whole: T,
        part: Part(T),
    };
}

test Source {
    const t = std.testing;
    const allocator = t.allocator;

    var context: *zimq.Context = try .init();
    defer context.deinit();

    var source: Source = try .init(context, .{
        .ping = "inproc://#1/ping",
        .noti = "inproc://#1/noti",
    });
    defer source.deinit(allocator);

    var sink: *zimq.Socket = try .init(context, .sub);
    defer sink.deinit();

    try sink.set(.subscribe, "");
    try sink.connect("inproc://#1/noti");

    var poller: *zimq.Poller = try .init();
    defer poller.deinit();

    try poller.add(sink, null, .in);

    var event: zimq.Poller.Event = undefined;

    const Data = struct { a: u8, b: u16, c: u32 };
    var actual: Noti(Data) = undefined;

    var message: zimq.Message = .empty();
    defer message.deinit();

    {
        const expected: Data = .{ .a = 10, .b = 20, .c = 30 };

        while (true) {
            if (poller.wait(&event, 1)) {
                break;
            } else |_| {
                try source.broadcastWhole(allocator, expected);
            }
        }

        _ = try sink.recvMsg(&message, .{});
        try t.expectEqualStrings("\x92\x00\x93\x0A\x14\x1E", message.slice());

        _ = try zic.unpack(message.slice(), &actual);
        try t.expectEqual(expected, actual.whole);
    }

    {
        const expected: Data = .{ .a = 10, .b = 20, .c = 30 };

        try source.broadcastPart(allocator, expected, .a);
        _ = try sink.recvMsg(&message, .{});
        try t.expectEqualStrings("\x92\x01\x92\x00\x0A", message.slice());

        _ = try zic.unpack(message.slice(), &actual);
        try t.expectEqual(Part(Data){ .a = 10 }, actual.part);
    }
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const Tag = std.meta.Tag;

const zimq = @import("zimq");
const mzg = @import("mzg");
const zic = @import("root.zig");

const consumeAll = zic.consumeAll;
