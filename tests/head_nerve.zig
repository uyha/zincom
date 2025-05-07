test "Head and Nerve join" {
    const allocator = t.allocator;

    var context: *zimq.Context = try .init();
    defer context.deinit();

    var head: zic.Head = try .init(context, "inproc://#1/head");
    defer head.deinit(allocator);

    var nerve: zic.Nerve = try .init(context, "inproc://#1/head");
    defer nerve.deinit(allocator);

    {
        try nerve.sendJoin(allocator, "test", 200, .initComptime(
            .{
                &.{ "hello", "inproc://#1/hello" },
            },
        ));
        try head.process(allocator);

        const response = try nerve.getResponse(allocator);
        try t.expectEqual(zic.Resp{ .join = .success }, response);
    }

    {
        try nerve.sendJoin(allocator, "test", 200, .initComptime(
            .{
                &.{ "hello", "inproc://#1/hello" },
            },
        ));
        try head.process(allocator);

        const response = try nerve.getResponse(allocator);
        try t.expectEqual(zic.Resp{ .join = .duplicate }, response);
    }
}

test "Head and Nerve down" {
    const allocator = t.allocator;

    var context: *zimq.Context = try .init();
    defer context.deinit();

    var head: zic.Head = try .init(context, "inproc://#1/head");
    defer head.deinit(allocator);

    var nerve: zic.Nerve = try .init(context, "inproc://#1/head");
    defer nerve.deinit(allocator);

    try nerve.sendJoin(allocator, "test", 200, .initComptime(
        .{
            &.{ "hello", "inproc://#1/hello" },
        },
    ));
    try head.process(allocator);
    _ = try nerve.getResponse(allocator);

    {
        try nerve.sendDown(allocator, "test");
        try head.process(allocator);

        const response = try nerve.getResponse(allocator);
        try t.expectEqual(zic.Resp{ .down = .success }, response);
    }

    {
        try nerve.sendPing(allocator, "test");
        try head.process(allocator);

        const response = try nerve.getResponse(allocator);
        try t.expectEqual(zic.Resp{ .ping = .absence }, response);
    }

    {
        try nerve.sendDown(allocator, "test");
        try head.process(allocator);

        const response = try nerve.getResponse(allocator);
        try t.expectEqual(zic.Resp{ .down = .absence }, response);
    }

    {
        try nerve.sendDown(allocator, "nopenoneverexists");
        try head.process(allocator);

        const response = try nerve.getResponse(allocator);
        try t.expectEqual(zic.Resp{ .down = .absence }, response);
    }
}

test "Head and Nerve checkMembers" {
    const allocator = t.allocator;

    var context: *zimq.Context = try .init();
    defer context.deinit();

    var head: zic.Head = try .init(context, "inproc://#1/head");
    defer head.deinit(allocator);

    var nerve: zic.Nerve = try .init(context, "inproc://#1/head");
    defer nerve.deinit(allocator);

    try nerve.sendJoin(allocator, "test", 10 * ns_per_ms, .initComptime(
        .{
            &.{ "hello", "inproc://#1/hello" },
        },
    ));
    try head.process(allocator);
    _ = try nerve.getResponse(allocator);

    {
        sleep(5 * ns_per_ms);
        try head.checkMembers(allocator);

        try nerve.sendPing(allocator, "test");
        try head.process(allocator);

        const response = try nerve.getResponse(allocator);
        try t.expectEqual(zic.Resp{ .ping = .success }, response);
    }

    {
        sleep(11 * ns_per_ms);
        try head.checkMembers(allocator);

        try nerve.sendPing(allocator, "test");
        try head.process(allocator);

        const response = try nerve.getResponse(allocator);
        try t.expectEqual(zic.Resp{ .ping = .absence }, response);
    }
}

const std = @import("std");
const t = std.testing;
const ns_per_ms = std.time.ns_per_ms;
const sleep = std.Thread.sleep;

const zic = @import("zic");
const zimq = @import("zimq");
