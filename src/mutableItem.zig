const std = @import("std");
const menus = @import("menu.zig");
const MenuItem = menus.MenuItem;
const ItemType = menus.ItemType;

const testing = std.testing;

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

test "init dupes the label and owns it" {
    var buf = [_]u8{ 'h', 'i' };
    var item = try MutableItem.init(testing.allocator, 1, &buf);
    defer item.deinit();

    buf[0] = 'X'; // mutate the original source
    try testing.expectEqualStrings("hi", item.label);
}

test "deinit frees label and children (no leak)" {
    var root = try MutableItem.init(testing.allocator, 0, "root");
    _ = try root.appendItem(1, "a");
    _ = try root.appendItem(2, "b");
    root.deinit();
}

test "appendItem adds a child and returns a usable pointer" {
    var root = try MutableItem.init(testing.allocator, 0, "root");
    defer root.deinit();

    const child = try root.appendItem(5, "child");
    try testing.expectEqual(@as(usize, 1), root.children.items.len);
    try testing.expectEqual(@as(i32, 5), child.id);
    try testing.expectEqualStrings("child", child.label);

    _ = try child.appendItem(6, "grandchild");
    try testing.expectEqual(@as(usize, 1), child.children.items.len);
}

test "appendSeparator sets the separator type" {
    var root = try MutableItem.init(testing.allocator, 0, "root");
    defer root.deinit();

    try root.appendSeparator(9);
    try testing.expectEqual(@as(usize, 1), root.children.items.len);
    try testing.expectEqual(ItemType.separator, root.children.items[0].type);
}

test "find locates self, nested, and returns null when missing" {
    var root = try MutableItem.init(testing.allocator, 0, "root");
    defer root.deinit();

    const a = try root.appendItem(1, "a");
    _ = try a.appendItem(2, "a-child");
    _ = try root.appendItem(3, "b");

    try testing.expect(root.find(0) != null); // self
    try testing.expectEqual(@as(i32, 2), root.find(2).?.id); // nested grandchild
    try testing.expectEqual(@as(i32, 3), root.find(3).?.id); // direct child
    try testing.expect(root.find(999) == null); // missing
}

test "remove deletes a leaf and frees its subtree" {
    var root = try MutableItem.init(testing.allocator, 0, "root");
    defer root.deinit();

    _ = try root.appendItem(1, "a");
    _ = try root.appendItem(2, "b");

    try testing.expect(root.remove(1));
    try testing.expectEqual(@as(usize, 1), root.children.items.len);
    try testing.expectEqual(@as(i32, 2), root.children.items[0].id);
}

test "remove works on a nested item" {
    var root = try MutableItem.init(testing.allocator, 0, "root");
    defer root.deinit();

    const a = try root.appendItem(1, "a");
    _ = try a.appendItem(10, "deep");

    try testing.expect(root.remove(10)); // remove the grandchild
    try testing.expectEqual(@as(usize, 0), root.find(1).?.children.items.len);
}

test "remove returns false when id not present" {
    var root = try MutableItem.init(testing.allocator, 0, "root");
    defer root.deinit();
    _ = try root.appendItem(1, "a");

    try testing.expect(!root.remove(42));
    try testing.expectEqual(@as(usize, 1), root.children.items.len);
}

test "clearChildren empties and frees all children" {
    var root = try MutableItem.init(testing.allocator, 0, "root");
    defer root.deinit();

    const a = try root.appendItem(1, "a");
    _ = try a.appendItem(2, "a-child");
    _ = try root.appendItem(3, "b");

    root.clearChildren();
    try testing.expectEqual(@as(usize, 0), root.children.items.len);
}

test "toMenuItem mirrors structure and labels" {
    var root = try MutableItem.init(testing.allocator, 0, "root");
    defer root.deinit();

    _ = try root.appendItem(1, "open");
    const more = try root.appendItem(2, "more");
    _ = try more.appendItem(3, "sub-a");
    _ = try more.appendItem(4, "sub-b");

    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const menu = try root.toMenuItem(arena);

    try testing.expectEqual(@as(i32, 0), menu.id);
    try testing.expectEqual(@as(usize, 2), menu.children.len);
    try testing.expectEqualStrings("open", menu.children[0].label);
    try testing.expectEqualStrings("more", menu.children[1].label);
    try testing.expectEqual(@as(usize, 2), menu.children[1].children.len);
    try testing.expectEqualStrings("sub-a", menu.children[1].children[0].label);
}

// Confirms that toMenu dupes into menu
test "toMenuItem snapshot is independent of later source mutation" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var menu_copy: @import("menu.zig").MenuItem = undefined;
    {
        var root = try MutableItem.init(testing.allocator, 0, "root");
        _ = try root.appendItem(1, "original");

        menu_copy = try root.toMenuItem(arena);

        // Mutate + free the source AFTER snapshotting.
        _ = root.remove(1);
        root.deinit();
    }
    // With the dupe fix, the arena snapshot still holds valid data.
    // (If toMenuItem borrows, this reads freed memory — UB, likely fails
    // under testing.allocator or a sanitizer.)
    try testing.expectEqualStrings("root", menu_copy.label);
    try testing.expectEqual(@as(usize, 1), menu_copy.children.len);
    try testing.expectEqualStrings("original", menu_copy.children[0].label);
}
