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

    {
        try nerve.sendJoin(allocator, "test", 200, .initComptime(
            .{
                &.{ "hello", "inproc://#1/hello" },
            },
        ));
        try head.processHead(allocator);

        const response = try nerve.getResponse(allocator);
        try t.expectEqual(Resp{ .join = .success }, response);
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
        try nerve.sendDown(allocator, "test");
        try head.processHead(allocator);

        const response = try nerve.getResponse(allocator);
        try t.expectEqual(Resp{ .down = .success }, response);
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

const std = @import("std");
const t = std.testing;
const ns_per_ms = std.time.ns_per_ms;
const sleep = std.Thread.sleep;

const zimq = @import("zimq");

const zic = @import("zic");
const Resp = zic.Head.Resp;
