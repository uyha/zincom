const Head = @This();

head: *zimq.Socket,
noti: *zimq.Socket,
ping: *zimq.Socket,

members: StringArrayHashMapUnmanaged(Member) = .empty,

buffer: ArrayListUnmanaged(u8) = .empty,
message: zimq.Message,

pub const InitError = zimq.Socket.InitError || zimq.Socket.BindError;

pub const Endpoints = struct {
    head: [:0]const u8,
    noti: [:0]const u8,
    ping: [:0]const u8,
};
pub fn init(context: *zimq.Context, endpoint: Endpoints) InitError!Head {
    const result: Head = .{
        .head = try .init(context, .rep),
        .noti = try .init(context, .@"pub"),
        .ping = try .init(context, .pull),
        .message = .empty(),
    };

    try result.head.bind(endpoint.head);
    try result.noti.bind(endpoint.noti);
    try result.ping.bind(endpoint.ping);

    return result;
}

pub fn deinit(self: *Head, allocator: Allocator) void {
    self.head.deinit();
    self.noti.deinit();
    self.ping.deinit();

    for (self.members.values()) |*value| {
        value.deinit(allocator);
    }
    self.members.deinit(allocator);

    self.buffer.deinit(allocator);
    self.message.deinit();
}

pub const ProcessError = zimq.Socket.RecvMsgError || zimq.Socket.SendError || mzg.UnpackError || Allocator.Error || BroadCastError || error{Unsupported};
pub fn processHead(self: *Head, allocator: Allocator) ProcessError!void {
    _ = try self.head.recvMsg(&self.message, .{});

    var req: Req = undefined;
    _ = try zic.unpackAllocate(allocator, self.message.slice(), &req);
    defer req.deinit(allocator);

    const resp = try switch (req) {
        .join => |join| self.processJoin(allocator, join),
        .pulse => |pulse| self.processPulse(pulse),
        .down => |down| self.processDown(allocator, down),
        .query => |query| self.processQuery(query),
    };

    self.buffer.clearRetainingCapacity();
    const writer = self.buffer.writer(allocator);
    try zic.pack(resp, writer);

    try self.head.sendSlice(self.buffer.items, .{});
}

fn processJoin(
    self: *Head,
    allocator: Allocator,
    join: Req.Join,
) ProcessError!Resp {
    if (self.members.contains(join.name)) {
        return Resp{ .join = .duplicate };
    }

    var member: Member = try .fromJoin(allocator, join, try .now());
    errdefer member.deinit(allocator);

    try self.members.put(allocator, member.name, member);
    try self.broadcastJoin(allocator, member.name);

    return Resp{ .join = .success };
}

fn processPulse(
    self: *Head,
    name: []const u8,
) ProcessError!Resp {
    if (self.members.getEntry(name)) |entry| {
        entry.value_ptr.last_pulse = try .now();
        return Resp{ .pulse = .success };
    }

    return Resp{ .pulse = .absence };
}

fn processDown(
    self: *Head,
    allocator: Allocator,
    name: []const u8,
) ProcessError!Resp {
    var entry = self.members.fetchSwapRemove(name);
    if (entry) |*kv| {
        try self.broadcastDown(allocator, kv.value.name);
        kv.value.deinit(allocator);
        return Resp{ .down = .success };
    }

    return Resp{ .down = .absence };
}

fn processQuery(
    self: *Head,
    name: []const u8,
) ProcessError!Resp {
    if (self.members.get(name)) |entry| {
        return Resp{
            .query = .{ .endpoints = entry.endpoints },
        };
    }

    return Resp{ .query = .absence };
}
pub const CheckError = BroadCastError || error{Unsupported};
pub fn checkMembers(self: *Head, allocator: Allocator) CheckError!void {
    const now: Instant = try .now();

    var i: usize = 0;
    while (i < self.members.count()) {
        var member = self.members.entries.get(i).value;
        if (now.since(member.last_pulse) <= member.interval) {
            i += 1;
            continue;
        }

        try self.broadcastDown(allocator, member.name);
        member.deinit(allocator);
        self.members.swapRemoveAt(i);
    }
}

pub const BroadCastError = zimq.Socket.SendError || mzg.PackError(ArrayListUnmanaged(u8).Writer);
pub fn broadcastMembers(self: *Head, allocator: Allocator) BroadCastError!void {
    self.buffer.clearRetainingCapacity();

    const writer = self.buffer.writer(allocator);
    try zic.pack(Noti{ .members = .initBuffer(self.members.keys()) }, writer);

    try self.noti.sendSlice(self.buffer.items, .{});
}

fn broadcastJoin(
    self: *Head,
    allocator: Allocator,
    name: []const u8,
) BroadCastError!void {
    self.buffer.clearRetainingCapacity();

    const writer = self.buffer.writer(allocator);
    try zic.pack(Noti{ .join = name }, writer);

    try self.noti.sendSlice(self.buffer.items, .{});
}
fn broadcastDown(
    self: *Head,
    allocator: Allocator,
    name: []const u8,
) BroadCastError!void {
    self.buffer.clearRetainingCapacity();

    const writer = self.buffer.writer(allocator);
    try zic.pack(Noti{ .down = name }, writer);

    try self.noti.sendSlice(self.buffer.items, .{});
}

pub fn consumePing(self: *Head) zimq.Socket.RecvError!void {
    try consumeAll(self.ping);
}

const Member = struct {
    name: []const u8,
    interval: u64,
    last_pulse: Instant,
    endpoints: StaticStringMap([]const u8),
    backing: ArrayListUnmanaged(u8),

    fn fromJoin(
        allocator: Allocator,
        join: Req.Join,
        last_pulse: Instant,
    ) Allocator.Error!Member {
        var result: Member = .{
            .name = undefined,
            .interval = join.interval,
            .last_pulse = last_pulse,
            .endpoints = undefined,
            .backing = .empty,
        };

        try result.backing.appendSlice(allocator, join.name);
        result.name = result.backing.items[0..];

        var kvs = try allocator.alloc(
            struct { []const u8, []const u8 },
            join.endpoints.kvs.len,
        );
        defer allocator.free(kvs);
        for (join.endpoints.keys(), join.endpoints.values(), 0..) |key, value, i| {
            kvs[i][0] = blk: {
                const old_len = result.backing.items.len;
                try result.backing.appendSlice(allocator, key);

                break :blk result.backing.items[old_len..];
            };
            kvs[i][1] = blk: {
                const old_len = result.backing.items.len;
                try result.backing.appendSlice(allocator, value);

                break :blk result.backing.items[old_len..];
            };
        }
        result.endpoints = try .init(kvs, allocator);

        return result;
    }

    fn deinit(self: *Member, allocator: Allocator) void {
        self.endpoints.deinit(allocator);
        self.backing.deinit(allocator);
    }
};

pub const Req = union(enum) {
    pub const Join = struct {
        name: []const u8,
        interval: u64,
        endpoints: StaticStringMap([]const u8),

        pub fn deinit(self: *Join, allocator: Allocator) void {
            self.endpoints.deinit(allocator);
        }
    };

    join: Join,
    pulse: []const u8,
    down: []const u8,
    query: []const u8,

    pub fn deinit(self: *Req, allocator: Allocator) void {
        switch (self.*) {
            .join => |*value| value.deinit(allocator),
            else => {},
        }
    }
};

pub const Resp = union(enum) {
    pub const Query = union(enum) {
        endpoints: StaticStringMap([]const u8),
        absence: void,

        pub fn deinit(self: *Query, allocator: Allocator) void {
            switch (self.*) {
                .endpoints => |*value| value.deinit(allocator),
                else => {},
            }
        }
    };

    join: enum { success, duplicate },
    pulse: enum { success, absence },
    down: enum { success, absence },
    query: Query,

    pub fn deinit(self: *Resp, allocator: Allocator) void {
        switch (self.*) {
            .query => |*query| query.deinit(allocator),
            else => {},
        }
    }
};

pub const Noti = union(enum) {
    members: ArrayListUnmanaged([]const u8),
    join: []const u8,
    down: []const u8,

    pub fn deinit(self: *Noti, allocator: Allocator) void {
        switch (self.*) {
            .members => |*value| value.deinit(allocator),
            .join, .down => {},
        }
    }
};

const std = @import("std");
const StringArrayHashMapUnmanaged = std.StringArrayHashMapUnmanaged;
const StaticStringMap = std.StaticStringMap;
const Allocator = std.mem.Allocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const eql = std.mem.eql;
const ns_per_s = std.time.ns_per_s;
const ns_per_ms = std.time.ns_per_ms;
const Instant = std.time.Instant;

const zimq = @import("zimq");

const mzg = @import("mzg");
const adapter = mzg.adapter;

const zic = @import("root.zig");
const consumeAll = zic.consumeAll;
