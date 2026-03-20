const std = @import("std");

/// OpenSSL C FFI bindings (unified cImport)
pub const c = @cImport({
    @cInclude("openssl/ssl.h");
    @cInclude("openssl/err.h");
    @cInclude("openssl/evp.h");
});

/// TLS Context wrapper for WSS connections
pub const TlsContext = struct {
    ctx: *c.SSL_CTX,
    ssl: ?*c.SSL = null,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !TlsContext {
        // Modern OpenSSL initialization (replaces SSL_library_init)
        _ = c.OPENSSL_init_ssl(0, null);

        // Create SSL context for TLS 1.2+
        const method = c.TLS_client_method() orelse return error.TlsInitFailed;

        const ctx = c.SSL_CTX_new(method) orelse return error.TlsContextCreationFailed;

        return TlsContext{
            .ctx = ctx,
            .ssl = null,
            .allocator = allocator,
        };
    }

    /// Connect to WSS endpoint with TLS
    pub fn connectWss(self: *TlsContext, socket_fd: std.posix.socket_t, hostname: [*:0]const u8) !void {
        // Create SSL connection object with explicit cast
        const ssl = c.SSL_new(self.ctx) orelse return error.TlsConnectionCreationFailed;

        self.ssl = ssl;

        // Attach socket to SSL
        if (c.SSL_set_fd(ssl, @intCast(socket_fd)) == 0) {
            return error.TlsSocketBindFailed;
        }

        // Set hostname for SNI (Server Name Indication)
        _ = c.SSL_set_tlsext_host_name(ssl, hostname);

        // Perform TLS handshake
        const ret = c.SSL_connect(ssl);
        if (ret <= 0) {
            const err = c.SSL_get_error(ssl, ret);
            std.debug.print("[TLS] Handshake error: {d}\n", .{err});
            return error.TlsHandshakeFailed;
        }

        std.debug.print("[TLS] Connected: {s} (TLS 1.2+)\n", .{hostname});
    }

    /// Send data over TLS
    pub fn send(self: *TlsContext, data: []const u8) !usize {
        const ssl = self.ssl orelse return error.TlsNotConnected;

        const written = c.SSL_write(ssl, data.ptr, @intCast(data.len));
        if (written <= 0) {
            return error.TlsWriteFailed;
        }

        return @intCast(written);
    }

    /// Receive data over TLS
    pub fn recv(self: *TlsContext, buffer: []u8) !usize {
        const ssl = self.ssl orelse return error.TlsNotConnected;

        const read = c.SSL_read(ssl, buffer.ptr, @intCast(buffer.len));
        if (read <= 0) {
            const err = c.SSL_get_error(ssl, read);
            if (err == c.SSL_ERROR_ZERO_RETURN) {
                return 0; // Connection closed gracefully
            }
            return error.TlsReadFailed;
        }

        return @intCast(read);
    }

    /// Close TLS connection
    pub fn close(self: *TlsContext) void {
        if (self.ssl) |ssl| {
            _ = c.SSL_shutdown(ssl);
            c.SSL_free(ssl);
            self.ssl = null;
        }
    }

    /// Cleanup TLS context
    pub fn deinit(self: *TlsContext) void {
        self.close();
        c.SSL_CTX_free(self.ctx);
        c.EVP_cleanup();
        c.ERR_free_strings();
    }
};
