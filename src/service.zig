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
        const conn = try Connection.initWithBackend(allocator, .Session, io, env_map, .poll);
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

    pub fn dispatchOne(self: *Service) !bool {
        return self.conn.dispatch();
    }

    pub fn tickTimeout(self: *Service, timeout: std.Io.Timeout) !bool {
        const conn = &self.conn;
        if (!conn.hasDataToRead() and !try waitForReadable(conn.getFd(), timeout, self.io)) {
            return false;
        }

        var handled = false;
        while (try conn.dispatch()) handled = true;
        return handled;
    }

    pub fn runEventLoop(self: *Service, comptime tick_ms: u64, ctx: anytype, comptime onTick: fn (@TypeOf(ctx)) void) !void {
        const timeout: std.Io.Timeout = .{ .duration = .{
            .raw = .fromMilliseconds(tick_ms),
            .clock = .awake,
        } };
        while (true) {
            _ = try self.tickTimeout(timeout);
            onTick(ctx);
        }
    }

    pub fn processNext(self: *Service) !void {
        while (try self.dispatchOne()) {}
    }

    pub fn activateApplication(
        self: *Service,
        app_name: [:0]const u8,
        app_path: [:0]const u8,
        token: ?[:0]const u8,
    ) !void {
        const conn = &self.conn;
        const alloc = self.allocator;
        const GVariant = goose.core.value.GVariant;

        var map = std.StringHashMap(GVariant).init(alloc);

        if (token) |t| {
            const key = try alloc.dupe(u8, "activation-token");
            const val = GVariant{ .string = GStr.new(t) };
            try map.put(key, val);
        }

        var dict_variant = GVariant{ .dict = map };
        defer dict_variant.deinit(alloc);

        var enc = try goose.message.BodyEncoder.encode(alloc, dict_variant);
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

    pub fn requestName(self: *Service, name: [:0]const u8) !void {
        return self.conn.requestName(name);
    }

    pub fn nameHasOwner(self: *Service, name: [:0]const u8) !bool {
        const conn = &self.conn;
        const alloc = self.allocator;

        var enc = try goose.message.BodyEncoder.encode(alloc, GStr.new(name));
        defer enc.deinit();

        var reply = try conn.methodCall(
            "org.freedesktop.DBus",
            "/org/freedesktop/DBus",
            "org.freedesktop.DBus",
            "NameHasOwner",
            enc.signature(),
            enc.body(),
        );
        defer conn.freeMessage(&reply);

        if (reply.header.message_type == .Error) return error.NameCheckFailed;

        var dec = goose.message.BodyDecoder.fromMessage(alloc, reply);
        return try dec.decode(bool);
    }
};

/// Blocks until the bus socket is readable or `timeout` elapses. A `.none`
/// timeout waits indefinitely.
fn waitForReadable(fd: std.posix.fd_t, timeout: std.Io.Timeout, io: std.Io) !bool {
    const millis: i32 = if (timeout.toDurationFromNow(io)) |remaining|
        @intCast(std.math.clamp(remaining.raw.toMilliseconds(), 0, std.math.maxInt(i32)))
    else
        -1;

    var fds = [1]std.posix.pollfd{.{ .fd = fd, .events = std.posix.POLL.IN, .revents = 0 }};
    return try std.posix.poll(&fds, millis) > 0;
}
