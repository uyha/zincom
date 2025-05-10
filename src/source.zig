pub fn Source(comptime T: type) type {
    return struct {
        const Self = @This();

        pub const Data = T;
        pub const Field = Changes(Data);

        pub const Noti = union(enum) {
            whole: Data,
            part: Field,
        };

        ping: *zimq.Socket,
        noti: *zimq.Socket,

        message: zimq.Message,
        buffer: std.ArrayListUnmanaged(u8) = .empty,

        /// Do not modify `current` directly, only do so via `setField` or
        /// `setCurrent` so that synchronization info will be emitted.
        current: Data,

        pub const InitError = zimq.Socket.InitError || zimq.Socket.BindError;
        pub const SendError = zimq.Socket.SendError || std.mem.Allocator.Error || mzg.PackError(std.ArrayListUnmanaged(u8).Writer);
        pub const PingError = SendError || zimq.Socket.RecvError;

        pub const Endpoints = struct {
            ping: [:0]const u8,
            noti: [:0]const u8,
        };
        pub fn init(
            context: *zimq.Context,
            endpoints: Endpoints,
            inital_data: Data,
        ) InitError!Self {
            const result: Self = .{
                .ping = try zimq.Socket.init(context, .pull),
                .noti = try zimq.Socket.init(context, .@"pub"),
                .message = .empty(),
                .current = inital_data,
            };

            try result.ping.bind(endpoints.ping);
            try result.noti.bind(endpoints.noti);

            return result;
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            self.ping.deinit();
            self.noti.deinit();
            self.message.deinit();
            self.buffer.deinit(allocator);
        }

        pub fn processPing(
            self: *Self,
            allocator: Allocator,
        ) PingError!void {
            try consumeAll(self.ping);
            try self.sendPing(allocator);
        }

        pub fn setCurrent(
            self: *Self,
            allocator: std.mem.Allocator,
            current: Data,
        ) SendError!void {
            self.current = current;
            try self.sendPing(allocator);
        }

        pub fn setField(
            self: *Self,
            allocator: Allocator,
            field: Field,
        ) SendError!void {
            const current = switch (@typeInfo(Data)) {
                .optional => if (self.current) |*current| current else return,
                else => &self.current,
            };
            switch (field) {
                inline else => |value, tag| {
                    @field(current, @tagName(tag)) = value;
                },
            }

            self.buffer.clearRetainingCapacity();

            const writer = self.buffer.writer(allocator);
            try zic.pack(Noti{ .part = field }, writer);

            try self.noti.sendSlice(self.buffer.items, .{});
        }

        inline fn sendPing(self: *Self, allocator: Allocator) SendError!void {
            self.buffer.clearRetainingCapacity();

            const writer = self.buffer.writer(allocator);
            try zic.pack(Noti{ .whole = self.current }, writer);

            try self.noti.sendSlice(self.buffer.items, .{});
        }
    };
}

fn Changes(T: type) type {
    const info = switch (@typeInfo(T)) {
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
const Allocator = std.mem.Allocator;

const zimq = @import("zimq");
const mzg = @import("mzg");
const zic = @import("root.zig");

const consumeAll = zic.consumeAll;
