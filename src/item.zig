const std = @import("std");
const goose = @import("goose");

const GStr = goose.core.value.GStr;
const Connection = goose.Connection;
const GPath = goose.core.value.GPath;

pub const SNI_INTERFACE = "org.kde.StatusNotifierItem";

/// SNI item status. Active = normal, Passive = de-emphasized/hidden by some
/// hosts, NeedsAttention = urgent (hosts highlight/animate the icon).
pub const Status = enum {
    active,
    passive,
    needs_attention,

    pub fn wire(self: Status) [:0]const u8 {
        return switch (self) {
            .active => "Active",
            .passive => "Passive",
            .needs_attention => "NeedsAttention",
        };
    }
};

pub const ScrollDirection = enum {
    up,
    down,
};

pub const Pixmap = struct {
    width: i32,
    height: i32,
    data: []const u8,
};

pub const ToolTip = struct {
    standard_title: []const u8 = "",
    standard_description: []const u8 = "",
    standard_icon: []const u8 = "",
    alternate_title: []const u8 = "",
    alternate_description: []const u8 = "",
};

pub const Config = struct {
    id: [:0]const u8,
    title: [:0]const u8,
    icon_name: [:0]const u8,
    status: [:0]const u8 = "Active",
    category: [:0]const u8 = "ApplicationStatus",
    icon_theme_path: [:0]const u8 = "",
    icon_pixmap: []const Pixmap = &.{},
    tool_tip: ?ToolTip = null,
    attention_icon_name: [:0]const u8 = "",
    user_ctx: ?*anyopaque = null,
    on_activate: ?ActivateFn = null,
    on_secondary_activate: ?SecondaryActivateFn = null,
    on_context_menu: ?ContextMenuFn = null,
    on_xdg_activation_token: ?XdgActivationTokenFn = null,
};

pub const XdgActivationTokenFn = *const fn (ctx: ?*anyopaque, token: []const u8) void;
pub const ActivateFn = *const fn (ctx: ?*anyopaque, x: i32, y: i32) void;
pub const SecondaryActivateFn = *const fn (ctx: ?*anyopaque, x: i32, y: i32) void;
pub const ContextMenuFn = *const fn (ctx: ?*anyopaque, x: i32, y: i32) void;

pub const Item = struct {
    conn: *Connection,
    cfg: *const Config,
    Category: goose.Property(GStr, .Read),
    Id: goose.Property(GStr, .Read),
    Title: goose.Property(GStr, .Read),
    Status: goose.Property(GStr, .Read),
    IconName: goose.Property(GStr, .Read),
    IconThemePath: goose.Property(GStr, .Read),
    Menu: goose.Property(GPath, .Read),
    AttentionIconName: goose.Property(GStr, .Read) = goose.property(GStr, .Read, GStr.new("")),
    ItemIsMenu: goose.Property(bool, .Read) = goose.property(bool, .Read, false),

    NewIcon: goose.Signal(void) = goose.signal("NewIcon", void),
    NewAttentionIcon: goose.Signal(void) = goose.signal("NewAttentionIcon", void),
    NewOverlayIcon: goose.Signal(void) = goose.signal("NewOverlayIcon", void),
    NewToolTip: goose.Signal(void) = goose.signal("NewToolTip", void),
    NewTitle: goose.7 = goose.signal("NewTitle", void),
    NewStatus: goose.Signal(GStr) = goose.signal("NewStatus", GStr),
    IconPixmap: goose.Property([]const Pixmap, .Read),

    pub const INTERFACE_NAME = SNI_INTERFACE;

    pub fn init(conn: *Connection, config: *const Config) @This() {
        return Item{
            .conn = conn,
            .cfg = config,
            .Category = goose.property(GStr, .Read, GStr.new(config.category)),
            .Id = goose.property(GStr, .Read, GStr.new(config.id)),
            .Title = goose.property(GStr, .Read, GStr.new(config.title)),
            .Status = goose.property(GStr, .Read, GStr.new(config.status)),
            .IconName = goose.property(GStr, .Read, GStr.new(config.icon_name)),
            .IconThemePath = goose.property(GStr, .Read, GStr.new(config.icon_theme_path)),
            .Menu = goose.property(GPath, .Read, GPath.new("/MenuBar")),
            .AttentionIconName = goose.property(GStr, .Read, GStr.new(config.attention_icon_name)),
            .ItemIsMenu = goose.property(bool, .Read, false),
            .NewIcon = goose.signal("NewIcon", void),
            .NewAttentionIcon = goose.signal("NewAttentionIcon", void),
            .NewOverlayIcon = goose.signal("NewOverlayIcon", void),
            .NewToolTip = goose.signal("NewToolTip", void),
            .NewTitle = goose.signal("NewTitle", void),
            .NewStatus = goose.signal("NewStatus", GStr),
            .IconPixmap = goose.property([]const Pixmap, .Read, config.icon_pixmap),
        };
    }

    pub fn Activate(self: *@This(), x: i32, y: i32) !void {
        if (self.cfg.on_activate) |cb| {
            cb(self.cfg.user_ctx, x, y);
        }
    }

    pub fn SecondaryActivate(self: *@This(), x: i32, y: i32) !void {
        if (self.cfg.on_secondary_activate) |cb| {
            cb(self.cfg.user_ctx, x, y);
        }
    }

    pub fn ContextMenu(self: *@This(), x: i32, y: i32) !void {
        if (self.cfg.on_context_menu) |cb| {
            cb(self.cfg.user_ctx, x, y);
        }
    }

    pub fn ProvideXdgActivationToken(self: *@This(), token: GStr) !void {
        if (self.cfg.on_xdg_activation_token) |cb| {
            cb(self.cfg.user_ctx, token.s);
        }
    }
};
