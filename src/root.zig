pub const Header = enum { ping, noti };

const utils = @import("utils.zig");

pub const consumeAll = utils.consumeAll;
pub const StructAsTaggedUnion = utils.StructAsTaggedUnion;
pub const AsOptional = utils.AsOptional;

const source = @import("source.zig");
pub const Source = source.Source;

const sink = @import("sink.zig");
pub const Sink = source.Sink;

comptime {
    const t = @import("std").testing;

    t.refAllDeclsRecursive(source);
    t.refAllDeclsRecursive(sink);
}
