test "source sink ping" {
    const allocator = t.allocator;

    var context: *zimq.Context = try .init();
    defer context.deinit();

    const Data = struct {
        position: i32,
        velocity: i32,
    };
    const Source = zic.Source(?Data);
    const Sink = zic.Sink(Source.Data);

    var source: Source = try .init(context, .{
        .noti = "inproc://#1/noti",
        .ping = "inproc://#1/ping",
    }, null);
    defer source.deinit(allocator);

    var sink: Sink = try .init(context, .{
        .noti = "inproc://#1/noti",
        .ping = "inproc://#1/ping",
    });
    defer sink.deinit();

    try t.expect(!sink.connected);
    try t.expect(sink.data == null);

    {
        var i: u8 = 0;
        while (i < 10) : (i += 1) {
            sleep(1 * ns_per_ms);

            try sink.sendPing();
            try source.processPing(allocator);

            try sink.process();

            if (sink.connected) {
                break;
            }
        }

        try t.expect(sink.connected);
        try t.expect(sink.data == null);
    }

    {
        try source.setCurrent(allocator, .{ .position = 100, .velocity = 200 });
        try sink.process();

        try t.expect(sink.connected);
        try t.expect(sink.data != null);
        try t.expectEqual(100, sink.data.?.position);
        try t.expectEqual(200, sink.data.?.velocity);
    }

    {
        try source.setCurrent(allocator, null);
        try sink.process();

        try t.expect(sink.connected);
        try t.expect(sink.data == null);
    }
}

test "source sink field updated" {
    const allocator = t.allocator;

    var context: *zimq.Context = try .init();
    defer context.deinit();

    const Data = struct {
        position: i32,
        velocity: i32,
    };
    const Source = zic.Source(?Data);
    const Sink = zic.Sink(Source.Data);

    var source: Source = try .init(context, .{
        .noti = "inproc://#1/noti",
        .ping = "inproc://#1/ping",
    }, .{ .position = 100, .velocity = 200 });
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
            try source.processPing(allocator);

            try sink.process();

            if (sink.connected) {
                break;
            }
        }

        try t.expect(sink.connected);
        try t.expect(sink.data != null);
        try t.expectEqual(Data{
            .position = 100,
            .velocity = 200,
        }, sink.data.?);
    }

    {
        try source.setField(allocator, .{ .position = 300 });
        try sink.process();

        try t.expect(sink.connected);
        try t.expect(sink.data != null);
        try t.expectEqual(Data{
            .position = 300,
            .velocity = 200,
        }, sink.data.?);
    }

    {
        try source.setField(allocator, .{ .velocity = 400 });
        try sink.process();

        try t.expect(sink.connected);
        try t.expect(sink.data != null);
        try t.expectEqual(Data{
            .position = 300,
            .velocity = 400,
        }, sink.data.?);
    }
}

const std = @import("std");
const t = std.testing;
const sleep = std.Thread.sleep;
const ns_per_ms = std.time.ns_per_ms;

const zimq = @import("zimq");
const zic = @import("zic");
