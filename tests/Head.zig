test "Head and Nerve join" {
    const allocator = t.allocator;

    var context: *zimq.Context = try .init();
    defer context.deinit();

    var head: zic.Head = try .init(context, .{
        .head = "inproc://#1/head",
        .noti = "inproc://#1/noti",
        .ping = "inproc://#1/ping",
    });
    defer head.deinit(allocator);

    var nerve: zic.Nerve = try .init(context, "inproc://#1/head");
    defer nerve.deinit(allocator);

    var watch: zic.Watch = try .init(context, .{
        .ping = "inproc://#1/ping",
        .noti = "inproc://#1/noti",
    });
    defer watch.deinit();

    {
        var i: u8 = 0;
        while (i < 10) : (i += 1) {
            sleep(5 * ns_per_ms);

            try watch.sendPing();
            try head.consumePing();
            try head.broadcastMembers(allocator);

            var result = watch.process(allocator);
            if (result) |*noti| {
                defer noti.deinit(allocator);

                try t.expect(watch.connected);
                for (head.members.keys(), noti.members.items) |expected, actual| {
                    try t.expectEqualStrings(expected, actual);
                }
                break;
            } else |_| {}
        } else {
            try t.expect(false);
        }
    }

    {
        try nerve.sendJoin(allocator, "test", 200, .initComptime(
            .{
                &.{ "hello", "inproc://#1/hello" },
            },
        ));
        try head.processHead(allocator);

        const response = try nerve.getResponse(allocator);
        try t.expectEqual(Resp{ .join = .success }, response);

        var noti = try watch.process(allocator);
        defer noti.deinit(allocator);

        try t.expectEqualStrings("test", noti.join);
    }

    {
        try nerve.sendJoin(allocator, "test", 200, .initComptime(
            .{
                &.{ "hello", "inproc://#1/hello" },
            },
        ));
        try head.processHead(allocator);

        const response = try nerve.getResponse(allocator);
        try t.expectEqual(Resp{ .join = .duplicate }, response);

        if (watch.process(allocator)) |_| {} else |err| {
            try t.expectEqual(error.WouldBlock, err);
        }
    }
}

test "Head and Nerve down" {
    const allocator = t.allocator;

    var context: *zimq.Context = try .init();
    defer context.deinit();

    var head: zic.Head = try .init(context, .{
        .head = "inproc://#1/head",
        .noti = "inproc://#1/noti",
        .ping = "inproc://#1/ping",
    });
    defer head.deinit(allocator);

    var watch: zic.Watch = try .init(context, .{
        .ping = "inproc://#1/ping",
        .noti = "inproc://#1/noti",
    });
    defer watch.deinit();
    {
        var i: u8 = 0;
        while (i < 10) : (i += 1) {
            sleep(1 * ns_per_ms);

            try head.broadcastMembers(allocator);
            _ = watch.process(allocator) catch {};
            if (watch.connected) break;
        } else {
            try t.expect(false);
        }
    }

    var nerve: zic.Nerve = try .init(context, "inproc://#1/head");
    defer nerve.deinit(allocator);

    try nerve.sendJoin(allocator, "test", 200, .initComptime(
        .{
            &.{ "hello", "inproc://#1/hello" },
        },
    ));
    try head.processHead(allocator);
    _ = try nerve.getResponse(allocator);

    {
        var noti = try watch.process(allocator);
        defer noti.deinit(allocator);

        try t.expectEqualStrings("test", noti.join);
    }

    {
        try nerve.sendDown(allocator, "test");
        try head.processHead(allocator);

        const response = try nerve.getResponse(allocator);
        try t.expectEqual(Resp{ .down = .success }, response);

        var noti = try watch.process(allocator);
        defer noti.deinit(allocator);

        try t.expectEqualStrings("test", noti.down);
    }

    {
        try nerve.sendPulse(allocator, "test");
        try head.processHead(allocator);

        const response = try nerve.getResponse(allocator);
        try t.expectEqual(Resp{ .pulse = .absence }, response);
    }

    {
        try nerve.sendDown(allocator, "test");
        try head.processHead(allocator);

        const response = try nerve.getResponse(allocator);
        try t.expectEqual(Resp{ .down = .absence }, response);
    }

    {
        try nerve.sendDown(allocator, "nopenoneverexists");
        try head.processHead(allocator);

        const response = try nerve.getResponse(allocator);
        try t.expectEqual(Resp{ .down = .absence }, response);
    }
}

test "Head and Nerve checkMembers" {
    const allocator = t.allocator;

    var context: *zimq.Context = try .init();
    defer context.deinit();

    var head: zic.Head = try .init(context, .{
        .head = "inproc://#1/head",
        .noti = "inproc://#1/noti",
        .ping = "inproc://#1/ping",
    });
    defer head.deinit(allocator);

    var nerve: zic.Nerve = try .init(context, "inproc://#1/head");
    defer nerve.deinit(allocator);

    try nerve.sendJoin(allocator, "test", 10 * ns_per_ms, .initComptime(
        .{
            &.{ "hello", "inproc://#1/hello" },
        },
    ));
    try head.processHead(allocator);
    _ = try nerve.getResponse(allocator);

    {
        sleep(5 * ns_per_ms);
        try head.checkMembers(allocator);

        try nerve.sendPulse(allocator, "test");
        try head.processHead(allocator);

        const response = try nerve.getResponse(allocator);
        try t.expectEqual(Resp{ .pulse = .success }, response);
    }

    {
        sleep(11 * ns_per_ms);
        try head.checkMembers(allocator);

        try nerve.sendPulse(allocator, "test");
        try head.processHead(allocator);

        const response = try nerve.getResponse(allocator);
        try t.expectEqual(Resp{ .pulse = .absence }, response);
    }
}

test "Head and Nerve query" {
    const allocator = t.allocator;

    var context: *zimq.Context = try .init();
    defer context.deinit();

    var head: zic.Head = try .init(context, .{
        .head = "inproc://#1/head",
        .noti = "inproc://#1/noti",
        .ping = "inproc://#1/ping",
    });
    defer head.deinit(allocator);

    var watch: zic.Watch = try .init(context, .{
        .ping = "inproc://#1/ping",
        .noti = "inproc://#1/noti",
    });
    defer watch.deinit();
    {
        var i: u8 = 0;
        while (i < 10) : (i += 1) {
            sleep(1 * ns_per_ms);

            try head.broadcastMembers(allocator);
            _ = watch.process(allocator) catch {};
            if (watch.connected) break;
        } else {
            try t.expect(false);
        }
    }

    var nerve: zic.Nerve = try .init(context, "inproc://#1/head");
    defer nerve.deinit(allocator);

    {
        try nerve.sendJoin(allocator, "test", 10 * ns_per_ms, .initComptime(
            .{
                &.{ "hello", "inproc://#1/hello" },
            },
        ));
        try head.processHead(allocator);
        _ = try nerve.getResponse(allocator);

        var noti = try watch.process(allocator);
        defer noti.deinit(allocator);

        try t.expectEqualStrings("test", noti.join);
    }

    {
        sleep(5 * ns_per_ms);
        try head.checkMembers(allocator);

        try nerve.sendQuery(allocator, "test");
        try head.processHead(allocator);

        var actual = try nerve.getResponse(allocator);
        defer actual.deinit(allocator);
        const endpoints = actual.query.endpoints;
        try t.expectEqualStrings("inproc://#1/hello", endpoints.get("hello").?);
    }

    {
        sleep(11 * ns_per_ms);
        try head.checkMembers(allocator);

        {
            try nerve.sendQuery(allocator, "test");
            try head.processHead(allocator);

            var actual = try nerve.getResponse(allocator);
            defer actual.deinit(allocator);
            try t.expectEqual(Resp{ .query = .absence }, actual);
        }

        {
            var noti = try watch.process(allocator);
            defer noti.deinit(allocator);

            try t.expectEqualStrings("test", noti.down);
        }
    }
}

const std = @import("std");
const t = std.testing;
const ns_per_ms = std.time.ns_per_ms;
const sleep = std.Thread.sleep;

const zimq = @import("zimq");

const zic = @import("zic");
const Resp = zic.Head.Resp;
