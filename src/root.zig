const std = @import("std");

pub const service = @import("service.zig");
pub const notifier = @import("notifier.zig");
pub const capabilities = @import("capabilities.zig");
pub const tray = @import("tray.zig");
pub const item = @import("item.zig");
pub const menu = @import("menu.zig");

pub const Service = service.Service;
pub const Notifier = notifier.Notifier;
pub const Notification = notifier.Notification;
pub const Action = notifier.Action;
pub const ActionFn = notifier.ActionFn;
pub const ClosedFn = notifier.ClosedFn;
pub const ActivateFn = notifier.ActivateFn;
pub const Capabilities = capabilities.Capabilities;
pub const Tray = tray.Tray;
pub const Config = item.Config;
pub const Item = item.Item;
pub const Pixmap = item.Pixmap;
pub const ToolTip = item.ToolTip;
pub const ScrollDirection = item.ScrollDirection;
pub const Menu = menu.Menu;
pub const MenuItem = menu.MenuItem;
pub const MenuState = menu.MenuState;
pub const MenuController = menu.MenuController;
pub const Tree = menu.Tree;

test {
    std.testing.refAllDecls(service);
    std.testing.refAllDecls(notifier);
    std.testing.refAllDecls(capabilities);
    std.testing.refAllDecls(tray);
    std.testing.refAllDecls(item);
    std.testing.refAllDecls(menu);

    _ = Service;
    _ = Notifier;
    _ = Notification;
    _ = Capabilities;
    _ = Tray;
    _ = Item;
    _ = Config;
    _ = Menu;
}
