pub const Header = enum { ping, noti, live, down };

const utils = @import("utils.zig");

pub const consumeAll = utils.consumeAll;
pub const StructAsTaggedUnion = utils.StructAsTaggedUnion;

const source = @import("source.zig");
pub const Source = source.Publisher;

comptime {
    const t = @import("std").testing;

    t.refAllDeclsRecursive(source);
}
