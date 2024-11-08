const std = @import("std");

const packages_url = "https://aur.archlinux.org/packages.gz";
const package_info_url = "https://aur.archlinux.org/rpc/v5/info?arg[]=";
const cache_filename = "packages.rua";
const cache_shelf_life = 4 * std.time.ns_per_day;

fn printUsage() !void {
    const stderr = std.io.getStdErr().writer();
    try stderr.print(
        \\Usage: rua [OPTION]
        \\Options are:
        \\list         - prints all AUR packagse to stdout
        \\info <pkg>   - prints information about AUR package
        \\
    , .{});
}

fn shouldRebuildCache(fd: *const std.fs.File) !bool {
    const stat = try fd.stat();
    const now = std.time.nanoTimestamp();
    const age = now - stat.mtime;
    return age > cache_shelf_life;
}

fn fromCache(alloc: std.mem.Allocator) []u8 {
    const dir = std.fs.cwd();
    const fd = try dir.openFile("list.gz", .{});
    const content = try fd.reader().readAllAlloc(alloc, 2e6);
    defer alloc.free(content);
    return content;
}

fn fetchPackages(alloc: std.mem.Allocator) ![]u8 {
    var client = std.http.Client{ .allocator = alloc };
    defer client.deinit();
    var buf = std.ArrayList(u8).init(alloc);
    defer buf.deinit();
    const result = try client.fetch(.{
        .method = .GET,
        .location = .{ .url = packages_url },
        .response_storage = .{ .dynamic = &buf },
    });

    if (result.status != .ok) {
        if (result.status.phrase()) |phrase| {
            std.log.err("Could not download package list: cause {s}", .{phrase});
        }
        return error.CouldNotDownload;
    }

    return try buf.toOwnedSlice();
}

const Modes = enum(u8) {
    INFO,
    LIST,
    ERROR,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    const stdout = std.io.getStdOut().writer();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    const mode: Modes = switch (args.len) {
        2 => m: {
            if (std.mem.eql(u8, "list", args[1])) {
                break :m .LIST;
            } else {
                break :m .ERROR;
            }
        },
        3 => m: {
            if (std.mem.eql(u8, "info", args[1])) {
                break :m .INFO;
            } else {
                break :m .ERROR;
            }
        },
        else => .ERROR,
    };

    switch (mode) {
        .ERROR => try printUsage(),
        .LIST => {
            const cache_path = (std.posix.getenv("XDG_CACHE_HOME") orelse "~/.cache");
            var dir = try std.fs.openDirAbsolute(cache_path, .{});
            defer dir.close();
            const fd = blk: {
                const file = dir.openFile(cache_filename, .{}) catch {
                    const new_file = try dir.createFile(cache_filename, .{
                        .read = true,
                    });
                    break :blk new_file;
                };
                break :blk file;
            };
            defer fd.close();
            if (try shouldRebuildCache(&fd)) {
                std.log.info("Fetching new packages from AUR.", .{});
                const new_content = try fetchPackages(alloc);
                defer alloc.free(new_content);
                try fd.writeAll(new_content);
                try stdout.print("{s}", .{new_content});
            } else {
                std.log.info("Reading from AUR cache.", .{});
                const content = try fd.reader().readAllAlloc(alloc, 2e6);
                defer alloc.free(content);
                try stdout.print("{s}", .{content});
            }
        },
        .INFO => {
            const package_name = args[2];
            const info_url = try std.fmt.allocPrint(alloc, "{s}{s}", .{
                package_info_url, package_name,
            });
            defer alloc.free(info_url);

            var client = std.http.Client{ .allocator = alloc };
            defer client.deinit();
            var buf = std.ArrayList(u8).init(alloc);
            defer buf.deinit();
            const result = try client.fetch(.{
                .method = .GET,
                .location = .{ .url = info_url },
                .response_storage = .{ .dynamic = &buf },
            });

            switch (result.status) {
                .ok => {},
                else => {
                    if (result.status.phrase()) |phrase| {
                        std.log.err("Could not download package list: {s}", .{phrase});
                    }
                    unreachable;
                },
            }
            try stdout.print("{s}", .{buf.items});
        },
    }
}
