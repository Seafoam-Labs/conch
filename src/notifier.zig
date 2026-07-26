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

const HintValue = union(enum) {
    str: GStr,
    int: i32,
};

const Hint = struct {
    key: GStr,
    value: HintValue,
};

pub const Action = struct {
    key: [:0]const u8,
    label: [:0]const u8,
};

pub const ActionFn = *const fn (ctx: ?*anyopaque, id: u32, key: []const u8) void;
pub const ClosedFn = *const fn (ctx: ?*anyopaque, id: u32, reason: u32) void;
pub const ActivateFn = *const fn (ctx: ?*anyopaque, id: u32) void;

pub const Notification = struct {
    app_name: [:0]const u8 = "",
    icon: [:0]const u8 = "",
    summary: [:0]const u8,
    body: [:0]const u8 = "",
    tooltip: [:0]const u8 = "",
    timeout_ms: i32 = -1,
    replaces_id: u32 = 0,
    actions: []const Action = &.{},
    on_activate: ?ActivateFn = null,
    on_action: ?ActionFn = null,
    on_closed: ?ClosedFn = null,
    ctx: ?*anyopaque = null,
};

const Handlers = struct {
    on_activate: ?ActivateFn,
    on_action: ?ActionFn,
    on_closed: ?ClosedFn,
    ctx: ?*anyopaque,
};

pub const Notifier = struct {
    service: *Service,
    live: std.AutoHashMap(u32, Handlers),
    subscribed: bool = false,

    pub fn init(svc: *Service) Notifier {
        return .{
            .service = svc,
            .live = std.AutoHashMap(u32, Handlers).init(svc.allocator),
        };
    }

    pub fn deinit(self: *Notifier) void {
        self.live.deinit();
    }

    pub fn notify(self: *Notifier, n: Notification) !u32 {
        const conn = self.service.connection();
        const alloc = self.service.allocator;

        const wants_signals = n.on_activate != null or n.on_action != null or n.on_closed != null;
        if (wants_signals) try self.ensure_subsribed();

        const inject = n.on_activate != null;
        const total = n.actions.len + @as(usize, if (inject) 1 else 0);
        var strs = try alloc.alloc(GStr, total * 2);
        defer alloc.free(strs);

        var w: usize = 0;
        if (inject) {
            strs[w] = GStr.new("default");
            strs[w + 1] = GStr.new("");
            w += 2;
        }
        for (n.actions) |act| {
            strs[w] = GStr.new(act.key);
            strs[w + 1] = GStr.new(act.label);
            w += 2;
        }
        const actions: []const GStr = strs;
        const hints: []const Hint = &.{};

        var enc = try BodyEncoder.encode(alloc, .{
            GStr.new(n.app_name),
            n.replaces_id,
            GStr.new(n.icon),
            GStr.new(n.summary),
            GStr.new(n.body),
            actions,
            hints,
            n.timeout_ms,
        });
        defer enc.deinit();

        var reply = try conn.methodCall(
            NOTIFY_NAME,
            NOTIFY_PATH,
            NOTIFY_IFACE,
            "Notify",
            enc.signature(),
            enc.body(),
        );
        defer conn.freeMessage(&reply);

        var dec = BodyDecoder.fromMessage(alloc, reply);
        const id = try dec.decode(u32);

        if (wants_signals) {
            try self.live.put(id, .{
                .on_activate = n.on_activate,
                .on_action = n.on_action,
                .on_closed = n.on_closed,
                .ctx = n.ctx,
            });
        }
        return id;
    }

    fn ensure_subsribed(self: *Notifier) !void {
        if (self.subscribed) return;
        const conn = self.service.connection();

        try conn.addMatch("type='signal',interface='org.freedesktop.Notifications'");

        try conn.registerSignalHandler(NOTIFY_IFACE, "ActionInvoked", on_action_invoked, self);
        try conn.registerSignalHandler(NOTIFY_IFACE, "NotificationClosed", on_notification_closed, self);
        self.subscribed = true;
    }

    pub fn close(self: *Notifier, id: u32) !void {
        const conn = self.service.connection();
        var enc = try BodyEncoder.encode(self.service.allocator, id);
        defer enc.deinit();

        var reply = try conn.methodCall(
            NOTIFY_NAME,
            NOTIFY_PATH,
            NOTIFY_IFACE,
            "CloseNotification",
            enc.signature(),
            enc.body(),
        );
        conn.freeMessage(&reply);
    }

    fn on_action_invoked(ctx: ?*anyopaque, msg: goose.core.Message) void {
        const self: *Notifier = @ptrCast(@alignCast(ctx.?));
        var dec = BodyDecoder.fromMessage(self.service.allocator, msg);
        const id = dec.decode(u32) catch return;
        const key = dec.decode(GStr) catch return;
        if (self.live.get(id)) |h| {
            if (std.mem.eql(u8, key.s, "default")) {
                if (h.on_activate) |cb| cb(h.ctx, id);
            } else {
                if (h.on_action) |cb| cb(h.ctx, id, key.s);
            }
        }
    }

    fn on_notification_closed(ctx: ?*anyopaque, msg: goose.core.Message) void {
        const self: *Notifier = @ptrCast(@alignCast(ctx.?));
        var dec = BodyDecoder.fromMessage(self.service.allocator, msg);
        const id = dec.decode(u32) catch return;
        const reason = dec.decode(u32) catch return;
        if (self.live.fetchRemove(id)) |kv| {
            if (kv.value.on_closed) |cb| cb(kv.value.ctx, id, reason);
        }
    }
};

const testing = std.testing;

test "Notify signature is correct with no actions" {
    const alloc = testing.allocator;
    const actions: []const GStr = &.{};
    const hints: []const Hint = &.{};
    var enc = try BodyEncoder.encode(alloc, .{
        GStr.new(""), @as(u32, 0), GStr.new(""), GStr.new("s"), GStr.new(""),
        actions,      hints,       @as(i32, -1),
    });
    defer enc.deinit();
    try testing.expectEqualStrings(NOTIFY_SIGNATURE, enc.signature());
}
