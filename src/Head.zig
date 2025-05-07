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

    for (self.members.entries.items(.value)) |*value| {
        value.deinit(allocator);
    }
    self.members.deinit(allocator);

    self.buffer.deinit(allocator);
    self.message.deinit();
}

pub const ProcessError = zimq.Socket.RecvMsgError || zimq.Socket.SendError || mzg.UnpackError || error{ HeaderInvalid, Unsupported };
pub fn processHead(self: *Head, allocator: Allocator) ProcessError!void {
    const header, const body = try self.getRequest();

    if (eql(u8, header, "join")) {
        return self.processJoin(allocator, body);
    }
    if (eql(u8, header, "pulse")) {
        return self.processPulse(allocator, body);
    }
    if (eql(u8, header, "down")) {
        return self.processDown(allocator, body);
    }
    if (eql(u8, header, "query")) {
        return self.processQuery(allocator, body);
    }

    return ProcessError.HeaderInvalid;
}

fn processJoin(
    self: *Head,
    allocator: Allocator,
    slice: []const u8,
) ProcessError!void {
    var raw: ArrayListUnmanaged(u8) = .empty;
    errdefer raw.deinit(allocator);

    try raw.appendSlice(allocator, slice);

    var registration: Registration = undefined;
    _ = try mzg.unpack(raw.items, registration.mzgUnpacker(allocator));
    errdefer registration.deinit(allocator);

    const result: Join = result: {
        if (self.members.contains(registration.name)) {
            raw.deinit(allocator);
            registration.deinit(allocator);
            break :result Join.duplicate;
        } else {
            try self.members.put(allocator, registration.name, .{
                .name = registration.name,
                .interval = registration.interval,
                .last_pulse = try .now(),
                .endpoints = registration.endpoints,
                .raw = raw,
            });

            break :result Join.success;
        }
    };

    self.buffer.clearRetainingCapacity();
    const writer = self.buffer.writer(allocator);
    try mzg.pack("join", writer);
    try mzg.pack(result, writer);

    try self.head.sendSlice(self.buffer.items, .{});
}

fn processPulse(
    self: *Head,
    allocator: Allocator,
    slice: []const u8,
) ProcessError!void {
    var name: []const u8 = undefined;
    _ = try mzg.unpack(slice, &name);

    const result: Pulse = blk: {
        if (self.members.getEntry(name)) |entry| {
            entry.value_ptr.last_pulse = try .now();
            break :blk Pulse.success;
        } else {
            break :blk Pulse.absence;
        }
    };

    self.buffer.clearRetainingCapacity();
    const writer = self.buffer.writer(allocator);
    try mzg.pack("pulse", writer);
    try mzg.pack(result, writer);

    try self.head.sendSlice(self.buffer.items, .{});
}

fn processDown(
    self: *Head,
    allocator: Allocator,
    slice: []const u8,
) ProcessError!void {
    var name: []const u8 = undefined;
    _ = try mzg.unpack(slice, &name);

    const result: Down =
        if (self.removeByName(allocator, name)) .success else .absence;

    self.buffer.clearRetainingCapacity();
    const writer = self.buffer.writer(allocator);
    try mzg.pack("down", writer);
    try mzg.pack(result, writer);

    try self.head.sendSlice(self.buffer.items, .{});
}

fn processQuery(
    self: *Head,
    allocator: Allocator,
    slice: []const u8,
) ProcessError!void {
    var name: []const u8 = undefined;
    _ = try mzg.unpack(slice, &name);

    self.buffer.clearRetainingCapacity();
    const writer = self.buffer.writer(allocator);

    if (self.members.get(name)) |member| {
        try mzg.pack("query", writer);
        _ = member;
    }
}
pub const CheckError = error{Unsupported};
pub fn checkMembers(self: *Head, allocator: Allocator) CheckError!void {
    const now: Instant = try .now();

    var i: usize = 0;
    while (i < self.members.count()) {
        var member = self.members.entries.get(i).value;
        if (now.since(member.last_pulse) <= member.interval) {
            i += 1;
            continue;
        }
        member.deinit(allocator);
        self.members.swapRemoveAt(i);
    }
}

fn removeByName(self: *Head, allocator: Allocator, name: []const u8) bool {
    var entry = self.members.fetchSwapRemove(name);
    if (entry) |*kv| {
        kv.value.deinit(allocator);

        return true;
    }
    return false;
}

const GetRequestError = zimq.Socket.RecvMsgError || mzg.UnpackError;
/// This function returns a tuple whose 1st element is the header and the 2nd
/// element is the body
fn getRequest(self: *Head) GetRequestError!struct { []const u8, []const u8 } {
    _ = try self.head.recvMsg(&self.message, .{});

    var header: []const u8 = undefined;
    const consumed = try mzg.unpack(self.message.slice(), &header);

    return .{ header, self.message.slice()[consumed..] };
}

pub const Registration = struct {
    name: []const u8,
    interval: u64,
    endpoints: StringArrayHashMapUnmanaged([]const u8) = .empty,

    pub fn deinit(self: *Registration, allocator: Allocator) void {
        self.endpoints.deinit(allocator);
    }

    pub const Unpacker = struct {
        allocator: Allocator,
        out: *Registration,

        pub fn init(allocator: Allocator, out: *Registration) Unpacker {
            return .{ .allocator = allocator, .out = out };
        }

        pub fn mzgUnpack(self: *const Unpacker, buffer: []const u8) mzg.UnpackError!usize {
            var len: usize = undefined;
            var consumed: usize = try mzg.unpackArray(buffer, &len);

            if (len != 3) {
                return mzg.UnpackError.TypeIncompatible;
            }

            consumed += try mzg.unpack(buffer[consumed..], &self.out.name);
            consumed += try mzg.unpack(buffer[consumed..], &self.out.interval);
            self.out.endpoints = .empty;
            consumed += try mzg.unpack(
                buffer[consumed..],
                unpackMap(self.allocator, &self.out.endpoints, .@"error"),
            );

            return consumed;
        }
    };

    pub fn mzgUnpacker(self: *Registration, allocator: Allocator) Unpacker {
        return .init(allocator, self);
    }
};
pub const Member = struct {
    name: []const u8,
    interval: u64,
    last_pulse: Instant,
    endpoints: StringArrayHashMapUnmanaged([]const u8),
    raw: ArrayListUnmanaged(u8),

    pub fn deinit(self: *Member, allocator: Allocator) void {
        self.endpoints.deinit(allocator);
        self.raw.deinit(allocator);
    }
};

test processJoin {
    const t = std.testing;

    var context: *zimq.Context = try .init();
    defer context.deinit();

    var head: Head = try .init(context, .{
        .head = "inproc://#1/head",
        .noti = "inproc://#1/noti",
        .ping = "inproc://#1/ping",
    });
    defer head.deinit(t.allocator);

    var nerve: *zimq.Socket = try .init(context, .req);
    defer nerve.deinit();

    try nerve.connect("inproc://#1/head");

    var buffer: ArrayListUnmanaged(u8) = .empty;
    defer buffer.deinit(t.allocator);

    const writer = buffer.writer(t.allocator);
    try mzg.pack("join", writer);
    try mzg.pack(
        .{ "test", 1 * ns_per_s, packMap(&StringArrayHashMapUnmanaged(u8).empty) },
        writer,
    );
    try nerve.sendSlice(buffer.items, .{});

    try head.processHead(t.allocator);

    const member = head.members.get("test");
    try t.expect(member != null);
    try t.expectEqualStrings("test", member.?.name);
    try t.expectEqual(1 * ns_per_s, member.?.interval);

    var message: zimq.Message = .empty();
    _ = try nerve.recvMsg(&message, .{});
    try t.expect(!message.more());

    {
        var response = try Resp.parse(t.allocator, message.slice());
        defer response.deinit(t.allocator);
        try t.expectEqual(Resp{ .join = .success }, response);
    }

    // Joining again should fail with `duplicate` returned
    try nerve.sendSlice(buffer.items, .{});
    try head.processHead(t.allocator);

    _ = try nerve.recvMsg(&message, .{});
    try t.expect(!message.more());

    {
        var response = try Resp.parse(t.allocator, message.slice());
        defer response.deinit(t.allocator);
        try t.expectEqual(Resp{ .join = .duplicate }, response);
    }
}
test processPulse {
    const t = std.testing;

    var context: *zimq.Context = try .init();
    defer context.deinit();

    var head: Head = try .init(context, .{
        .head = "inproc://#1/head",
        .noti = "inproc://#1/noti",
        .ping = "inproc://#1/ping",
    });
    defer head.deinit(t.allocator);

    var nerve: *zimq.Socket = try .init(context, .req);
    defer nerve.deinit();

    try nerve.connect("inproc://#1/head");

    var buffer: ArrayListUnmanaged(u8) = .empty;
    defer buffer.deinit(t.allocator);

    var message: zimq.Message = .empty();
    {
        defer buffer.clearRetainingCapacity();

        const writer = buffer.writer(t.allocator);
        try mzg.pack("join", writer);
        try mzg.pack(
            .{ "test", 1 * ns_per_s, packMap(&StringArrayHashMapUnmanaged(u8).empty) },
            writer,
        );
        try nerve.sendSlice(buffer.items, .{});
        try head.processHead(t.allocator);
        _ = try nerve.recvMsg(&message, .{});
    }

    {
        defer buffer.clearRetainingCapacity();

        const writer = buffer.writer(t.allocator);
        try mzg.pack("pulse", writer);
        try mzg.pack("test", writer);
        try nerve.sendSlice(buffer.items, .{});
        try head.processHead(t.allocator);

        _ = try nerve.recvMsg(&message, .{});
        try t.expect(!message.more());
        var response = try Resp.parse(t.allocator, message.slice());
        defer response.deinit(t.allocator);
        try t.expectEqual(Resp{ .pulse = .success }, response);
    }

    {
        defer buffer.clearRetainingCapacity();

        const writer = buffer.writer(t.allocator);
        try mzg.pack("pulse", writer);
        try mzg.pack("asdf", writer);
        try nerve.sendSlice(buffer.items, .{});
        try head.processHead(t.allocator);

        _ = try nerve.recvMsg(&message, .{});
        try t.expect(!message.more());
        var response = try Resp.parse(t.allocator, message.slice());
        defer response.deinit(t.allocator);
        try t.expectEqual(Resp{ .pulse = .absence }, response);
    }
}
test processDown {
    const t = std.testing;

    var context: *zimq.Context = try .init();
    defer context.deinit();

    var head: Head = try .init(context, .{
        .head = "inproc://#1/head",
        .noti = "inproc://#1/noti",
        .ping = "inproc://#1/ping",
    });
    defer head.deinit(t.allocator);

    var nerve: *zimq.Socket = try .init(context, .req);
    defer nerve.deinit();

    try nerve.connect("inproc://#1/head");

    var buffer: ArrayListUnmanaged(u8) = .empty;
    defer buffer.deinit(t.allocator);

    var message: zimq.Message = .empty();
    {
        defer buffer.clearRetainingCapacity();

        const writer = buffer.writer(t.allocator);
        try mzg.pack("join", writer);
        try mzg.pack(
            .{ "test", 1 * ns_per_s, packMap(&StringArrayHashMapUnmanaged(u8).empty) },
            writer,
        );
        try nerve.sendSlice(buffer.items, .{});
        try head.processHead(t.allocator);
        _ = try nerve.recvMsg(&message, .{});
    }

    {
        defer buffer.clearRetainingCapacity();

        const writer = buffer.writer(t.allocator);
        try mzg.pack("down", writer);
        try mzg.pack("test", writer);
        try nerve.sendSlice(buffer.items, .{});
        try head.processHead(t.allocator);

        _ = try nerve.recvMsg(&message, .{});
        try t.expect(!message.more());
        var response = try Resp.parse(t.allocator, message.slice());
        defer response.deinit(t.allocator);
        try t.expectEqual(Resp{ .down = .success }, response);
    }

    {
        defer buffer.clearRetainingCapacity();

        const writer = buffer.writer(t.allocator);
        try mzg.pack("pulse", writer);
        try mzg.pack("asdf", writer);
        try nerve.sendSlice(buffer.items, .{});
        try head.processHead(t.allocator);

        _ = try nerve.recvMsg(&message, .{});
        try t.expect(!message.more());
        var response = try Resp.parse(t.allocator, message.slice());
        defer response.deinit(t.allocator);
        try t.expectEqual(Resp{ .pulse = .absence }, response);
    }

    {
        defer buffer.clearRetainingCapacity();

        const writer = buffer.writer(t.allocator);
        try mzg.pack("down", writer);
        try mzg.pack("test", writer);
        try nerve.sendSlice(buffer.items, .{});
        try head.processHead(t.allocator);

        _ = try nerve.recvMsg(&message, .{});
        try t.expect(!message.more());
        var response = try Resp.parse(t.allocator, message.slice());
        defer response.deinit(t.allocator);
        try t.expectEqual(Resp{ .down = .absence }, response);
    }
}
test checkMembers {
    const t = std.testing;

    var context: *zimq.Context = try .init();
    defer context.deinit();

    var head: Head = try .init(context, .{
        .head = "inproc://#1/head",
        .noti = "inproc://#1/noti",
        .ping = "inproc://#1/ping",
    });
    defer head.deinit(t.allocator);

    var nerve: *zimq.Socket = try .init(context, .req);
    defer nerve.deinit();

    try nerve.connect("inproc://#1/head");

    var buffer: ArrayListUnmanaged(u8) = .empty;
    defer buffer.deinit(t.allocator);

    var message: zimq.Message = .empty();
    {
        defer buffer.clearRetainingCapacity();

        const writer = buffer.writer(t.allocator);
        try mzg.pack("join", writer);
        try mzg.pack(
            .{ "test1", 10 * ns_per_ms, packMap(&StringArrayHashMapUnmanaged(u8).empty) },
            writer,
        );
        try nerve.sendSlice(buffer.items, .{});
        try head.processHead(t.allocator);
        _ = try nerve.recvMsg(&message, .{});
    }
    {
        defer buffer.clearRetainingCapacity();

        const writer = buffer.writer(t.allocator);
        try mzg.pack("join", writer);
        try mzg.pack(
            .{ "test2", 10 * ns_per_s, packMap(&StringArrayHashMapUnmanaged(u8).empty) },
            writer,
        );
        try nerve.sendSlice(buffer.items, .{});
        try head.processHead(t.allocator);
        _ = try nerve.recvMsg(&message, .{});
    }

    try head.checkMembers(t.allocator);
    try t.expectEqual(2, head.members.count());

    std.Thread.sleep(11 * ns_per_ms);

    try head.checkMembers(t.allocator);
    try t.expectEqual(1, head.members.count());

    {
        defer buffer.clearRetainingCapacity();

        const writer = buffer.writer(t.allocator);
        try mzg.pack("pulse", writer);
        try mzg.pack("test1", writer);
        try nerve.sendSlice(buffer.items, .{});
        try head.processHead(t.allocator);

        _ = try nerve.recvMsg(&message, .{});
        try t.expect(!message.more());
        var response = try Resp.parse(t.allocator, message.slice());
        defer response.deinit(t.allocator);
        try t.expectEqual(Resp{ .pulse = .absence }, response);
    }
    {
        defer buffer.clearRetainingCapacity();

        const writer = buffer.writer(t.allocator);
        try mzg.pack("pulse", writer);
        try mzg.pack("test2", writer);
        try nerve.sendSlice(buffer.items, .{});
        try head.processHead(t.allocator);

        _ = try nerve.recvMsg(&message, .{});
        try t.expect(!message.more());
        var response = try Resp.parse(t.allocator, message.slice());
        defer response.deinit(t.allocator);
        try t.expectEqual(Resp{ .pulse = .success }, response);
    }
}
test Registration {
    const t = std.testing;

    var registration: Registration = undefined;
    _ = try mzg.unpack(
        "\x93\xA4test\xCE\x3B\x9A\xCA\x00\x80",
        registration.mzgUnpacker(t.allocator),
    );

    try t.expectEqualStrings("test", registration.name);
}

const std = @import("std");
const StringArrayHashMapUnmanaged = std.StringArrayHashMapUnmanaged;
const Allocator = std.mem.Allocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const eql = std.mem.eql;
const ns_per_s = std.time.ns_per_s;
const ns_per_ms = std.time.ns_per_ms;
const Instant = std.time.Instant;

const zimq = @import("zimq");

const mzg = @import("mzg");
const packMap = mzg.adapter.packMap;
const unpackMap = mzg.adapter.unpackMap;

const zic = @import("root.zig");

const Resp = zic.Resp;
const Join = zic.Join;
const Pulse = zic.Pulse;
const Down = zic.Down;
