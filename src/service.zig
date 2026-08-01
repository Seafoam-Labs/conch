const std = @import("std");
const goose = @import("goose");
const GStr = goose.core.value.GStr;

const Connection = goose.Connection;

const PlatformDataValue = union(enum) {
    s: GStr,
};

pub const SignalHandlerFn = *const fn (ctx: ?*anyopaque, msg: goose.core.Message) void;

pub const Service = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    conn: Connection,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, env_map: *std.process.Environ.Map) !Service {
        const conn = try Connection.init(allocator, .Session, io, env_map);
        return .{
            .allocator = allocator,
            .io = io,
            .conn = conn,
        };
    }

    pub fn deinit(self: *Service) void {
        self.conn.close();
    }

    pub fn connection(self: *Service) *Connection {
        return &self.conn;
    }

    pub fn run(self: *Service, handle: usize) !void {
        try self.conn.waitOnHandle(handle);
    }

    pub fn dispatchOne(self: *Service) !void {
        var msg = try self.conn.waitMessage();
        self.conn.freeMessage(&msg);
    }

    pub fn waitMessageTimeout(self: *Service, timeout: std.Io.Timeout) !?goose.core.Message {
        return self.conn.waitMessageTimeout(timeout);
    }

    pub fn tickTimeout(self: *Service, timeout: std.Io.Timeout) !bool {
        return self.conn.tickTimeout(timeout);
    }

    pub fn runEventLoop(self: *Service, comptime tick_ms: u64, ctx: anytype, comptime onTick: fn (@TypeOf(ctx)) void) !void {
        while (true) {
            _ = try self.tickTimeout(.{ .duration = .fromMillis(tick_ms) });
            onTick(ctx);
        }
    }

    pub fn processNext(self: *Service) !void {
        while (true) try self.dispatchOne();
    }

    pub fn activateApplication(
        self: *Service,
        app_name: [:0]const u8,
        app_path: [:0]const u8,
        token: ?[:0]const u8,
    ) !void {
        const conn = &self.conn;
        const alloc = self.allocator;
        const Variant = goose.core.value.Value.Variant(PlatformDataValue);
        const Dict = goose.core.value.Value.Dict(GStr, Variant, std.StringHashMap(Variant));
        var map = std.StringHashMap(Variant).init(alloc);
        defer map.deinit();
        if (token) |t| {
            try map.put("activation-token", Variant.new(.{ .s = GStr.new(t) }));
        }
        var enc = try goose.message.BodyEncoder.encode(alloc, Dict.new(map));
        defer enc.deinit();
        var reply = try conn.methodCall(
            app_name,
            app_path,
            "org.freedesktop.Application",
            "Activate",
            enc.signature(),
            enc.body(),
        );
        defer conn.freeMessage(&reply);

        if (reply.header.message_type == .Error) {
            return error.ApplicationNotRunning;
        }
    }

    pub fn getProcessId(self: *Service, bus_name: [:0]const u8) !u32 {
        const conn = &self.conn;
        const alloc = self.allocator;

        var enc = try goose.message.BodyEncoder.encode(alloc, GStr.new(bus_name));
        defer enc.deinit();

        var reply = try conn.methodCall(
            "org.freedesktop.DBus",
            "/org/freedesktop/DBus",
            "org.freedesktop.DBus",
            "GetConnectionUnixProcessID",
            enc.signature(),
            enc.body(),
        );
        defer conn.freeMessage(&reply);

        if (reply.header.message_type == .Error) {
            return error.NameNotOwned;
        }

        var dec = goose.message.BodyDecoder.fromMessage(alloc, reply);
        const pid = try dec.decode(u32);
        return pid;
    }

    /// Subscribe to a fire-and-forget signal from another application (e.g. the UI
    /// telling the tray to refresh). Wraps the addMatch + registerSignalHandler
    /// pair. The handler fires when the event loop dispatches the signal.
    pub fn onExternalSignal(
        self: *Service,
        interface: [:0]const u8,
        member: [:0]const u8,
        handler: SignalHandlerFn,
        ctx: ?*anyopaque,
    ) !void {
        const conn = &self.conn;
        const match = try std.fmt.allocPrintSentinel(self.allocator, "type='signal',interface='{s}',member='{s}'", .{ interface, member }, 0);
        defer self.allocator.free(match);
        try conn.addMatch(match);
        try conn.registerSignalHandler(interface, member, handler, ctx);
    }
};
