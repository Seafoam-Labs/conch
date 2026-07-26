const std = @import("std");
const goose = @import("goose");

const GStr = goose.core.value.GStr;
const Connection = goose.Connection;

pub const SNI_INTERFACE = "org.kde.StatusNotifierItem";

pub const Config = struct {
    id: [:0]const u8,
    title: [:0]const u8,
    icon_name: [:0]const u8,
    status: [:0]const u8 = "Active",
    category: [:0]const u8 = "ApplicationStatus",
};

pub const Item = struct {
    conn: *Connection,

    Category: goose.Property(GStr, .Read) = goose.property(GStr, .Read, GStr.new("ApplicationStatus")),
    Id: goose.Property(GStr, .Read) = goose.property(GStr, .Read, GStr.new("")),
    Title: goose.Property(GStr, .Read) = goose.property(GStr, .Read, GStr.new("")),
    Status: goose.Property(GStr, .Read) = goose.property(GStr, .Read, GStr.new("Active")),
    IconName: goose.Property(GStr, .Read) = goose.property(GStr, .Read, GStr.new("")),
    Menu: goose.Property(GStr, .Read) = goose.property(GStr, .Read, GStr.new("/")),

    pub const INTERFACE_NAME = SNI_INTERFACE;

    pub fn init(conn: *Connection, config: *const Config) @This() {
        return Item{
            .conn = conn,
            .Category = goose.property(GStr, .Read, GStr.new(config.category)),
            .Id = goose.property(GStr, .Read, GStr.new(config.id)),
            .Title = goose.property(GStr, .Read, GStr.new(config.title)),
            .Status = goose.property(GStr, .Read, GStr.new(config.status)),
            .IconName = goose.property(GStr, .Read, GStr.new(config.icon_name)),
            .Menu = goose.property(GStr, .Read, GStr.new("/")),
        };
    }

    pub fn Activate(self: *@This(), x: i32, y: i32) !void {
        _ = self;
        _ = x;
        _ = y;
        std.debug.print("[sni] Activate\n", .{});
    }

    pub fn SecondaryActivate(self: *@This(), x: i32, y: i32) !void {
        _ = self;
        _ = x;
        _ = y;
        std.debug.print("[sni] SecondaryActivate\n", .{});
    }

    pub fn ContextMenu(self: *@This(), x: i32, y: i32) !void {
        _ = self;
        _ = x;
        _ = y;
        std.debug.print("[sni] ContextMenu\n", .{});
    }
};
