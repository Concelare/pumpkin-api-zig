const std = @import("std");
const pumpkin = @import("pumpkin");
const cmd = pumpkin.cmd;
const msg = pumpkin.msg;
const menu = pumpkin.menu;

pub const std_options: std.Options = .{ .logFn = pumpkin.logFn };

const log = std.log.scoped(.example);

const Example = struct {
    pub const metadata: pumpkin.Metadata = .{
        .name = "pumpkin-plugin-example",
        .version = "0.1.0",
        .authors = &.{"You"},
        .description = "An example plugin in Zig.",
        .permissions = &.{ "fs.read.data", "fs.write.data" },
    };

    pub const events = .{
        .player_join_event = onJoin,
        .player_chat_event = .{ onChat, pumpkin.EventOptions{ .priority = .high } },
    };

    // /greet and /greet <targets>, /colors, /heal <target> [amount]
    pub const commands: []const cmd.Spec = &.{ .{
        .names = &.{ "greet", "hi" },
        .description = "Says hello.",
        .permission = "pumpkin-plugin-example:command.greet",
        .run = greetSender,
        .then = &.{
            .argument("targets", .players, .{ .run = greetTargets }),
        },
    }, .{
        .names = &.{"colors"},
        .description = "Opens a menu to pick a chat color.",
        .permission = "pumpkin-plugin-example:command.colors",
        .run = openColors,
    }, .{
        .names = &.{"heal"},
        .description = "Heals a player, fully or by the given amount.",
        .permission = "pumpkin-plugin-example:command.heal",
        .default = .{ .op = .two },
        .then = &.{
            .argument("target", .players, .{
                .run = cmd.typed(heal),
                .then = &.{.argument("amount", .{ .float = .{ 0.5, null } }, .{ .run = cmd.typed(heal) })},
            }),
        },
    } };

    var welcome: []const u8 = default_welcome;
    const default_welcome = "Welcome! Edit welcome.txt in the plugin's data folder to change this.";

    pub fn onLoad(ctx: pumpkin.Context) !void {
        menu.listen(ctx);
        welcome = try loadWelcome();
        log.info("Hello from Zig!", .{});
    }

    fn loadWelcome() ![]const u8 {
        const io = pumpkin.io();
        const dir = std.Io.Dir.cwd();
        const text = dir.readFileAlloc(io, "welcome.txt", pumpkin.abi.heap, .limited(4096)) catch |err| switch (err) {
            error.FileNotFound => {
                try dir.writeFile(io, .{ .sub_path = "welcome.txt", .data = default_welcome ++ "\n" });
                return default_welcome;
            },
            else => return err,
        };
        return std.mem.trim(u8, text, " \r\n");
    }

    fn onJoin(_: pumpkin.Server, ev: *pumpkin.EventData(.player_join_event)) void {
        log.info("{s} joined", .{ev.player.getName()});
        ev.join_message = msg.build(&.{
            .{ .text = "+ ", .color = .green, .bold = true },
            .{ .text = ev.player.getName(), .color = .yellow },
        });
        ev.player.sendSystemMessage(msg.plain(welcome), false);
    }

    fn onChat(_: pumpkin.Server, ev: *pumpkin.EventData(.player_chat_event)) void {
        if (std.mem.indexOf(u8, ev.message, "spoiler") != null) ev.cancelled = true;
    }

    fn greetSender(sender: cmd.Sender, _: pumpkin.Server, _: cmd.Args) cmd.Result {
        sender.sendMessage(msg.build(&.{
            .{ .text = "Hello from Zig! ", .color = .gold },
            .{ .text = "[again]", .color = .gray, .click = .{ .run_command = "/greet" }, .hover = "Runs /greet" },
        }));
        return cmd.ok(1);
    }

    fn heal(sender: cmd.Sender, _: pumpkin.Server, args: struct { target: pumpkin.Player, amount: ?f32 }) cmd.Result {
        const target = args.target;
        if (args.amount) |amount| target.heal(amount) else target.setHealth(target.getMaxHealth());
        sender.sendMessage(msg.fmt(.green, "{s} is at {d:.1} health.", .{ target.getName(), target.getHealth() }));
        return cmd.ok(1);
    }

    fn greetTargets(sender: cmd.Sender, _: pumpkin.Server, args: cmd.Args) cmd.Result {
        const targets = cmd.get(args, "targets", .players) orelse return cmd.fail("nobody to greet");
        for (targets) |target| {
            target.sendSystemMessage(msg.fmt(.aqua, "{s} says hello", .{sender.getName()}), false);
        }
        sender.sendMessage(msg.fmt(null, "Greeted {d} player(s).", .{targets.len}));
        return cmd.ok(@intCast(targets.len));
    }

    const colors = [_]struct { wool: []const u8, color: msg.Color }{
        .{ .wool = "minecraft:red_wool", .color = .red },
        .{ .wool = "minecraft:lime_wool", .color = .green },
        .{ .wool = "minecraft:light_blue_wool", .color = .aqua },
        .{ .wool = "minecraft:yellow_wool", .color = .yellow },
    };

    fn openColors(sender: cmd.Sender, _: pumpkin.Server, _: cmd.Args) cmd.Result {
        const player = sender.asPlayer() orelse return cmd.fail("only players can pick a color");
        var buttons: [colors.len]menu.Button = undefined;
        for (&buttons, colors, 0..) |*button, c, i| button.* = .{
            .slot = @intCast(10 + 2 * i),
            .icon = .{ .id = c.wool, .name = &.{.{ .text = @tagName(c.color), .color = c.color }} },
            .on_click = pickColor,
            .data = i,
        };
        menu.open(player, .{
            .title = &.{.{ .text = "Pick a color" }},
            .buttons = &buttons,
            .fill = .{ .id = "minecraft:gray_stained_glass_pane", .name = &.{} },
        });
        return cmd.ok(1);
    }

    fn pickColor(click: menu.Click) void {
        const c = colors[click.data];
        click.player.sendSystemMessage(msg.fmt(c.color, "You picked {s}.", .{@tagName(c.color)}), false);
    }
};

comptime {
    pumpkin.register(Example);
}
