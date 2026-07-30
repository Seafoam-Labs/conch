const std = @import("std");
const MenuItem = @import("MenuItem.zig");

pub const MutableItem = struct {
    allocator: std.mem.Allocator,
    id: i32,
    label: []const u8,
    type: ItemType = .normal,
    enabled: bool = true,
    visible: bool = true,
    children: std.ArrayList(MutableItem) = .empty,

    pub fn init(allocator: std.mem.Allocator, id: i32, label: []const u8) !MutableItem {
        return .{
            .allocator = allocator,
            .id = id,
            .label = try allocator.dupe(u8, label),
        };
    }

    pub fn deinit(self: *MutableItem) void {
        for (self.children.items) |*child| child.deinit();
        self.children.deinit(self.allocator);
        self.allocator.free(self.label);
    }

    pub fn appendItem(self: *MutableItem, id: i32, label: []const u8) !*MutableItem {
        try self.children.append(self.allocator, .{
            .allocator = self.allocator,
            .id = id,
            .label = try self.allocator.dupe(u8, label),
        });
        return &self.children.items[self.children.items.len - 1];
    }

    pub fn appendSeparator(self: *MutableItem, id: i32) !void {
        try self.children.append(self.allocator, .{
            .allocator = self.allocator,
            .id = id,
            .label = try self.allocator.dupe(u8, ""),
            .type = .separator,
        });
    }

    pub fn find(self: *MutableItem, id: i32) ?*MutableItem {
        if (self.id == id) return self;
        for (self.children.items) |*child| {
            if (child.find(id)) |found| return found;
        }
        return null;
    }

    pub fn remove(self: *MutableItem, id: i32) bool {
        for (self.children.items, 0..) |*child, idx| {
            if (child.id == id) {
                var removed = self.children.orderedRemove(idx);
                removed.deinit();
                return true;
            }
            if (child.remove(id)) return true;
        }
        return false;
    }

    pub fn clearChildren(self: *MutableItem) void {
        for (self.children.items) |*child| child.deinit();
        self.children.clearRetainingCapacity();
    }

    pub fn toMenuItem(self: *const MutableItem, arena: std.mem.Allocator) !MenuItem {
        var kids = std.ArrayList(MenuItem).empty;
        for (self.children.items) |*child| {
            try kids.append(arena, try child.toMenuItem(arena));
        }
        return .{
            .id = self.id,
            .label = try arena.dupe(u8, self.label),
            .type = self.type,
            .enabled = self.enabled,
            .visible = self.visible,
            .children = try kids.toOwnedSlice(arena),
        };
    }
};
