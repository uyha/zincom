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
        try t.expectEqual(zic.Response{ .join = .success }, response);
    }

    {
        try nerve.sendJoin(allocator, "test", 200, .initComptime(
            .{
                &.{ "hello", "inproc://#1/hello" },
            },
        ));
        try head.process(allocator);

        const response = try nerve.getResponse(allocator);
        try t.expectEqual(zic.Response{ .join = .duplicate }, response);
    }
}

test "Head and Nerve ping" {
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
        try nerve.sendPing(allocator, "test");
        try head.process(allocator);

        const response = try nerve.getResponse(allocator);
        try t.expectEqual(zic.Response{ .ping = .success }, response);
    }

    {
        try nerve.sendPing(allocator, "nopenoneverexists");
        try head.process(allocator);

        const response = try nerve.getResponse(allocator);
        try t.expectEqual(zic.Response{ .ping = .absence }, response);
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
        try nerve.sendPing(allocator, "test");
        try head.process(allocator);

        const response = try nerve.getResponse(allocator);
        try t.expectEqual(zic.Response{ .ping = .success }, response);
    }

    {
        try nerve.sendPing(allocator, "nopenoneverexists");
        try head.process(allocator);

        const response = try nerve.getResponse(allocator);
        try t.expectEqual(zic.Response{ .ping = .absence }, response);
    }
}

const std = @import("std");
const t = std.testing;

const zic = @import("zic");
const zimq = @import("zimq");
