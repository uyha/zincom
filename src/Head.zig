const Head = @This();

head: *zimq.Socket,
members: StringArrayHashMapUnmanaged(Member) = .empty,

buffer: ArrayListUnmanaged(u8) = .empty,
message: zimq.Message,

pub const InitError = zimq.Socket.InitError || zimq.Socket.BindError;
pub fn init(context: *zimq.Context, prefix: []const u8) InitError!Head {
    const result: Head = .{
        .head = try .init(context, .rep),
        .message = .empty(),
    };

    var buffer: [1024]u8 = undefined;

    try result.head.bind(std.fmt.bufPrintZ(
        &buffer,
        "{s}/head",
        .{prefix},
    ) catch @panic("buffer too small"));

    return result;
}

pub fn deinit(self: *Head, allocator: Allocator) void {
    self.head.deinit();

    for (self.members.entries.items(.value)) |*value| {
        value.deinit(allocator);
    }
    self.members.deinit(allocator);

    self.buffer.deinit(allocator);
    self.message.deinit();
}

pub const ProcessError = zimq.Socket.RecvMsgError || zimq.Socket.SendError || mzg.UnpackError || error{ HeaderInvalid, Unsupported };
pub fn process(self: *Head, allocator: Allocator) ProcessError!void {
    _ = try self.head.recvMsg(&self.message, .{});

    if (startsWith(u8, self.message.slice(), "join")) {
        return self.processJoin(allocator, self.message.slice()[4..]);
    }
    if (startsWith(u8, self.message.slice(), "ping")) {
        return self.processPing(allocator, self.message.slice()[4..]);
    }
    if (startsWith(u8, self.message.slice(), "down")) {
        return self.processDown(allocator, self.message.slice()[4..]);
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
                .last_ping = try .now(),
                .endpoints = registration.endpoints,
                .raw = raw,
            });

            break :result Join.success;
        }
    };

    self.buffer.clearRetainingCapacity();
    const writer = self.buffer.writer(allocator);
    try writer.writeAll("join");
    try mzg.pack(result, writer);

    try self.head.sendSlice(self.buffer.items, .{});
}

test processJoin {
    const t = std.testing;

    var context: *zimq.Context = try .init();
    defer context.deinit();

    var head: Head = try .init(context, "inproc://#1");
    defer head.deinit(t.allocator);

    var nerve: *zimq.Socket = try .init(context, .req);
    defer nerve.deinit();

    try nerve.connect("inproc://#1/head");

    var buffer: ArrayListUnmanaged(u8) = .empty;
    defer buffer.deinit(t.allocator);

    const writer = buffer.writer(t.allocator);
    try writer.writeAll("join");
    try mzg.pack(
        .{ "test", 1 * ns_per_s, packMap(&StringArrayHashMapUnmanaged(u8).empty) },
        writer,
    );
    try nerve.sendSlice(buffer.items, .{});

    try head.process(t.allocator);

    const member = head.members.get("test");
    try t.expect(member != null);
    try t.expectEqualStrings("test", member.?.name);
    try t.expectEqual(1 * ns_per_s, member.?.interval);

    var message: zimq.Message = .empty();
    _ = try nerve.recvMsg(&message, .{});
    try t.expect(!message.more());

    try t.expectEqual(
        Response{ .join = .success },
        try Response.parse(message.slice()),
    );

    // Joining again should fail with `duplicate` returned
    try nerve.sendSlice(buffer.items, .{});
    try head.process(t.allocator);

    _ = try nerve.recvMsg(&message, .{});
    try t.expect(!message.more());

    try t.expectEqual(
        Response{ .join = .duplicate },
        try Response.parse(message.slice()),
    );
}

fn processPing(
    self: *Head,
    allocator: Allocator,
    slice: []const u8,
) ProcessError!void {
    var name: []const u8 = undefined;
    _ = try mzg.unpack(slice, &name);

    const result: Ping = blk: {
        if (self.members.getEntry(name)) |entry| {
            entry.value_ptr.last_ping = try .now();
            break :blk Ping.success;
        } else {
            break :blk Ping.absence;
        }
    };

    self.buffer.clearRetainingCapacity();
    const writer = self.buffer.writer(allocator);
    try writer.writeAll("ping");
    try mzg.pack(result, writer);

    try self.head.sendSlice(self.buffer.items, .{});
}

test processPing {
    const t = std.testing;

    var context: *zimq.Context = try .init();
    defer context.deinit();

    var head: Head = try .init(context, "inproc://#1");
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
        try writer.writeAll("join");
        try mzg.pack(
            .{ "test", 1 * ns_per_s, packMap(&StringArrayHashMapUnmanaged(u8).empty) },
            writer,
        );
        try nerve.sendSlice(buffer.items, .{});
        try head.process(t.allocator);
        _ = try nerve.recvMsg(&message, .{});
    }

    {
        defer buffer.clearRetainingCapacity();

        const writer = buffer.writer(t.allocator);
        try writer.writeAll("ping");
        try mzg.pack("test", writer);
        try nerve.sendSlice(buffer.items, .{});
        try head.process(t.allocator);

        _ = try nerve.recvMsg(&message, .{});
        try t.expect(!message.more());
        try t.expectEqual(
            Response{ .ping = .success },
            try Response.parse(message.slice()),
        );
    }

    {
        defer buffer.clearRetainingCapacity();

        const writer = buffer.writer(t.allocator);
        try writer.writeAll("ping");
        try mzg.pack("asdf", writer);
        try nerve.sendSlice(buffer.items, .{});
        try head.process(t.allocator);

        _ = try nerve.recvMsg(&message, .{});
        try t.expect(!message.more());
        try t.expectEqual(
            Response{ .ping = .absence },
            try Response.parse(message.slice()),
        );
    }
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
    try writer.writeAll("down");
    try mzg.pack(result, writer);

    try self.head.sendSlice(self.buffer.items, .{});
}

test processDown {
    const t = std.testing;

    var context: *zimq.Context = try .init();
    defer context.deinit();

    var head: Head = try .init(context, "inproc://#1");
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
        try writer.writeAll("join");
        try mzg.pack(
            .{ "test", 1 * ns_per_s, packMap(&StringArrayHashMapUnmanaged(u8).empty) },
            writer,
        );
        try nerve.sendSlice(buffer.items, .{});
        try head.process(t.allocator);
        _ = try nerve.recvMsg(&message, .{});
    }

    {
        defer buffer.clearRetainingCapacity();

        const writer = buffer.writer(t.allocator);
        try writer.writeAll("down");
        try mzg.pack("test", writer);
        try nerve.sendSlice(buffer.items, .{});
        try head.process(t.allocator);

        _ = try nerve.recvMsg(&message, .{});
        try t.expect(!message.more());
        try t.expectEqual(
            Response{ .down = .success },
            try Response.parse(message.slice()),
        );
    }

    {
        defer buffer.clearRetainingCapacity();

        const writer = buffer.writer(t.allocator);
        try writer.writeAll("ping");
        try mzg.pack("asdf", writer);
        try nerve.sendSlice(buffer.items, .{});
        try head.process(t.allocator);

        _ = try nerve.recvMsg(&message, .{});
        try t.expect(!message.more());
        try t.expectEqual(
            Response{ .ping = .absence },
            try Response.parse(message.slice()),
        );
    }

    {
        defer buffer.clearRetainingCapacity();

        const writer = buffer.writer(t.allocator);
        try writer.writeAll("down");
        try mzg.pack("test", writer);
        try nerve.sendSlice(buffer.items, .{});
        try head.process(t.allocator);

        _ = try nerve.recvMsg(&message, .{});
        try t.expect(!message.more());
        try t.expectEqual(
            Response{ .down = .absence },
            try Response.parse(message.slice()),
        );
    }
}

pub const CheckError = error{Unsupported};
pub fn checkMembers(self: *Head, allocator: Allocator) CheckError!void {
    const now: Instant = try .now();

    var i: usize = 0;
    while (i < self.members.count()) {
        var member = self.members.entries.get(i).value;
        if (now.since(member.last_ping) <= member.interval) {
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

test checkMembers {
    const t = std.testing;

    var context: *zimq.Context = try .init();
    defer context.deinit();

    var head: Head = try .init(context, "inproc://#1");
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
        try writer.writeAll("join");
        try mzg.pack(
            .{ "test1", 10 * ns_per_ms, packMap(&StringArrayHashMapUnmanaged(u8).empty) },
            writer,
        );
        try nerve.sendSlice(buffer.items, .{});
        try head.process(t.allocator);
        _ = try nerve.recvMsg(&message, .{});
    }
    {
        defer buffer.clearRetainingCapacity();

        const writer = buffer.writer(t.allocator);
        try writer.writeAll("join");
        try mzg.pack(
            .{ "test2", 10 * ns_per_s, packMap(&StringArrayHashMapUnmanaged(u8).empty) },
            writer,
        );
        try nerve.sendSlice(buffer.items, .{});
        try head.process(t.allocator);
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
        try writer.writeAll("ping");
        try mzg.pack("test1", writer);
        try nerve.sendSlice(buffer.items, .{});
        try head.process(t.allocator);

        _ = try nerve.recvMsg(&message, .{});
        try t.expect(!message.more());
        try t.expectEqual(
            Response{ .ping = .absence },
            try Response.parse(message.slice()),
        );
    }
    {
        defer buffer.clearRetainingCapacity();

        const writer = buffer.writer(t.allocator);
        try writer.writeAll("ping");
        try mzg.pack("test2", writer);
        try nerve.sendSlice(buffer.items, .{});
        try head.process(t.allocator);

        _ = try nerve.recvMsg(&message, .{});
        try t.expect(!message.more());
        try t.expectEqual(
            Response{ .ping = .success },
            try Response.parse(message.slice()),
        );
    }
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

test Registration {
    const t = std.testing;

    var registration: Registration = undefined;
    _ = try mzg.unpack(
        "\x93\xA4test\xCE\x3B\x9A\xCA\x00\x80",
        registration.mzgUnpacker(t.allocator),
    );

    try t.expectEqualStrings("test", registration.name);
}

pub const Member = struct {
    name: []const u8,
    interval: u64,
    last_ping: Instant,
    endpoints: StringArrayHashMapUnmanaged([]const u8),
    raw: ArrayListUnmanaged(u8),

    pub fn deinit(self: *Member, allocator: Allocator) void {
        self.endpoints.deinit(allocator);
        self.raw.deinit(allocator);
    }
};

const std = @import("std");
const StringArrayHashMapUnmanaged = std.StringArrayHashMapUnmanaged;
const Allocator = std.mem.Allocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const startsWith = std.mem.startsWith;
const ns_per_s = std.time.ns_per_s;
const ns_per_ms = std.time.ns_per_ms;
const Instant = std.time.Instant;

const zimq = @import("zimq");

const mzg = @import("mzg");
const packMap = mzg.adapter.packMap;
const unpackMap = mzg.adapter.unpackMap;

const zic = @import("root.zig");

const Response = zic.Response;
const Join = Response.Join;
const Ping = Response.Ping;
const Down = Response.Down;
