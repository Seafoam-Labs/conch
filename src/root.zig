const std = @import("std");

pub const service = @import("service.zig");
pub const notifier = @import("notifier.zig");
pub const capabilities = @import("capabilities.zig");

pub const Service = service.Service;
pub const Notifier = notifier.Notifier;
pub const Notification = notifier.Notification;
pub const Capabilities = capabilities.Capabilities;

test {
    std.testing.refAllDecls(service);
    std.testing.refAllDecls(notifier);
    std.testing.refAllDecls(capabilities);
}
