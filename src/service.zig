const std = @import("std");
const goose = @import("goose");
const GStr = goose.core.value.GStr;

const Connection = goose.Connection;

const PlatformDataValue = union(enum) {
    s: GStr,
};

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
};
