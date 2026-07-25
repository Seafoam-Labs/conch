const std = @import("std");
const goose = @import("goose");
const service = @import("service.zig");

const Service = service.Service;
const GStr = goose.core.value.GStr;
const BodyEncoder = goose.message.BodyEncoder;
const BodyDecoder = goose.message.BodyDecoder;

const NOTIFY_NAME = "org.freedesktop.Notifications";
const NOTIFY_PATH = "/org/freedesktop/Notifications";
const NOTIFY_IFACE = "org.freedesktop.Notifications";

pub const NOTIFY_SIGNATURE = "susssasa{sv}i";

/// Queries and holds the notification daemon's advertised capabilities
/// (e.g. "actions", "body", "inline-reply") for the current session.
/// Ownership: the struct owns all its heap memory
pub const Capabilities = struct {
    list: []const GStr,
    allocator: std.mem.Allocator,

    pub fn init(svc: *Service) !Capabilities {
        const conn = svc.connection();
        var reply = try conn.methodCall(
            NOTIFY_NAME,
            NOTIFY_PATH,
            NOTIFY_IFACE,
            "GetCapabilities",
            null,
            &.{},
        );
        defer conn.freeMessage(&reply);
        var dec = BodyDecoder.fromMessage(svc.allocator, reply);
        return .{ .list = try dec.decodeAlloc([]const GStr), .allocator = svc.allocator };
    }

    pub fn deinit(self: *Capabilities) void {
        for (self.list) |c| self.allocator.free(c.s);
        self.allocator.free(self.list);
    }

    pub fn has(self: Capabilities, cap: []const u8) bool {
        for (self.list) |c| if (std.mem.eql(u8, c.s, cap)) return true;
        return false;
    }
};

const testing = std.testing;

test "Capabilities.deinit frees nested allocations" {
    const alloc = testing.allocator;
    var list = try alloc.alloc(GStr, 2);
    const a = try alloc.allocSentinel(u8, 7, 0);
    @memcpy(a, "actions");
    const b = try alloc.allocSentinel(u8, 4, 0);
    @memcpy(b, "body");
    list[0] = GStr.new(a);
    list[1] = GStr.new(b);
    var caps = Capabilities{ .list = list, .allocator = alloc };
    caps.deinit();
    // testing.allocator panics at test end if deinit under/over-freed
}
