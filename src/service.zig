const std = @import("std");
const goose = @import("goose");

const Connection = goose.Connection;

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

    /// Process one message: dispatch a matching signal to its handler, or return.
    /// This is the primitive; the caller decides how to drive it.
    pub fn dispatchOne(self: *Service) !void {
        var msg = try self.conn.waitMessage();
        self.conn.freeMessage(&msg);
    }

    /// `while (true) try tick();`. Most apps want their own loop instead.
    pub fn processNext(self: *Service) !void {
        while (true) try self.dispatchOne();
    }
};
