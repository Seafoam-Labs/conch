//A kde implementation for SNI tray menus.

const std = @import("std");
const goose = @import("goose");

const GStr = goose.core.value.GStr;
const DBusWriter = goose.core.value.DBusWriter;
const Connection = goose.Connection;
const Service = @import("service.zig").Service;

pub const ItemType = enum {
    normal,
    separator,

    fn wire(self: ItemType) []const u8 {
        return switch (self) {
            .normal => "standard",
            .separator => "separator",
        };
    }
};

pub const MenuItem = struct {
    id: i32,
    label: []const u8 = "",
    type: ItemType = .normal,
    enabled: bool = true,
    visible: bool = true,
    children: []const MenuItem = &.{},

    pub fn isSubmenu(self: MenuItem) bool {
        return self.children.len > 0;
    }
};

pub const Tree = struct {
    root: MenuItem,

    pub fn find(self: *const Tree, id: i32) ?*const MenuItem {
        return find_in(&self.root, id);
    }

    fn find_in(item: *const MenuItem, id: i32) ?*const MenuItem {
        if (item.id == id) return item;
        for (item.children) |*child| {
            if (find_in(child, id)) |res| return res;
        }
        return null;
    }
};

fn hashItem(h: *std.hash.Wyhash, item: *const MenuItem) void {
    h.update(std.mem.asBytes(&item.id));
    const label_len: u64 = item.label.len;
    h.update(std.mem.asBytes(&label_len));
    h.update(item.label);
    h.update(&[_]u8{@intFromEnum(item.type)});
    h.update(&[_]u8{@intFromBool(item.enabled)});
    h.update(&[_]u8{@intFromBool(item.visible)});
    for (item.children) |*child| {
        hashItem(h, child);
    }
}

pub fn menuHash(root: *const MenuItem) u64 {
    var h = std.hash.Wyhash.init(0);
    hashItem(&h, root);
    return h.final();
}

pub const LayoutValue = struct {
    item: *const MenuItem,
    depth: i32,

    pub const SIGNATURE: [:0]const u8 = "(ia{sv}av)";

    pub fn ser(self: LayoutValue, w: *DBusWriter) !void {
        try write_item(w, self.item, self.depth);
    }
};

pub const BuilderFn = *const fn (ctx: ?*anyopaque, arena: std.mem.Allocator) anyerror!Tree;

pub const EventFn = *const fn (ctx: ?*anyopaque, id: i32) void;

pub const GroupPropsValue = struct {
    state: *MenuState,
    ids: []const i32,
    pub const SIGNATURE: [:0]const u8 = "a(ia{sv})";
    pub fn ser(self: GroupPropsValue, w: *DBusWriter) !void {
        try w.padTo(4);
        const len_pos = w.buffer.items.len;
        try w.buffer.appendNTimes(w.gpa, 0, 4);
        try w.padTo(8);
        const start = w.buffer.items.len;
        const root = try self.state.buildTree();
        _ = root;
        for (self.ids) |id| {
            const item = self.state.current_tree.find(id) orelse continue;
            try w.padTo(8);
            try w.writeInt(i32, item.id);
            try write_props(w, item);
        }
        const arr_bytes: u32 = @intCast(w.buffer.items.len - start);
        w.writeU32At(len_pos, arr_bytes);
    }
};

pub const EventGroupResult = struct {
    failed: []const i32 = &.{},
    pub const SIGNATURE: [:0]const u8 = "ai";
    pub fn ser(self: EventGroupResult, w: *DBusWriter) !void {
        try w.padTo(4);
        const len_pos = w.buffer.items.len;
        try w.buffer.appendNTimes(w.gpa, 0, 4);
        try w.padTo(4);
        const start = w.buffer.items.len;
        for (self.failed) |id| try w.writeInt(i32, id);
        const arr_bytes: u32 = @intCast(w.buffer.items.len - start);
        w.writeU32At(len_pos, arr_bytes);
    }
};

pub const AboutToShowGroupResult = struct {
    pub const SIGNATURE: [:0]const u8 = "aiai";
    pub fn ser(self: AboutToShowGroupResult, w: *DBusWriter) !void {
        _ = self;

        try w.padTo(4);
        try w.writeInt(u32, 0);
        try w.padTo(4);
        try w.writeInt(u32, 0);
    }
};

pub const MenuState = struct {
    builder: BuilderFn,
    on_event: ?EventFn = null,
    ctx: ?*anyopaque = null,
    arena: std.heap.ArenaAllocator,
    revision: u32 = 0,
    path: []const u8 = "/MenuBar",
    current_tree: Tree = undefined,
    delivered_hash: ?u64 = null,

    pub fn init(backing: std.mem.Allocator, builder: BuilderFn) MenuState {
        return .{
            .builder = builder,
            .arena = std.heap.ArenaAllocator.init(backing),
        };
    }

    pub fn deinit(self: *MenuState) void {
        self.arena.deinit();
    }

    fn buildTree(self: *MenuState) anyerror!*const MenuItem {
        _ = self.arena.reset(.retain_capacity);
        self.current_tree = try self.builder(self.ctx, self.arena.allocator());
        return &self.current_tree.root;
    }

    fn markDelivered(self: *MenuState, root: *const MenuItem, whole: bool) void {
        self.delivered_hash = if (whole) menuHash(root) else null;
    }

    pub fn refreshIfChanged(self: *MenuState) anyerror!bool {
        const root = try self.buildTree();
        const hash = menuHash(root);
        if (self.delivered_hash) |known| {
            if (known == hash) return false;
        }

        self.delivered_hash = hash;
        self.revision += 1;
        return true;
    }
};

pub const Menu = struct {
    conn: *Connection,
    state: *MenuState,
    Version: goose.Property(u32, .Read) = goose.property(u32, .Read, 3),
    TextDirection: goose.Property(GStr, .Read) = goose.property(GStr, .Read, GStr.new("ltr")),
    Status: goose.Property(GStr, .Read) = goose.property(GStr, .Read, GStr.new("normal")),

    pub const INTERFACE_NAME = "com.canonical.dbusmenu";

    pub fn init(conn: *Connection, st: *MenuState) @This() {
        return .{ .conn = conn, .state = st };
    }

    pub fn GetLayout(self: *@This(), parent_id: i32, recursion_depth: i32, property_names: []const GStr) !LayoutReturn {
        _ = property_names;
        const root = try self.state.buildTree();
        self.state.markDelivered(root, parent_id == 0 and recursion_depth < 0);

        const item = if (parent_id == 0) root else self.state.current_tree.find(parent_id) orelse root;
        return .{
            .revision = self.state.revision,
            .layout = .{ .item = item, .depth = recursion_depth },
        };
    }

    pub const EventData = union(enum) {
        i: i32,
        s: GStr,
    };

    pub fn Event(self: *@This(), id: i32, event_id: GStr, data: EventData, timestamp: u32) !void {
        _ = data;
        _ = timestamp;
        if (std.mem.eql(u8, event_id.s, "clicked")) {
            if (self.state.on_event) |cb| cb(self.state.ctx, id);
        }
    }

    pub fn GetGroupProperties(
        self: *@This(),
        ids: []const i32,
        property_names: []const GStr,
    ) !GroupPropsValue {
        _ = property_names;
        return .{ .state = self.state, .ids = ids };
    }

    pub fn AboutToShow(self: *@This(), id: i32) !bool {
        _ = id;
        return self.state.refreshIfChanged();
    }

    pub const GroupEvent = struct {
        id: i32,
        event_id: GStr,
        data: EventData,
        timestamp: u32,
    };

    pub fn EventGroup(self: *@This(), events: []const GroupEvent) !EventGroupResult {
        for (events) |ev| {
            if (std.mem.eql(u8, ev.event_id.s, "clicked")) {
                if (self.state.on_event) |cb| cb(self.state.ctx, ev.id);
            }
        }
        return .{};
    }

    pub fn AboutToShowGroup(self: *@This(), ids: []const i32) !AboutToShowGroupResult {
        _ = self;
        _ = ids;
        return .{};
    }
};

pub const LayoutReturn = struct {
    revision: u32,
    layout: LayoutValue,

    pub const SIGNATURE: [:0]const u8 = "u(ia{sv}av)";

    pub fn ser(self: LayoutReturn, w: *DBusWriter) !void {
        try w.padTo(4);
        try w.writeInt(u32, self.revision);
        try self.layout.ser(w);
    }
};

pub const MenuController = struct {
    service: *Service,
    state: *MenuState,
    name: [:0]const u8,
    path: [:0]const u8,

    pub fn init(svc: *Service, state: *MenuState, name: [:0]const u8, path: [:0]const u8) MenuController {
        state.path = path;
        return .{ .service = svc, .state = state, .name = name, .path = path };
    }

    pub fn register(self: *MenuController) !void {
        const conn = self.service.connection();
        try conn.registerObject(Menu, self.name, self.path, self.state);
    }

    pub fn invalidate(self: *MenuController) !void {
        self.state.revision += 1;
        const conn = self.service.connection();
        const alloc = self.service.allocator;

        var enc = try goose.message.BodyEncoder.encode(alloc, .{
            @as(u32, self.state.revision),
            @as(i32, 0),
        });
        defer enc.deinit();

        const serial = conn.nextSerial();
        const header = goose.core.MessageHeader{
            .message_type = .Signal,
            .flags = 0x1,
            .proto_version = 1,
            .body_length = @intCast(enc.body().len),
            .serial = serial,
            .header_fields = @constCast(&[_]goose.core.HeaderField{
                .{ .code = .Path, .value = .{ .Path = self.path } },
                .{ .code = .Interface, .value = .{ .Interface = "com.canonical.dbusmenu" } },
                .{ .code = .Member, .value = .{ .Member = "LayoutUpdated" } },
                .{ .code = .Signature, .value = .{ .Signature = enc.signature() } },
            }),
        };
        try conn.sendMessage(goose.core.Message.new(header, enc.body()));
    }
};

fn write_item(w: *DBusWriter, item: *const MenuItem, depth: i32) anyerror!void {
    try w.padTo(8);
    try w.writeInt(i32, item.id);
    try write_props(w, item);
    try write_children(w, item, depth);
}

fn write_props(w: *DBusWriter, item: *const MenuItem) !void {
    try w.padTo(4);
    const len_pos = w.buffer.items.len;
    try w.buffer.appendNTimes(w.gpa, 0, 4);

    try w.padTo(8);
    const start = w.buffer.items.len;

    if (item.id != 0) {
        if (item.type == .separator) {
            try write_str_variant_entry(w, "type", "separator");
        } else {
            try write_str_variant_entry(w, "type", "standard");
            try write_str_variant_entry(w, "label", item.label);
            try write_bool_variant_entry(w, "enabled", item.enabled);
            try write_bool_variant_entry(w, "visible", item.visible);
            if (item.isSubmenu()) {
                try write_str_variant_entry(w, "children-display", "submenu");
            }
        }
    }

    const arr_bytes: u32 = @intCast(w.buffer.items.len - start);
    w.writeU32At(len_pos, arr_bytes);
}

fn write_children(w: *DBusWriter, item: *const MenuItem, depth: i32) anyerror!void {
    try w.padTo(4);
    const len_pos = w.buffer.items.len;
    try w.buffer.appendNTimes(w.gpa, 0, 4);

    try w.padTo(1);
    const start = w.buffer.items.len;

    if (depth != 0) {
        const next: i32 = if (depth < 0) -1 else depth - 1;
        for (item.children) |*child| {
            try write_layout_variant(w, child, next);
        }
    }

    const arr_bytes: u32 = @intCast(w.buffer.items.len - start);
    w.writeU32At(len_pos, arr_bytes);
}

fn write_layout_variant(w: *DBusWriter, item: *const MenuItem, depth: i32) anyerror!void {
    const sig = "(ia{sv}av)";
    try w.padTo(1);
    try w.buffer.append(w.gpa, @as(u8, @intCast(sig.len)));
    try w.buffer.appendSlice(w.gpa, sig);
    try w.buffer.append(w.gpa, 0);
    try write_item(w, item, depth);
}

fn write_str_variant_entry(w: *DBusWriter, key: []const u8, val: []const u8) !void {
    try w.padTo(8);
    try write_str(w, key);
    try w.buffer.append(w.gpa, 1);
    try w.buffer.append(w.gpa, 's');
    try w.buffer.append(w.gpa, 0);
    try write_str(w, val);
}

fn write_bool_variant_entry(w: *DBusWriter, key: []const u8, val: bool) !void {
    try w.padTo(8);
    try write_str(w, key);
    try w.buffer.append(w.gpa, 1);
    try w.buffer.append(w.gpa, 'b');
    try w.buffer.append(w.gpa, 0);
    try w.padTo(4);
    try w.writeInt(u32, if (val) 1 else 0);
}

fn write_str(w: *DBusWriter, str: []const u8) !void {
    try w.padTo(4);
    try w.writeInt(u32, @intCast(str.len));
    try w.buffer.appendSlice(w.gpa, str);
    try w.buffer.append(w.gpa, 0);
}

test "Tree.find locates nested items" {
    const tree = Tree{
        .root = .{
            .id = 0,
            .children = &.{
                .{ .id = 1, .label = "Open" },
                .{ .id = 2, .label = "More", .children = &.{
                    .{ .id = 3, .label = "Nested" },
                } },
            },
        },
    };
    try std.testing.expect(tree.find(3) != null);
    try std.testing.expectEqualStrings("Nested", tree.find(3).?.label);
    try std.testing.expect(tree.find(99) == null);
}

const DBusWriter_test = goose.core.value.DBusWriter;

fn serializeTree(alloc: std.mem.Allocator, item: *const MenuItem, depth: i32) !std.ArrayList(u8) {
    var buf = std.ArrayList(u8).empty;
    var w = DBusWriter_test.init(&buf, alloc, .little);
    const lv = LayoutValue{ .item = item, .depth = depth };
    try lv.ser(&w);
    return buf;
}

fn containsBytes(haystack: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, haystack, needle) != null;
}

test "serialize leaf: id at offset 0, label present" {
    const alloc = std.testing.allocator;
    const leaf = MenuItem{ .id = 1, .label = "Open" };
    var buf = try serializeTree(alloc, &leaf, 0);
    defer buf.deinit(alloc);

    // id = 1, little-endian i32 at the very start
    try std.testing.expect(buf.items.len >= 4);
    try std.testing.expectEqual(@as(u8, 1), buf.items[0]);
    try std.testing.expectEqual(@as(u8, 0), buf.items[1]);
    try std.testing.expectEqual(@as(u8, 0), buf.items[2]);
    try std.testing.expectEqual(@as(u8, 0), buf.items[3]);

    // property strings should appear verbatim
    try std.testing.expect(containsBytes(buf.items, "type"));
    try std.testing.expect(containsBytes(buf.items, "standard"));
    try std.testing.expect(containsBytes(buf.items, "label"));
    try std.testing.expect(containsBytes(buf.items, "Open"));
    try std.testing.expect(containsBytes(buf.items, "enabled"));
    try std.testing.expect(containsBytes(buf.items, "visible"));
}

test "serialize root with children at depth -1 includes child labels" {
    const alloc = std.testing.allocator;
    const root = MenuItem{
        .id = 0,
        .children = &.{
            .{ .id = 1, .label = "Open" },
            .{ .id = 2, .label = "Quit" },
        },
    };
    var buf = try serializeTree(alloc, &root, -1);
    defer buf.deinit(alloc);

    // root id 0 at start
    try std.testing.expectEqual(@as(u8, 0), buf.items[0]);
    // both children serialized (their labels appear)
    try std.testing.expect(containsBytes(buf.items, "Open"));
    try std.testing.expect(containsBytes(buf.items, "Quit"));
    // each child variant carries the recursive signature
    try std.testing.expect(containsBytes(buf.items, "(ia{sv}av)"));
}

test "depth 0 omits children" {
    const alloc = std.testing.allocator;
    const root = MenuItem{
        .id = 0,
        .children = &.{.{ .id = 1, .label = "Open" }},
    };
    var buf = try serializeTree(alloc, &root, 0);
    defer buf.deinit(alloc);

    // depth 0 -> children not recursed -> child label absent
    try std.testing.expect(!containsBytes(buf.items, "Open"));
}

fn testTreeFor(app_ignored: ?*anyopaque, arena: std.mem.Allocator) anyerror!Tree {
    _ = app_ignored;
    var items = std.ArrayList(MenuItem).empty;
    try items.append(arena, .{ .id = 1, .label = "Open" });
    try items.append(arena, .{ .id = 2, .label = "Quit" });
    return .{ .root = .{ .id = 0, .children = try items.toOwnedSlice(arena) } };
}

fn serializeGroupProps(alloc: std.mem.Allocator, state: *MenuState, ids: []const i32) !std.ArrayList(u8) {
    var buf = std.ArrayList(u8).empty;
    var w = DBusWriter.init(&buf, alloc, .little);
    const gpv = GroupPropsValue{ .state = state, .ids = ids };
    try gpv.ser(&w);
    return buf;
}

fn bytesContain(hay: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, hay, needle) != null;
}

test "separator emits type=separator and no label" {
    const alloc = std.testing.allocator;
    const sep = MenuItem{ .id = 5, .type = .separator };
    var buf = try serializeTree(alloc, &sep, 0);
    defer buf.deinit(alloc);

    try std.testing.expect(containsBytes(buf.items, "separator"));
    // separators carry no "label"/"enabled" keys
    try std.testing.expect(!containsBytes(buf.items, "enabled"));
}

test "array length words are non-zero when populated" {
    const alloc = std.testing.allocator;
    const leaf = MenuItem{ .id = 1, .label = "Open" };
    var buf = try serializeTree(alloc, &leaf, 0);
    defer buf.deinit(alloc);

    // props array length is the u32 at offset 4 (after the i32 id). A populated
    // props dict must have a non-zero byte length.
    const props_len = std.mem.readInt(u32, buf.items[4..8], .little);
    try std.testing.expect(props_len > 0);
}

test "GroupPropsValue: requested ids produce their props" {
    const alloc = std.testing.allocator;
    var state = MenuState.init(alloc, testTreeFor);
    defer state.deinit();

    var buf = try serializeGroupProps(alloc, &state, &.{ 1, 2 });
    defer buf.deinit(alloc);

    // outer array length word (first 4 bytes) must be non-zero
    const arr_len = std.mem.readInt(u32, buf.items[0..4], .little);
    try std.testing.expect(arr_len > 0);

    // both requested items' labels must appear
    try std.testing.expect(bytesContain(buf.items, "Open"));
    try std.testing.expect(bytesContain(buf.items, "Quit"));
    // and the property key
    try std.testing.expect(bytesContain(buf.items, "label"));
}

test "GroupPropsValue: unknown id is skipped, not crashed" {
    const alloc = std.testing.allocator;
    var state = MenuState.init(alloc, testTreeFor);
    defer state.deinit();

    // id 999 doesn't exist; id 1 does. Should emit only id 1's props.
    var buf = try serializeGroupProps(alloc, &state, &.{ 999, 1 });
    defer buf.deinit(alloc);

    try std.testing.expect(bytesContain(buf.items, "Open")); // id 1 present
    try std.testing.expect(!bytesContain(buf.items, "Quit")); // id 2 not requested
}

test "GroupPropsValue: empty id list yields empty array" {
    const alloc = std.testing.allocator;
    var state = MenuState.init(alloc, testTreeFor);
    defer state.deinit();

    var buf = try serializeGroupProps(alloc, &state, &.{});
    defer buf.deinit(alloc);

    // array length word should be 0 (no elements)
    const arr_len = std.mem.readInt(u32, buf.items[0..4], .little);
    try std.testing.expectEqual(@as(u32, 0), arr_len);
}

test "menuHash distinguishes every property a client renders" {
    const base = MenuItem{ .id = 1, .label = "Open" };
    const h = menuHash(&base);

    try std.testing.expectEqual(h, menuHash(&MenuItem{ .id = 1, .label = "Open" }));
    try std.testing.expect(h != menuHash(&MenuItem{ .id = 2, .label = "Open" }));
    try std.testing.expect(h != menuHash(&MenuItem{ .id = 1, .label = "Quit" }));
    try std.testing.expect(h != menuHash(&MenuItem{ .id = 1, .label = "Open", .enabled = false }));
    try std.testing.expect(h != menuHash(&MenuItem{ .id = 1, .label = "Open", .visible = false }));
    try std.testing.expect(h != menuHash(&MenuItem{ .id = 1, .label = "Open", .type = .separator }));
    try std.testing.expect(h != menuHash(&MenuItem{ .id = 1, .label = "Open", .children = &.{.{ .id = 2 }} }));
}

test "menuHash depends on nested content and child order, not allocation" {
    const ab = MenuItem{ .id = 0, .children = &.{
        .{ .id = 1, .label = "More", .children = &.{.{ .id = 3, .label = "Deep" }} },
        .{ .id = 2, .label = "Quit" },
    } };
    const ba = MenuItem{ .id = 0, .children = &.{
        .{ .id = 2, .label = "Quit" },
        .{ .id = 1, .label = "More", .children = &.{.{ .id = 3, .label = "Deep" }} },
    } };
    const deep_changed = MenuItem{ .id = 0, .children = &.{
        .{ .id = 1, .label = "More", .children = &.{.{ .id = 3, .label = "Deeper" }} },
        .{ .id = 2, .label = "Quit" },
    } };

    // A structurally equal tree built elsewhere hashes the same.
    const ab_copy = MenuItem{ .id = 0, .children = &.{
        .{ .id = 1, .label = "More", .children = &.{.{ .id = 3, .label = "Deep" }} },
        .{ .id = 2, .label = "Quit" },
    } };
    try std.testing.expectEqual(menuHash(&ab), menuHash(&ab_copy));
    try std.testing.expect(menuHash(&ab) != menuHash(&ba));
    try std.testing.expect(menuHash(&ab) != menuHash(&deep_changed));
}

const RefreshCase = struct {
    label: []const u8 = "Open",
    extra: bool = false,
};

fn refreshTreeFor(ctx: ?*anyopaque, arena: std.mem.Allocator) anyerror!Tree {
    const case: *const RefreshCase = @ptrCast(@alignCast(ctx));
    var items = std.ArrayList(MenuItem).empty;
    try items.append(arena, .{ .id = 1, .label = case.label });
    if (case.extra) {
        try items.append(arena, .{ .id = 2, .label = "Quit" });
    }
    return .{ .root = .{ .id = 0, .children = try items.toOwnedSlice(arena) } };
}

test "refreshIfChanged only reports an update when the rebuild differs" {
    const alloc = std.testing.allocator;
    var case: RefreshCase = .{};
    var state = MenuState.init(alloc, refreshTreeFor);
    defer state.deinit();
    state.ctx = &case;

    // Nothing has been delivered yet, so the client has to be told to fetch.
    try std.testing.expect(try state.refreshIfChanged());
    const revision = state.revision;

    // Rebuilding identical content must not ask for a refresh: that is what
    // made clients tear down the submenu the user had just opened.
    try std.testing.expect(!(try state.refreshIfChanged()));
    try std.testing.expect(!(try state.refreshIfChanged()));
    try std.testing.expectEqual(revision, state.revision);

    case.label = "Reopen";
    try std.testing.expect(try state.refreshIfChanged());
    try std.testing.expectEqual(revision + 1, state.revision);
    try std.testing.expect(!(try state.refreshIfChanged()));

    case.extra = true;
    try std.testing.expect(try state.refreshIfChanged());
    try std.testing.expectEqual(revision + 2, state.revision);
}

test "GetLayout records what the client received" {
    const alloc = std.testing.allocator;
    var case: RefreshCase = .{};
    var state = MenuState.init(alloc, refreshTreeFor);
    defer state.deinit();
    state.ctx = &case;

    var menu = Menu.init(@as(*Connection, undefined), &state);

    // A full fetch tells us exactly what the client holds.
    _ = try menu.GetLayout(0, -1, &.{});
    try std.testing.expect(!(try state.refreshIfChanged()));

    // A partial fetch does not, so we fall back to reporting an update.
    _ = try menu.GetLayout(0, 1, &.{});
    try std.testing.expect(try state.refreshIfChanged());
    try std.testing.expect(!(try state.refreshIfChanged()));

    _ = try menu.GetLayout(1, -1, &.{});
    try std.testing.expect(try state.refreshIfChanged());
}
