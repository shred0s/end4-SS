pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/*
 * Game mode: drops Hyprland's effects and turns on VRR while playing. The settings are applied at runtime with
 * `hyprctl eval` and undone with a config reload, so nothing is written to the config files. Follows the game
 * detection in Clips to turn itself on when a game window opens and off when it closes.
 */
Singleton {
    id: root

    property bool active: false
    property bool autoEnabled: false // Turned on for a game, so turn it off when the game closes
    property string game: ""

    // Applied on top of the config; a config reload brings the normal values back
    readonly property string luaConfig: `hl.config({
        animations = { enabled = false },
        decoration = {
            rounding = 0,
            blur = { enabled = false },
            shadow = { enabled = false },
            dim_inactive = false,
            active_opacity = 1,
            inactive_opacity = 1,
        },
        general = { gaps_in = 0, gaps_out = 0, border_size = 1, allow_tearing = true },
        misc = { vrr = 2 }, -- Fullscreen windows only
        render = { direct_scanout = 2 }, -- Windows that mark themselves as games only; 1 = every fullscreen window
    })`

    function load() {}

    // enable()/disable() are user actions, which take over from game detection until the next game
    function enable() {
        root.autoEnabled = false;
        root.apply();
    }
    function disable() {
        root.autoEnabled = false;
        root.restore();
    }
    function toggle() {
        if (root.active) root.disable();
        else root.enable();
    }

    function apply() {
        root.active = true;
        Quickshell.execDetached(["hyprctl", "eval", root.luaConfig]);
    }
    function restore() {
        root.active = false;
        Quickshell.execDetached(["hyprctl", "reload", "config-only"]);
    }

    function notify(title, body) {
        Quickshell.execDetached(["notify-send", title, body, "-a", "Game mode", "-i", "input-gaming", "-t", "4000"]);
    }

    // ---- Game detection ----
    Connections {
        target: Clips
        function onActiveGameChanged() {
            if (!Config.options.gameMode.autoForGames) return;
            if (Clips.activeGame) {
                if (root.active) return; // Already on, by hand or for the game before
                root.game = Clips.activeGame;
                root.autoEnabled = true;
                root.apply();
                root.notify(Translation.tr("Game mode on"),
                    Translation.tr("%1 · Effects off, VRR on").arg(root.game));
            } else if (root.autoEnabled) {
                root.autoEnabled = false;
                root.restore();
                root.notify(Translation.tr("Game mode off"), Translation.tr("%1 closed").arg(root.game));
            }
        }
    }

    // Shell settings are written to the Hyprland config, and the reload that follows would undo game mode
    Connections {
        target: HyprlandConfig
        function onReloaded() {
            if (root.active) Quickshell.execDetached(["hyprctl", "eval", root.luaConfig]);
        }
    }

    // Pick up game mode left on by a previous shell instance; animations are only off in game mode
    Process {
        running: true
        command: ["hyprctl", "getoption", "animations:enabled", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const option = JSON.parse(text);
                    if (!root.active) root.active = !(option.bool ?? option.int ?? true);
                } catch (e) {}
            }
        }
    }
}
