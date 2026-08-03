const std = @import("std");
const Io = std.Io;
const Service = @import("conch").Service;
const Tray = @import("conch").Tray;
const MenuState = @import("conch").MenuState;
const MenuController = @import("conch").MenuController;
const Tree = @import("conch").Tree;
const MenuItem = @import("conch").MenuItem;

const ex_tray = @import("ex_tray");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    // Init a service
    var service = try Service.init(allocator, init.io, init.environ_map);
    defer service.deinit();

    // Aquire you singleton name
    const SINGLETON_NAME = "example.conch.com";

    if (try service.nameHasOwner(SINGLETON_NAME)) {
        std.process.exit(0);
    }
    try service.requestName(SINGLETON_NAME);

    // Create your tray icon
    var t = try Tray.init(&service, .{
        .id = "example.conch.com",
        .title = "Example Tray",
        .icon_name = "system-software-update-symbolic",
        .icon_pixmap = &.{},
    });
    defer t.deinit();
    _ = try t.register();

    var mstate = MenuState.init(allocator, buildMenu);
    defer mstate.deinit();
    // Call back for tray events
    mstate.on_event = onEvent;

    var menu_ctrl = MenuController.init(&service, &mstate, t.name, "/MenuBar");
    _ = try menu_ctrl.register();

    while (true) {
        _ = service.tickTimeout(.{
            .duration = .{
                .raw = .fromMilliseconds(250),
                .clock = .awake,
            },
        }) catch {};
    }
}

// Build a static menu layout
fn buildMenu(ctx: ?*anyopaque, arena: std.mem.Allocator) !Tree {
    var items = std.ArrayList(MenuItem).empty;
    _ = ctx;

    const item: MenuItem = .{ .id = 1, .label = "Log Hello", .enabled = true, .visible = true, .type = .normal };
    try items.append(arena, item);
    const item_with_children: MenuItem = .{ .id = 2, .label = "Hello", .enabled = true, .visible = true, .type = .normal, .children = &.{
        .{ .id = 3, .label = "Log World", .enabled = true, .visible = true, .type = .normal },
    } };
    try items.append(arena, item_with_children);

    return .{ .root = .{ .id = 0, .children = try items.toOwnedSlice(arena) } };
}

fn onEvent(ctx: ?*anyopaque, id: i32) void {
    _ = ctx;
    if (id == 1) {
        std.log.info("Log Hello", .{});
    }

    if (id == 3) {
        std.log.info("Log World", .{});
    }
}
