pub const Header = enum { ping, noti, live, down };

const utils = @import("utils.zig");

pub const consumeAll = utils.consumeAll;
pub const StructAsTaggedUnion = utils.StructAsTaggedUnion;

const publisher = @import("publisher.zig");
pub const Publisher = publisher.Publisher;

comptime {
    const t = @import("std").testing;

    t.refAllDeclsRecursive(publisher);
}
