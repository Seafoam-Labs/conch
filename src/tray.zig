const std = @import("std");
const goose = @import("goose");
const item = @import("item.zig");
const service = @import("service.zig");
const core = goose.core;

const Service = service.Service;
const GStr = goose.core.value.GStr;
const Item = item.Item;
const Config = item.Config;

const ITEM_PATH = "/StatusNotifierItem";
const WATCHER_NAME = "org.kde.StatusNotifierWatcher";
const WATCHER_PATH = "/StatusNotifierWatcher";
const WATCHER_IFACE = "org.kde.StatusNotifierWatcher";

pub const Tray = struct {
    service: *Service,
    cfg: Config,
    name: [:0]const u8,
    handle: ?usize = null,

    pub fn init(svc: *Service, cfg: Config) !Tray {
        const pid = std.os.linux.getpid();
        const name = try std.fmt.allocPrintSentinel(svc.allocator, "org.kde.StatusNotifierItem-{d}-1", .{pid}, 0);
        return .{ .service = svc, .cfg = cfg, .name = name };
    }

    pub fn deinit(self: *Tray) void {
        self.service.allocator.free(self.name);
    }

    pub fn register(self: *Tray) !usize {
        const conn = self.service.connection();

        const handle = try conn.registerObject(Item, self.name, ITEM_PATH, &self.cfg);
        self.handle = handle;

        try conn.addMatch(
            "type='signal',interface='org.freedesktop.DBus',member='NameOwnerChanged',arg0='org.kde.StatusNotifierWatcher'",
        );
        try conn.registerSignalHandler("org.freedesktop.DBus", "NameOwnerChanged", on_name_owner_changed, self);

        try conn.addMatch(
            "type='signal',interface='org.kde.StatusNotifierWatcher',member='StatusNotifierHostRegistered'",
        );
        try conn.registerSignalHandler(WATCHER_IFACE, "StatusNotifierHostRegistered", on_host_registered, self);

        try self.announce();
        std.debug.print("[tray] registered as {s}\n", .{self.name});
        return handle;
    }

    pub fn emitNewIcon(self: *Tray, icon: [:0]const u8) !void {
        const conn = self.service.connection();
        const handle = self.handle orelse return;
        const it: *Item = @ptrCast(@alignCast(conn.registered_interfaces.items[handle].instance));
        it.IconName = goose.property(GStr, .Read, GStr.new(icon));

        const serial = conn.serial_counter;
        conn.serial_counter += 1;

        const header = core.MessageHeader{
            .message_type = .Signal,
            .flags = 0x1,
            .proto_version = 1,
            .body_length = 0,
            .serial = serial,
            .header_fields = @constCast(&[_]core.HeaderField{
                .{ .code = .Path, .value = .{ .Path = ITEM_PATH } },
                .{ .code = .Interface, .value = .{ .Interface = "org.kde.StatusNotifierItem" } },
                .{ .code = .Member, .value = .{ .Member = "NewIcon" } },
            }),
        };

        try conn.sendMessage(core.Message.new(header, &.{}));
    }

    fn announce(self: *Tray) !void {
        const conn = self.service.connection();
        const alloc = self.service.allocator;

        var enc = try goose.message.BodyEncoder.encode(alloc, GStr.new(self.name));
        defer enc.deinit();

        const serial = conn.serial_counter;
        conn.serial_counter += 1;

        const header = core.MessageHeader{
            .message_type = .MethodCall,
            .flags = 0x1,
            .proto_version = 1,
            .body_length = @intCast(enc.body().len),
            .serial = serial,
            .header_fields = @constCast(&[_]core.HeaderField{
                .{ .code = .Destination, .value = .{ .Destination = WATCHER_NAME } },
                .{ .code = .Path, .value = .{ .Path = WATCHER_PATH } },
                .{ .code = .Interface, .value = .{ .Interface = WATCHER_IFACE } },
                .{ .code = .Member, .value = .{ .Member = "RegisterStatusNotifierItem" } },
                .{ .code = .Signature, .value = .{ .Signature = enc.signature() } },
            }),
        };
        try conn.sendMessage(core.Message.new(header, enc.body()));
    }

    fn on_name_owner_changed(ctx: ?*anyopaque, msg: goose.core.Message) void {
        const self: *Tray = @ptrCast(@alignCast(ctx.?));
        var dec = goose.message.BodyDecoder.fromMessage(self.service.allocator, msg);
        _ = dec.decode(GStr) catch return;
        _ = dec.decode(GStr) catch return;
        const new_owner = dec.decode(GStr) catch return;
        if (new_owner.s.len == 0) return;
        std.debug.print("[tray] watcher reappeared; re-registering\n", .{});
        self.announce() catch |e| std.debug.print("[tray] re-register failed: {any}\n", .{e});
    }

    fn on_host_registered(ctx: ?*anyopaque, msg: goose.core.Message) void {
        const self: *Tray = @ptrCast(@alignCast(ctx.?));
        _ = msg;
        std.debug.print("[tray] new host registered; re-registering\n", .{});
        self.announce() catch |e| std.debug.print("[tray] re-register failed: {any}\n", .{e});
    }

    fn send_register(self: *Tray, conn: *goose.Connection) !void {
        const alloc = self.service.allocator;
        var enc = try goose.message.BodyEncoder.encode(alloc, GStr.new(self.name));
        defer enc.deinit();

        const serial = conn.serial_counter;
        conn.serial_counter += 1;

        const header = core.MessageHeader{
            .message_type = .MethodCall,
            .flags = 0x1,
            .proto_version = 1,
            .body_length = @intCast(enc.body().len),
            .serial = serial,
            .header_fields = @constCast(&[_]core.HeaderField{
                .{ .code = .Destination, .value = .{ .Destination = WATCHER_NAME } },
                .{ .code = .Path, .value = .{ .Path = WATCHER_PATH } },
                .{ .code = .Interface, .value = .{ .Interface = WATCHER_IFACE } },
                .{ .code = .Member, .value = .{ .Member = "RegisterStatusNotifierItem" } },
                .{ .code = .Signature, .value = .{ .Signature = enc.signature() } },
            }),
        };

        const msg = core.Message.new(header, enc.body());
        try conn.sendMessage(msg);
    }
};
