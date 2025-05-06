const utils = @import("utils.zig");

pub const consumeAll = utils.consumeAll;
pub const StructAsTaggedUnion = utils.StructAsTaggedUnion;
pub const AsOptional = utils.AsOptional;

const source = @import("source.zig");
pub const Source = source.Source;

const sink = @import("sink.zig");
pub const Sink = source.Sink;

const response = @import("response.zig");
pub const Response = response.Response;

pub const Head = @import("Head.zig");
pub const Nerve = @import("Nerve.zig");

comptime {
    const t = @import("std").testing;

    t.refAllDeclsRecursive(source);
    t.refAllDeclsRecursive(sink);
    t.refAllDeclsRecursive(Response);
    t.refAllDeclsRecursive(Head);
    t.refAllDeclsRecursive(Nerve);
}
