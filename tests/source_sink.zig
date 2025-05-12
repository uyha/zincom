test "source sink whole" {
    const allocator = t.allocator;

    var context: *zimq.Context = try .init();
    defer context.deinit();

    const Data = struct { position: i32, velocity: i32 };

    var source: Source = try .init(context, .{
        .noti = "inproc://#1/noti",
        .ping = "inproc://#1/ping",
    });
    defer source.deinit(allocator);

    var sink: Sink = try .init(context, .{
        .noti = "inproc://#1/noti",
        .ping = "inproc://#1/ping",
    });
    defer sink.deinit();

    try t.expect(!sink.connected);

    {
        const expected: Data = .{ .position = 10, .velocity = 20 };

        var i: u8 = 0;
        while (i < 10) : (i += 1) {
            sleep(1 * ns_per_ms);

            try sink.sendPing();
            try source.consumePing();
            try source.broadcastWhole(allocator, expected);

            if (sink.process(Data)) |actual| {
                try t.expect(sink.connected);
                try t.expectEqual(expected, actual.whole);
                break;
            } else |_| {
                try t.expect(!sink.connected);
            }

            if (sink.connected) {
                break;
            }
        }
    }
}

test "source sink part" {
    const allocator = t.allocator;

    var context: *zimq.Context = try .init();
    defer context.deinit();

    const Data = struct { position: i32, velocity: i32 };

    var source: Source = try .init(context, .{
        .noti = "inproc://#1/noti",
        .ping = "inproc://#1/ping",
    });
    defer source.deinit(allocator);

    var sink: Sink = try .init(context, .{
        .noti = "inproc://#1/noti",
        .ping = "inproc://#1/ping",
    });
    defer sink.deinit();

    try t.expect(!sink.connected);

    {
        const expected: Data = .{ .position = 10, .velocity = 20 };

        var i: u8 = 0;
        while (i < 10) : (i += 1) {
            sleep(1 * ns_per_ms);

            try sink.sendPing();
            try source.consumePing();
            try source.broadcastPart(allocator, expected, .velocity);

            if (sink.process(Data)) |actual| {
                try t.expect(sink.connected);
                try t.expectEqual(expected.velocity, actual.part.velocity);
                break;
            } else |_| {
                try t.expect(!sink.connected);
            }

            if (sink.connected) {
                break;
            }
        }
    }
}

test "source sink nil" {
    const allocator = t.allocator;

    var context: *zimq.Context = try .init();
    defer context.deinit();

    const Data = struct { position: i32, velocity: i32 };

    var source: Source = try .init(context, .{
        .noti = "inproc://#1/noti",
        .ping = "inproc://#1/ping",
    });
    defer source.deinit(allocator);

    var sink: Sink = try .init(context, .{
        .noti = "inproc://#1/noti",
        .ping = "inproc://#1/ping",
    });
    defer sink.deinit();

    try t.expect(!sink.connected);

    {
        var i: u8 = 0;
        while (i < 10) : (i += 1) {
            sleep(1 * ns_per_ms);

            try sink.sendPing();
            try source.consumePing();
            try source.broadcastNil(allocator);

            if (sink.process(Data)) |actual| {
                try t.expect(sink.connected);
                try t.expectEqual({}, actual.nil);
                break;
            } else |_| {
                try t.expect(!sink.connected);
            }

            if (sink.connected) {
                break;
            }
        }
    }
}

const std = @import("std");
const t = std.testing;
const sleep = std.Thread.sleep;
const ns_per_ms = std.time.ns_per_ms;

const zimq = @import("zimq");

const zic = @import("zic");
const Source = zic.Source;
const Noti = Source.Noti;
const Part = Source.Part;
const Sink = zic.Sink;
