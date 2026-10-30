pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Item {
    id: root

    signal closeRequested()

    // Library state
    property string view: "all" // all, favorites, recent, game
    property string selectedGame: ""
    property string searchText: ""
    property list<string> selectedIds: []
    property var playingClip: null
    readonly property bool selectionMode: selectedIds.length > 0
    readonly property list<var> selectedClips: ClipLibrary.clips.filter(c => root.selectedIds.includes(c.id))
    readonly property var selectedGameInfo: ClipLibrary.games.find(g => g.name === root.selectedGame) ?? null

    readonly property list<var> sortOptions: [
        { displayName: Translation.tr("Newest"), value: "newest", icon: "arrow_downward" },
        { displayName: Translation.tr("Oldest"), value: "oldest", icon: "arrow_upward" },
        { displayName: Translation.tr("Longest"), value: "longest", icon: "timer" },
        { displayName: Translation.tr("Largest"), value: "largest", icon: "hard_drive" },
        { displayName: Translation.tr("Name"), value: "name", icon: "sort_by_alpha" },
    ]
    readonly property string sort: Persistent.states.clips.sort

    readonly property real weekAgo: Date.now() / 1000 - 7 * 86400
    readonly property int favoriteCount: ClipLibrary.clips.filter(c => c.favorite).length
    readonly property int recentCount: ClipLibrary.clips.filter(c => c.created >= root.weekAgo).length
    readonly property int driveCount: ClipLibrary.clips.filter(c => c.cloud).length
    readonly property string saveShortcut: root.shortcutLabel(Config.options.clips.shortcuts.save)

    readonly property list<var> visibleClips: {
        const query = root.searchText.trim().toLowerCase();
        const sorters = {
            newest: (a, b) => b.created - a.created,
            oldest: (a, b) => a.created - b.created,
            longest: (a, b) => (b.duration ?? 0) - (a.duration ?? 0),
            largest: (a, b) => b.size - a.size,
            name: (a, b) => a.name.localeCompare(b.name, undefined, { numeric: true }),
        };
        return ClipLibrary.clips.filter(c => {
            if (root.view === "favorites" && !c.favorite) return false;
            if (root.view === "recent" && c.created < root.weekAgo) return false;
            if (root.view === "drive" && !c.cloud) return false;
            if (root.view === "game" && c.game !== root.selectedGame) return false;
            if (query && !c.name.toLowerCase().includes(query) && !c.game.toLowerCase().includes(query)) return false;
            return true;
        }).sort(sorters[root.sort] ?? sorters.newest);
    }

    readonly property list<var> groups: {
        if (root.sort !== "newest" && root.sort !== "oldest")
            return [{ label: "", clips: root.visibleClips }];
        const result = [];
        for (const clip of root.visibleClips) {
            const label = root.dayLabel(clip.created);
            if (result.length === 0 || result[result.length - 1].label !== label)
                result.push({ label: label, clips: [] });
            result[result.length - 1].clips.push(clip);
        }
        return result;
    }

    function dayLabel(created) {
        const now = new Date();
        const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime() / 1000;
        if (created >= startOfToday) return Translation.tr("Today");
        if (created >= startOfToday - 86400) return Translation.tr("Yesterday");
        if (created >= startOfToday - 6 * 86400) return Translation.tr("This week");
        return Qt.formatDate(new Date(created * 1000), "MMMM yyyy");
    }

    function showView(view, game) {
        root.view = view;
        root.selectedGame = game ?? "";
        root.playingClip = null;
        root.selectedIds = [];
        libraryFlickable.contentY = 0;
    }
    function toggleSelected(id) {
        root.selectedIds = root.selectedIds.includes(id)
            ? root.selectedIds.filter(i => i !== id)
            : [...root.selectedIds, id];
    }
    function play(clip) {
        root.playingClip = clip;
    }
    // ---- Shortcuts ----
    // Hyprland (xkb) name of the pressed key, or "" for a modifier on its own
    function keyName(event) {
        const key = event.key;
        if ([Qt.Key_Control, Qt.Key_Shift, Qt.Key_Alt, Qt.Key_AltGr, Qt.Key_Meta, Qt.Key_Super_L, Qt.Key_Super_R,
             Qt.Key_Hyper_L, Qt.Key_Hyper_R, Qt.Key_CapsLock, Qt.Key_NumLock].includes(key)) return "";
        if ((key >= Qt.Key_A && key <= Qt.Key_Z) || (key >= Qt.Key_0 && key <= Qt.Key_9)) return String.fromCharCode(key);
        if (key >= Qt.Key_F1 && key <= Qt.Key_F35) return `F${key - Qt.Key_F1 + 1}`;
        const names = {
            [Qt.Key_Space]: "space", [Qt.Key_Return]: "Return", [Qt.Key_Enter]: "KP_Enter", [Qt.Key_Tab]: "Tab",
            [Qt.Key_Backspace]: "BackSpace", [Qt.Key_Delete]: "Delete", [Qt.Key_Insert]: "Insert",
            [Qt.Key_Home]: "Home", [Qt.Key_End]: "End", [Qt.Key_PageUp]: "Prior", [Qt.Key_PageDown]: "Next",
            [Qt.Key_Left]: "Left", [Qt.Key_Right]: "Right", [Qt.Key_Up]: "Up", [Qt.Key_Down]: "Down",
            [Qt.Key_Print]: "Print", [Qt.Key_Pause]: "Pause", [Qt.Key_ScrollLock]: "Scroll_Lock", [Qt.Key_Menu]: "Menu",
            [Qt.Key_Comma]: "comma", [Qt.Key_Period]: "period", [Qt.Key_Slash]: "slash", [Qt.Key_Backslash]: "backslash",
            [Qt.Key_Semicolon]: "semicolon", [Qt.Key_Apostrophe]: "apostrophe", [Qt.Key_BracketLeft]: "bracketleft",
            [Qt.Key_BracketRight]: "bracketright", [Qt.Key_Minus]: "minus", [Qt.Key_Equal]: "equal", [Qt.Key_QuoteLeft]: "grave",
            [Qt.Key_MediaPlay]: "XF86AudioPlay", [Qt.Key_MediaNext]: "XF86AudioNext", [Qt.Key_MediaPrevious]: "XF86AudioPrev",
        };
        if (names[key]) return names[key];
        return event.nativeScanCode > 0 ? `code:${event.nativeScanCode}` : ""; // Shifted symbols and the like
    }
    // "CTRL + SHIFT + F10" style combo for Hyprland. Plain keys only for ones that don't get in the way of typing.
    function shortcutFromEvent(event) {
        const key = root.keyName(event);
        if (!key) return "";
        const modifiers = [];
        if (event.modifiers & Qt.ControlModifier) modifiers.push("CTRL");
        if (event.modifiers & Qt.ShiftModifier) modifiers.push("SHIFT");
        if (event.modifiers & Qt.AltModifier) modifiers.push("ALT");
        if (event.modifiers & Qt.MetaModifier) modifiers.push("SUPER");
        if (modifiers.length === 0 && !/^(F\d+|Print|Pause|Scroll_Lock|Insert|XF86\w+)$/.test(key)) return "";
        return [...modifiers, key].join(" + ");
    }
    function shortcutLabel(combo) {
        const names = { CTRL: "Ctrl", SHIFT: "Shift", ALT: "Alt", SUPER: "Super", space: "Space", Prior: "Page Up",
            Next: "Page Down", Return: "Enter", KP_Enter: "Enter", grave: "`" };
        return (combo || "").split("+").map(part => part.trim()).filter(part => part.length > 0)
            .map(part => names[part] ?? (part.startsWith("code:") ? Translation.tr("Key %1").arg(part.slice(5)) : part.charAt(0).toUpperCase() + part.slice(1)))
            .join("+");
    }
    function setShortcut(name, combo) {
        const shortcuts = Config.options.clips.shortcuts;
        for (const other of ["save", "saveBuffer", "toggle", "openApp"]) { // One combo, one action
            if (other !== name && combo && shortcuts[other] === combo) shortcuts[other] = "";
        }
        shortcuts[name] = combo;
        ClipLibrary.applyShortcuts();
    }

    function requestDelete(ids) {
        deleteDialog.ids = ids;
        deleteDialog.open();
    }
    function requestRename(clip) {
        renameDialog.targetClip = clip;
        renameField.text = clip.name;
        renameDialog.open();
        renameField.forceActiveFocus();
        renameField.selectAll();
    }
    function requestMove(ids) {
        moveDialog.ids = ids;
        moveField.text = "";
        moveDialog.open();
        moveField.forceActiveFocus();
    }

    function openRequestedClip() {
        if (!ClipLibrary.requestedClipId) return;
        const clip = ClipLibrary.find(ClipLibrary.requestedClipId);
        if (!clip) return;
        ClipLibrary.requestedClipId = "";
        root.showView("all");
        root.play(clip);
    }

    readonly property string driveIcon: {
        if (!ClipLibrary.driveConnected) return "cloud_off";
        if (ClipLibrary.syncing) return "cloud_sync";
        if (ClipLibrary.syncStatus.error) return "sync_problem";
        return "cloud_done";
    }
    readonly property string driveSummary: {
        const status = ClipLibrary.syncStatus;
        if (!ClipLibrary.driveInstalled) return Translation.tr("Needs the proton-drive CLI");
        if (!ClipLibrary.driveConnected) return status.signedOut ? Translation.tr("Signed out, sign in again to sync") : Translation.tr("Sync clips between your devices");
        if (ClipLibrary.syncing) {
            const progress = Math.round((status.progress ?? 0) * 100);
            if (status.phase === "upload") return Translation.tr("Uploading “%1” · %2%").arg(status.name).arg(progress);
            if (status.phase === "download") return Translation.tr("Downloading “%1” · %2%").arg(status.name).arg(progress);
            return Translation.tr("Syncing…");
        }
        if (status.error) return Translation.tr("Sync failed: %1").arg(status.error);
        if (status.finished) return Translation.tr("Last synced: %1").arg(ClipLibrary.formatRelative(status.finished));
        return Translation.tr("Signed in");
    }

    // Keep the open clip pointing at fresh data (or close it if it's gone)
    Connections {
        target: ClipLibrary
        function onRequestedClipIdChanged() {
            root.openRequestedClip();
        }
        function onClipsChanged() {
            root.openRequestedClip();
            if (root.playingClip) {
                const fresh = ClipLibrary.find(root.playingClip.id);
                if (fresh) root.playingClip = fresh;
                else root.playingClip = null;
            }
            root.selectedIds = root.selectedIds.filter(id => ClipLibrary.clips.some(c => c.id === id));
            if (root.view === "game" && !ClipLibrary.games.some(g => g.name === root.selectedGame))
                root.showView("all");
        }
    }

    focus: true
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            if (root.selectionMode) root.selectedIds = [];
            else if (root.searchText.length > 0) searchField.text = "";
            else root.closeRequested();
        } else if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) {
            root.selectedIds = root.visibleClips.map(c => c.id);
        } else if (event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier)) {
            searchField.forceActiveFocus();
        } else if (event.key === Qt.Key_Delete && root.selectionMode) {
            root.requestDelete(root.selectedIds);
        } else if (event.key === Qt.Key_F5) {
            ClipLibrary.refresh();
            ClipLibrary.sync();
        } else {
            return;
        }
        event.accepted = true;
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 8

        // ================= Sidebar =================
        ColumnLayout {
            Layout.preferredWidth: 260
            Layout.maximumWidth: 260
            Layout.fillHeight: true
            visible: root.width >= 760 && !(root.playingClip && playerLoader.item?.theater)
            spacing: 4

            RowLayout {
                Layout.margins: 10
                Layout.bottomMargin: 6
                spacing: 10
                MaterialShapeWrappedMaterialSymbol {
                    text: "movie"
                    iconSize: 22
                    padding: 8
                    wrappedShape: MaterialShape.Shape.Cookie7Sided
                    color: Appearance.colors.colPrimaryContainer
                    colSymbol: Appearance.colors.colOnPrimaryContainer
                }
                StyledText {
                    text: Translation.tr("Clips")
                    color: Appearance.colors.colOnLayer0
                    font {
                        family: Appearance.font.family.title
                        pixelSize: Appearance.font.pixelSize.title
                        variableAxes: Appearance.font.variableAxes.title
                    }
                }
            }

            // Replay buffer status
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: bufferColumn.implicitHeight + 24
                radius: Appearance.rounding.normal
                color: ClipLibrary.running ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer1
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                ColumnLayout {
                    id: bufferColumn
                    anchors {
                        fill: parent
                        margins: 12
                    }
                    spacing: 8

                    RowLayout {
                        spacing: 10
                        Rectangle {
                            implicitWidth: 10
                            implicitHeight: 10
                            radius: 5
                            color: ClipLibrary.running ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                            SequentialAnimation on opacity {
                                running: ClipLibrary.running
                                loops: Animation.Infinite
                                alwaysRunToEnd: true
                                NumberAnimation { to: 0.3; duration: 900; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                text: ClipLibrary.running ? Translation.tr("Clipping is on") : Translation.tr("Clipping is off")
                                color: ClipLibrary.running ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
                                font.weight: Font.Medium
                            }
                            StyledText {
                                text: Translation.tr("Keeps the last %1 s · %2 fps").arg(Config.options.clips.bufferSeconds).arg(Config.options.clips.fps)
                                color: ClipLibrary.running ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                opacity: 0.85
                            }
                        }
                        StyledSwitch {
                            checked: ClipLibrary.running
                            enabled: !ClipLibrary.bufferBusy
                            onClicked: ClipLibrary.toggleBuffer()
                        }
                    }
                    RowLayout {
                        visible: ClipLibrary.running
                        spacing: 6
                        SidebarPill {
                            Layout.fillWidth: true
                            symbol: "content_cut"
                            label: Translation.tr("Clip %1s").arg(Config.options.clips.clipSeconds)
                            enabled: !ClipLibrary.bufferBusy
                            onClicked: ClipLibrary.saveClip()
                        }
                        SidebarPill {
                            Layout.fillWidth: true
                            symbol: "history"
                            label: Translation.tr("Save %1s").arg(Config.options.clips.bufferSeconds)
                            enabled: !ClipLibrary.bufferBusy
                            onClicked: ClipLibrary.saveBuffer()
                        }
                    }
                }
            }

            Item { implicitHeight: 6 }

            NavButton {
                symbol: "video_library"
                label: Translation.tr("All clips")
                count: ClipLibrary.clips.length
                active: root.view === "all"
                onClicked: root.showView("all")
            }
            NavButton {
                symbol: "star"
                label: Translation.tr("Favorites")
                count: root.favoriteCount
                active: root.view === "favorites"
                onClicked: root.showView("favorites")
            }
            NavButton {
                symbol: "schedule"
                label: Translation.tr("Last 7 days")
                count: root.recentCount
                active: root.view === "recent"
                onClicked: root.showView("recent")
            }
            NavButton {
                visible: ClipLibrary.driveConnected || root.driveCount > 0
                symbol: "cloud"
                label: Translation.tr("On Proton Drive")
                count: root.driveCount
                active: root.view === "drive"
                onClicked: root.showView("drive")
            }

            StyledText {
                Layout.topMargin: 14
                Layout.leftMargin: 12
                Layout.bottomMargin: 2
                visible: ClipLibrary.games.length > 0
                text: Translation.tr("Games")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Medium
            }

            StyledListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 2
                popin: false
                model: ClipLibrary.games
                delegate: GameButton {
                    required property var modelData
                    width: ListView.view.width
                    game: modelData
                    active: root.view === "game" && root.selectedGame === modelData.name
                    onClicked: root.showView("game", modelData.name)
                }
            }

            // Proton Drive
            RippleButton {
                Layout.fillWidth: true
                implicitHeight: driveColumn.implicitHeight + 20
                buttonRadius: Appearance.rounding.normal
                colBackground: Appearance.colors.colLayer1
                colBackgroundHover: Appearance.colors.colLayer1Hover
                colRipple: Appearance.colors.colLayer1Active
                onClicked: driveDialog.open()

                contentItem: ColumnLayout {
                    id: driveColumn
                    anchors {
                        fill: parent
                        margins: 10
                        leftMargin: 14
                    }
                    spacing: 8

                    RowLayout {
                        spacing: 10
                        MaterialSymbol {
                            text: root.driveIcon
                            iconSize: 22
                            fill: ClipLibrary.driveConnected ? 1 : 0
                            color: ClipLibrary.syncStatus.error && ClipLibrary.driveConnected && !ClipLibrary.syncing
                                ? Appearance.colors.colError : Appearance.colors.colOnLayer1
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                text: Translation.tr("Proton Drive")
                                color: Appearance.colors.colOnLayer1
                                font.weight: Font.Medium
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: root.driveSummary
                                elide: Text.ElideRight
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smaller
                            }
                        }
                        ToolIconButton {
                            visible: ClipLibrary.driveConnected
                            enabled: !ClipLibrary.syncing
                            opacity: enabled ? 1 : 0.4
                            implicitWidth: 34
                            implicitHeight: 34
                            symbol: "sync"
                            tooltip: Translation.tr("Sync now")
                            onClicked: ClipLibrary.sync()
                        }
                    }
                    StyledProgressBar {
                        Layout.fillWidth: true
                        visible: ClipLibrary.syncing && (ClipLibrary.syncStatus.phase === "upload" || ClipLibrary.syncStatus.phase === "download")
                        value: ClipLibrary.syncStatus.progress ?? 0
                    }
                }
            }

            // Footer
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 6
                spacing: 2
                StyledText {
                    Layout.fillWidth: true
                    Layout.leftMargin: 6
                    text: `${ClipLibrary.clips.length} clips · ${ClipLibrary.formatSize(ClipLibrary.totalSize)}`
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    elide: Text.ElideRight
                }
                ToolIconButton {
                    symbol: "folder_open"
                    tooltip: Translation.tr("Open clips folder")
                    onClicked: ClipLibrary.openFolder()
                }
                ToolIconButton {
                    symbol: "keyboard"
                    tooltip: Translation.tr("Shortcuts & sound")
                    onClicked: shortcutsDialog.open()
                }
                ToolIconButton {
                    symbol: "settings"
                    tooltip: Translation.tr("Clipping settings")
                    onClicked: settingsDialog.open()
                }
            }
        }

        // ================= Main panel =================
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Appearance.rounding.windowRounding
            color: Appearance.colors.colLayer1

            // ---------- Library ----------
            Item {
                id: library
                anchors.fill: parent
                anchors.margins: 16
                visible: !root.playingClip

                readonly property real gap: 16
                readonly property int columns: Math.max(1, Math.floor((width + gap) / (Persistent.states.clips.cardSize + gap)))
                readonly property real cardWidth: Math.floor((width - gap * (columns - 1)) / columns)

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 12

                    // Game banner
                    Rectangle {
                        id: banner
                        Layout.fillWidth: true
                        visible: root.view === "game" && !!root.selectedGameInfo?.hero
                        implicitHeight: 170
                        radius: Appearance.rounding.normal
                        color: Appearance.colors.colLayer2

                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: banner.width
                                height: banner.height
                                radius: banner.radius
                            }
                        }

                        Image {
                            anchors.fill: parent
                            source: root.selectedGameInfo?.hero ? `file://${root.selectedGameInfo.hero}` : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                        Rectangle {
                            anchors.fill: parent
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: ColorUtils.transparentize("#000000", 0.25) }
                                GradientStop { position: 0.7; color: "transparent" }
                            }
                        }
                        ColumnLayout {
                            anchors {
                                left: parent.left
                                bottom: parent.bottom
                                margins: 20
                            }
                            spacing: 6
                            Image {
                                Layout.preferredHeight: 64
                                Layout.preferredWidth: Math.min(280, implicitWidth * 64 / Math.max(1, implicitHeight))
                                visible: !!root.selectedGameInfo?.logo && status === Image.Ready
                                source: root.selectedGameInfo?.logo ? `file://${root.selectedGameInfo.logo}` : ""
                                fillMode: Image.PreserveAspectFit
                                horizontalAlignment: Image.AlignLeft
                                asynchronous: true
                            }
                            StyledText {
                                text: `${root.selectedGameInfo?.count ?? 0} clips · ${ClipLibrary.formatSize(root.selectedGameInfo?.size ?? 0)}`
                                color: "#ffffff"
                                font.weight: Font.Medium
                            }
                        }
                    }

                    // Title + toolbar
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: root.view === "favorites" ? Translation.tr("Favorites")
                                    : root.view === "recent" ? Translation.tr("Last 7 days")
                                    : root.view === "drive" ? Translation.tr("On Proton Drive")
                                    : root.view === "game" ? root.selectedGame
                                    : Translation.tr("All clips")
                                color: Appearance.colors.colOnLayer1
                                font {
                                    family: Appearance.font.family.title
                                    pixelSize: Appearance.font.pixelSize.title
                                    variableAxes: Appearance.font.variableAxes.title
                                }
                            }
                            StyledText {
                                text: Translation.tr("%1 clips").arg(root.visibleClips.length)
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.small
                            }
                        }

                        Rectangle {
                            implicitWidth: 260
                            implicitHeight: 40
                            radius: Appearance.rounding.full
                            color: Appearance.colors.colLayer2
                            RowLayout {
                                anchors {
                                    fill: parent
                                    leftMargin: 12
                                    rightMargin: 4
                                }
                                spacing: 4
                                MaterialSymbol {
                                    text: "search"
                                    iconSize: 20
                                    color: Appearance.colors.colSubtext
                                }
                                ToolbarTextField {
                                    id: searchField
                                    Layout.fillWidth: true
                                    colBackground: "transparent"
                                    padding: 6
                                    placeholderText: Translation.tr("Search clips (Ctrl+F)")
                                    onTextChanged: root.searchText = text
                                    Keys.onEscapePressed: {
                                        if (text.length > 0) text = "";
                                        else root.forceActiveFocus();
                                    }
                                }
                                ToolIconButton {
                                    visible: searchField.text.length > 0
                                    implicitWidth: 32
                                    implicitHeight: 32
                                    symbol: "close"
                                    onClicked: searchField.text = ""
                                }
                            }
                        }

                        StyledComboBox {
                            Layout.fillWidth: false
                            implicitWidth: 160
                            model: root.sortOptions.map(o => o.displayName)
                            currentIndex: Math.max(0, root.sortOptions.findIndex(o => o.value === root.sort))
                            buttonIcon: root.sortOptions[currentIndex]?.icon ?? "sort"
                            onActivated: index => Persistent.states.clips.sort = root.sortOptions[index].value
                        }

                        ToolIconButton {
                            symbol: "photo_size_select_large"
                            tooltip: Translation.tr("Card size")
                            onClicked: {
                                const sizes = [220, 300, 420];
                                const current = sizes.findIndex(s => s >= Persistent.states.clips.cardSize);
                                Persistent.states.clips.cardSize = sizes[(current + 1) % sizes.length];
                            }
                        }
                        ToolIconButton {
                            symbol: "refresh"
                            tooltip: Translation.tr("Refresh (F5)")
                            rotation: ClipLibrary.loading ? 360 : 0
                            Behavior on rotation {
                                NumberAnimation { duration: 700 }
                            }
                            onClicked: {
                                ClipLibrary.refresh();
                                ClipLibrary.sync();
                            }
                        }
                    }

                    // Selection bar
                    Rectangle {
                        Layout.fillWidth: true
                        visible: root.selectionMode
                        implicitHeight: 48
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colSecondaryContainer

                        RowLayout {
                            anchors {
                                fill: parent
                                leftMargin: 8
                                rightMargin: 8
                            }
                            spacing: 4
                            ToolIconButton {
                                symbol: "close"
                                tooltip: Translation.tr("Clear selection (Esc)")
                                onClicked: root.selectedIds = []
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("%1 selected").arg(root.selectedIds.length)
                                color: Appearance.colors.colOnSecondaryContainer
                                font.weight: Font.Medium
                            }
                            SelectionAction {
                                symbol: "select_all"
                                label: Translation.tr("Select all")
                                onClicked: root.selectedIds = root.visibleClips.map(c => c.id)
                            }
                            SelectionAction {
                                readonly property bool allFavorite: root.selectedClips.every(c => c.favorite)
                                symbol: "star"
                                label: allFavorite ? Translation.tr("Unfavorite") : Translation.tr("Favorite")
                                onClicked: ClipLibrary.setFavorite(root.selectedIds, !allFavorite)
                            }
                            SelectionAction {
                                symbol: "drive_file_move"
                                label: Translation.tr("Change game")
                                onClicked: root.requestMove(root.selectedIds)
                            }
                            SelectionAction {
                                readonly property list<string> cloudOnly: root.selectedClips.filter(c => !c.local).map(c => c.id)
                                visible: ClipLibrary.driveConnected && cloudOnly.length > 0
                                symbol: "cloud_download"
                                label: Translation.tr("Download")
                                onClicked: ClipLibrary.download(cloudOnly)
                            }
                            SelectionAction {
                                readonly property list<string> notUploaded: root.selectedClips.filter(c => c.local && !c.cloud).map(c => c.id)
                                visible: ClipLibrary.driveConnected && notUploaded.length > 0
                                symbol: "cloud_upload"
                                label: Translation.tr("Upload")
                                onClicked: ClipLibrary.upload(notUploaded)
                            }
                            SelectionAction {
                                symbol: "delete"
                                label: Translation.tr("Delete")
                                onClicked: root.requestDelete(root.selectedIds)
                            }
                        }
                    }

                    // Grid
                    StyledFlickable {
                        id: libraryFlickable
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        contentHeight: groupsColumn.implicitHeight
                        ScrollBar.vertical: StyledScrollBar {}

                        Column {
                            id: groupsColumn
                            width: libraryFlickable.width
                            spacing: 20
                            bottomPadding: 16

                            Repeater {
                                model: root.groups
                                delegate: Column {
                                    id: group
                                    required property var modelData
                                    width: groupsColumn.width
                                    spacing: 10

                                    StyledText {
                                        visible: group.modelData.label.length > 0
                                        text: group.modelData.label
                                        color: Appearance.colors.colOnLayer1
                                        font.pixelSize: Appearance.font.pixelSize.large
                                        font.weight: Font.Medium
                                    }

                                    Flow {
                                        width: parent.width
                                        spacing: library.gap

                                        Repeater {
                                            model: group.modelData.clips
                                            delegate: ClipCard {
                                                id: card
                                                required property var modelData
                                                clipData: modelData
                                                width: library.cardWidth
                                                showGame: root.view !== "game"
                                                selected: root.selectedIds.includes(modelData.id)
                                                selectionMode: root.selectionMode
                                                onPlay: root.play(modelData)
                                                onToggleSelected: root.toggleSelected(modelData.id)
                                                onMenuRequested: (x, y) => {
                                                    const p = card.mapToItem(root, x, y);
                                                    clipMenu.openFor(modelData, p.x, p.y);
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Empty / loading states
                ColumnLayout {
                    anchors.centerIn: parent
                    visible: root.visibleClips.length === 0
                    spacing: 12

                    MaterialLoadingIndicator {
                        Layout.alignment: Qt.AlignHCenter
                        visible: ClipLibrary.loading && !ClipLibrary.loaded
                        loading: visible
                    }
                    MaterialShapeWrappedMaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        visible: !(ClipLibrary.loading && !ClipLibrary.loaded)
                        text: root.searchText.length > 0 ? "search_off" : root.view === "favorites" ? "star" : root.view === "drive" ? "cloud" : "movie"
                        iconSize: 48
                        padding: 22
                        wrappedShape: MaterialShape.Shape.Cookie9Sided
                        color: Appearance.colors.colSecondaryContainer
                        colSymbol: Appearance.colors.colOnSecondaryContainer
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        visible: !(ClipLibrary.loading && !ClipLibrary.loaded)
                        text: root.searchText.length > 0 ? Translation.tr("No clips match “%1”").arg(root.searchText)
                            : root.view === "favorites" ? Translation.tr("No favorites yet")
                            : root.view === "drive" ? Translation.tr("Nothing on Proton Drive yet")
                            : Translation.tr("No clips yet")
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.larger
                        font.weight: Font.Medium
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.maximumWidth: 420
                        visible: !(ClipLibrary.loading && !ClipLibrary.loaded) && root.searchText.length === 0
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: root.view === "favorites" ? Translation.tr("Star a clip to keep it here.")
                            : root.view === "drive" ? Translation.tr("Select clips and press Upload, or right-click one and pick Upload to Proton Drive.")
                            : !root.saveShortcut ? Translation.tr("Set a shortcut for saving clips under Shortcuts & sound.")
                            : ClipLibrary.running ? Translation.tr("Clipping is on. Press %1 in game to save the last %2 seconds.").arg(root.saveShortcut).arg(Config.options.clips.clipSeconds)
                            : Translation.tr("Turn on clipping to keep a replay buffer running, then press %1 in game to save a clip.").arg(root.saveShortcut)
                        color: Appearance.colors.colSubtext
                    }
                    RippleButton {
                        Layout.alignment: Qt.AlignHCenter
                        visible: !ClipLibrary.running && !(ClipLibrary.loading && !ClipLibrary.loaded) && root.view !== "favorites" && root.view !== "drive" && root.searchText.length === 0
                        implicitHeight: 40
                        implicitWidth: startRow.implicitWidth + 32
                        buttonRadius: height / 2
                        colBackground: Appearance.colors.colPrimary
                        colBackgroundHover: Appearance.colors.colPrimaryHover
                        colRipple: Appearance.colors.colPrimaryActive
                        enabled: !ClipLibrary.bufferBusy
                        onClicked: ClipLibrary.toggleBuffer()
                        contentItem: RowLayout {
                            id: startRow
                            anchors.centerIn: parent
                            spacing: 6
                            MaterialSymbol {
                                text: "power_settings_new"
                                iconSize: 20
                                color: Appearance.colors.colOnPrimary
                            }
                            StyledText {
                                text: Translation.tr("Start clipping")
                                color: Appearance.colors.colOnPrimary
                            }
                        }
                    }
                }
            }

            // ---------- Player ----------
            Loader {
                id: playerLoader
                anchors.fill: parent
                anchors.margins: 16
                active: !!root.playingClip
                onLoaded: item.forceActiveFocus()
                sourceComponent: ClipPlayer {
                    clipData: root.playingClip
                    playlist: root.visibleClips
                    onBack: {
                        root.playingClip = null;
                        root.forceActiveFocus();
                    }
                    onOpenClip: clip => root.playingClip = clip
                    onDeleteRequested: clip => root.requestDelete([clip.id])
                    onRenameRequested: clip => root.requestRename(clip)
                    onMoveRequested: clip => root.requestMove([clip.id])
                }
            }
        }
    }

    // ================= Context menu =================
    Popup {
        id: clipMenu
        property var targetClip: null

        function openFor(clip, x, y) {
            clipMenu.targetClip = clip;
            clipMenu.x = Math.min(x, root.width - menuColumn.implicitWidth - 24);
            clipMenu.y = Math.min(y, root.height - menuColumn.implicitHeight - 24);
            clipMenu.open();
        }

        padding: 6
        background: Rectangle {
            radius: Appearance.rounding.normal
            color: Appearance.m3colors.m3surfaceContainerHigh
            border.width: 1
            border.color: Appearance.colors.colOutlineVariant
        }
        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 120 }
        }

        contentItem: ColumnLayout {
            id: menuColumn
            spacing: 0
            MenuEntry {
                symbol: "play_arrow"
                label: Translation.tr("Play")
                onClicked: root.play(clipMenu.targetClip)
            }
            MenuEntry {
                symbol: "star"
                label: clipMenu.targetClip?.favorite ? Translation.tr("Remove from favorites") : Translation.tr("Add to favorites")
                onClicked: ClipLibrary.toggleFavorite(clipMenu.targetClip.id)
            }
            MenuEntry {
                symbol: "check_circle"
                label: root.selectedIds.includes(clipMenu.targetClip?.id) ? Translation.tr("Deselect") : Translation.tr("Select")
                onClicked: root.toggleSelected(clipMenu.targetClip.id)
            }
            MenuDivider {}
            MenuEntry {
                symbol: "edit"
                label: Translation.tr("Rename…")
                onClicked: root.requestRename(clipMenu.targetClip)
            }
            MenuEntry {
                symbol: "drive_file_move"
                label: Translation.tr("Change game…")
                onClicked: root.requestMove([clipMenu.targetClip.id])
            }
            MenuDivider {
                visible: clipMenu.targetClip?.local ?? false
            }
            MenuEntry {
                visible: clipMenu.targetClip?.local ?? false
                symbol: "content_copy"
                label: Translation.tr("Copy clip")
                onClicked: ClipLibrary.copyFile(clipMenu.targetClip.path)
            }
            MenuEntry {
                visible: clipMenu.targetClip?.local ?? false
                symbol: "link"
                label: Translation.tr("Copy file path")
                onClicked: ClipLibrary.copyPath(clipMenu.targetClip.path)
            }
            MenuEntry {
                visible: clipMenu.targetClip?.local ?? false
                symbol: "folder_open"
                label: Translation.tr("Show in folder")
                onClicked: ClipLibrary.showInFolder(clipMenu.targetClip.path)
            }
            MenuEntry {
                visible: clipMenu.targetClip?.local ?? false
                symbol: "open_in_new"
                label: Translation.tr("Open in external player")
                onClicked: ClipLibrary.openExternally(clipMenu.targetClip.path)
            }
            MenuDivider {
                visible: ClipLibrary.driveConnected
            }
            MenuEntry {
                visible: ClipLibrary.driveConnected && !(clipMenu.targetClip?.local ?? true)
                symbol: "cloud_download"
                label: Translation.tr("Download")
                onClicked: ClipLibrary.download([clipMenu.targetClip.id])
            }
            MenuEntry {
                visible: ClipLibrary.driveConnected && (clipMenu.targetClip?.local ?? false) && !clipMenu.targetClip?.cloud
                symbol: "cloud_upload"
                label: Translation.tr("Upload to Proton Drive")
                onClicked: ClipLibrary.upload([clipMenu.targetClip.id])
            }
            MenuEntry {
                visible: ClipLibrary.driveConnected && (clipMenu.targetClip?.synced ?? false) // Drive has this exact file
                symbol: "file_download_off"
                label: Translation.tr("Remove download (keep on Drive)")
                onClicked: ClipLibrary.trash([clipMenu.targetClip.id], true)
            }
            MenuEntry {
                visible: ClipLibrary.driveConnected && (clipMenu.targetClip?.local ?? false) && (clipMenu.targetClip?.cloud ?? false)
                symbol: "cloud_off"
                label: Translation.tr("Remove from Proton Drive")
                onClicked: ClipLibrary.removeFromDrive([clipMenu.targetClip.id])
            }
            MenuDivider {}
            MenuEntry {
                symbol: "delete"
                label: Translation.tr("Delete")
                danger: true
                onClicked: root.requestDelete([clipMenu.targetClip.id])
            }
        }
    }

    // ================= Dialogs =================
    ClipDialog {
        id: deleteDialog
        property list<string> ids: []
        readonly property bool onDrive: ClipLibrary.clips.some(c => c.cloud && deleteDialog.ids.includes(c.id))
        anchors.fill: parent
        backgroundWidth: 400

        WindowDialogTitle {
            text: deleteDialog.ids.length === 1 ? Translation.tr("Delete clip?") : Translation.tr("Delete %1 clips?").arg(deleteDialog.ids.length)
        }
        WindowDialogParagraph {
            Layout.fillWidth: true
            text: deleteDialog.onDrive
                ? Translation.tr("They'll be moved to the trash here and on Proton Drive, so you can still restore them for a while.")
                : Translation.tr("They'll be moved to the trash, so you can still restore them from your file manager.")
        }
        WindowDialogButtonRow {
            Layout.bottomMargin: 10
            Item { Layout.fillWidth: true }
            DialogButton {
                buttonText: Translation.tr("Cancel")
                onClicked: deleteDialog.close()
            }
            DialogButton {
                buttonText: Translation.tr("Delete")
                colEnabled: Appearance.colors.colError
                onClicked: {
                    if (root.playingClip && deleteDialog.ids.includes(root.playingClip.id)) {
                        const list = playerLoader.item?.playlist ?? [];
                        const index = list.findIndex(c => c.id === root.playingClip.id);
                        const next = list.find((c, i) => i > index && !deleteDialog.ids.includes(c.id));
                        root.playingClip = next ?? null;
                    }
                    ClipLibrary.trash(deleteDialog.ids, false);
                    root.selectedIds = root.selectedIds.filter(id => !deleteDialog.ids.includes(id));
                    deleteDialog.close();
                    root.forceActiveFocus();
                }
            }
        }
    }

    ClipDialog {
        id: renameDialog
        property var targetClip: null
        anchors.fill: parent
        backgroundWidth: 440

        function submit() {
            ClipLibrary.rename(renameDialog.targetClip.id, renameField.text);
            renameDialog.close();
            root.forceActiveFocus();
        }

        WindowDialogTitle {
            text: Translation.tr("Rename clip")
        }
        MaterialTextField {
            id: renameField
            Layout.fillWidth: true
            placeholderText: Translation.tr("Clip name")
            onAccepted: renameDialog.submit()
            Keys.onEscapePressed: renameDialog.close()
        }
        WindowDialogButtonRow {
            Layout.bottomMargin: 10
            Item { Layout.fillWidth: true }
            DialogButton {
                buttonText: Translation.tr("Cancel")
                onClicked: renameDialog.close()
            }
            DialogButton {
                buttonText: Translation.tr("Rename")
                enabled: renameField.text.trim().length > 0
                onClicked: renameDialog.submit()
            }
        }
    }

    ClipDialog {
        id: moveDialog
        property list<string> ids: []
        anchors.fill: parent
        backgroundWidth: 460

        function submit(game) {
            ClipLibrary.moveToGame(moveDialog.ids, game);
            root.selectedIds = [];
            moveDialog.close();
            root.forceActiveFocus();
        }

        WindowDialogTitle {
            text: moveDialog.ids.length === 1 ? Translation.tr("Change game") : Translation.tr("Move %1 clips to game").arg(moveDialog.ids.length)
        }
        WindowDialogParagraph {
            Layout.fillWidth: true
            text: Translation.tr("Pick a game or type a new name.")
        }
        Flow {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: ClipLibrary.games.filter(g => g.name !== "Unsorted")
                delegate: RippleButton {
                    id: gameChip
                    required property var modelData
                    implicitHeight: 34
                    implicitWidth: chipText.implicitWidth + 24
                    buttonRadius: height / 2
                    colBackground: Appearance.colors.colLayer4
                    colBackgroundHover: Appearance.colors.colLayer4Hover
                    colRipple: Appearance.colors.colLayer4Active
                    onClicked: moveDialog.submit(gameChip.modelData.name)
                    contentItem: StyledText {
                        id: chipText
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: gameChip.modelData.name
                        color: Appearance.colors.colOnLayer3
                    }
                }
            }
        }
        MaterialTextField {
            id: moveField
            Layout.fillWidth: true
            placeholderText: Translation.tr("New game name")
            onAccepted: if (text.trim().length > 0) moveDialog.submit(text)
            Keys.onEscapePressed: moveDialog.close()
        }
        WindowDialogButtonRow {
            Layout.bottomMargin: 10
            Item { Layout.fillWidth: true }
            DialogButton {
                buttonText: Translation.tr("Cancel")
                onClicked: moveDialog.close()
            }
            DialogButton {
                buttonText: Translation.tr("Move")
                enabled: moveField.text.trim().length > 0
                onClicked: moveDialog.submit(moveField.text)
            }
        }
    }

    ClipDialog {
        id: settingsDialog
        anchors.fill: parent
        backgroundWidth: 520

        WindowDialogTitle {
            text: Translation.tr("Clipping settings")
        }
        WindowDialogParagraph {
            Layout.fillWidth: true
            text: Translation.tr("Capture changes restart the replay buffer, which clears what it has recorded so far.")
        }

        ConfigSwitch {
            Layout.fillWidth: true
            buttonIcon: "sports_esports"
            text: Translation.tr("Clip automatically while a game is running")
            checked: Config.options.clips.autoStartForGames
            onCheckedChanged: Config.options.clips.autoStartForGames = checked
        }
        ConfigSwitch {
            Layout.fillWidth: true
            buttonIcon: "rocket_launch"
            text: Translation.tr("Start clipping when the shell starts")
            checked: Config.options.clips.autoStart
            onCheckedChanged: Config.options.clips.autoStart = checked
        }
        ConfigSpinBox {
            icon: "history"
            text: Translation.tr("Replay buffer length (seconds)")
            value: Config.options.clips.bufferSeconds
            from: 10
            to: 600
            stepSize: 10
            onValueChanged: if (value !== Config.options.clips.bufferSeconds) Config.options.clips.bufferSeconds = value
        }
        ConfigSpinBox {
            icon: "content_cut"
            text: Translation.tr("Clip length for hotkey (seconds)")
            value: Config.options.clips.clipSeconds
            from: 5
            to: Config.options.clips.bufferSeconds
            stepSize: 5
            onValueChanged: if (value !== Config.options.clips.clipSeconds) Config.options.clips.clipSeconds = value
        }
        ConfigComboBox {
            Layout.fillWidth: true
            buttonIcon: "speed"
            text: Translation.tr("Frame rate")
            model: [30, 60, 120, 144, 165, 240].map(f => ({ displayName: `${f} fps`, value: f }))
            currentValue: Config.options.clips.fps
            onSelected: newValue => Config.options.clips.fps = newValue
        }
        ConfigComboBox {
            Layout.fillWidth: true
            buttonIcon: "high_quality"
            text: Translation.tr("Quality")
            model: [
                { displayName: Translation.tr("Medium"), value: "medium" },
                { displayName: Translation.tr("High"), value: "high" },
                { displayName: Translation.tr("Very high"), value: "very_high" },
                { displayName: Translation.tr("Ultra"), value: "ultra" },
            ]
            currentValue: Config.options.clips.quality
            onSelected: newValue => Config.options.clips.quality = newValue
        }
        ConfigComboBox {
            Layout.fillWidth: true
            buttonIcon: "aspect_ratio"
            text: Translation.tr("Resolution")
            model: [
                { displayName: Translation.tr("Native"), value: "0x0" },
                { displayName: "1440p", value: "2560x1440" },
                { displayName: "1080p", value: "1920x1080" },
                { displayName: "720p", value: "1280x720" },
            ]
            currentValue: Config.options.clips.resolution
            onSelected: newValue => Config.options.clips.resolution = newValue
        }
        ConfigComboBox {
            Layout.fillWidth: true
            buttonIcon: "monitor"
            text: Translation.tr("Monitor")
            model: [{ displayName: Translation.tr("Focused when clipping starts"), value: "" },
                ...Quickshell.screens.map(s => ({ displayName: `${s.name} (${s.width}×${s.height})`, value: s.name }))]
            currentValue: Config.options.clips.monitor
            onSelected: newValue => Config.options.clips.monitor = newValue
        }
        ConfigSwitch {
            Layout.fillWidth: true
            buttonIcon: "volume_up"
            text: Translation.tr("Record system audio")
            checked: Config.options.clips.systemAudio
            onCheckedChanged: Config.options.clips.systemAudio = checked
        }
        ConfigSwitch {
            Layout.fillWidth: true
            buttonIcon: "mic"
            text: Translation.tr("Record microphone")
            checked: Config.options.clips.microphone
            onCheckedChanged: Config.options.clips.microphone = checked
        }
        WindowDialogButtonRow {
            Layout.bottomMargin: 10
            DialogButton {
                buttonText: Translation.tr("Shortcuts & sound…")
                onClicked: {
                    settingsDialog.close();
                    shortcutsDialog.open();
                }
            }
            DialogButton {
                buttonText: Translation.tr("Proton Drive…")
                onClicked: {
                    settingsDialog.close();
                    driveDialog.open();
                }
            }
            Item { Layout.fillWidth: true }
            DialogButton {
                buttonText: Translation.tr("Done")
                onClicked: {
                    settingsDialog.close();
                    root.forceActiveFocus();
                }
            }
        }
    }

    ClipDialog {
        id: driveDialog
        anchors.fill: parent
        backgroundWidth: 540

        function closeDialog() {
            if (ClipLibrary.driveSigningIn) ClipLibrary.cancelSignIn();
            driveDialog.close();
            root.forceActiveFocus();
        }

        WindowDialogTitle {
            text: Translation.tr("Proton Drive")
        }
        WindowDialogParagraph {
            Layout.fillWidth: true
            visible: !ClipLibrary.driveInstalled
            text: Translation.tr("Syncing goes through Proton's proton-drive command line tool, which isn't installed. Put it on your PATH or in ~/.local/bin, then open this again.")
        }
        WindowDialogParagraph {
            Layout.fillWidth: true
            visible: ClipLibrary.driveInstalled && !ClipLibrary.driveConnected
            text: ClipLibrary.driveSigningIn
                ? Translation.tr("Finish signing in in your browser…")
                : Translation.tr("Sign in to Proton Drive to keep clips in step between your devices. Uploaded clips go into their own “Quickshell Clips” folder, and nothing else in your Drive is touched.")
        }
        WindowDialogParagraph {
            Layout.fillWidth: true
            visible: ClipLibrary.driveConnected
            text: Translation.tr("Signed in as %1. Only the clips you pick get uploaded: select them and press Upload, or right-click one. Uploaded clips stay in step on all your devices (names, games, favorites, edits and deletions) and live in their own “Quickshell Clips” folder in your Proton Drive.")
                .arg(ClipLibrary.driveEmail || Translation.tr("your Proton account"))
        }
        RowLayout {
            Layout.fillWidth: true
            visible: ClipLibrary.driveConnected
            spacing: 10
            MaterialSymbol {
                text: root.driveIcon
                iconSize: 20
                color: Appearance.colors.colOnSurfaceVariant
            }
            StyledText {
                Layout.fillWidth: true
                text: root.driveSummary
                wrapMode: Text.Wrap
                color: Appearance.colors.colOnSurfaceVariant
                font.pixelSize: Appearance.font.pixelSize.small
            }
        }
        StyledText {
            Layout.fillWidth: true
            visible: ClipLibrary.driveMessage.length > 0
            text: ClipLibrary.driveMessage
            wrapMode: Text.Wrap
            color: Appearance.colors.colError
            font.pixelSize: Appearance.font.pixelSize.small
        }

        WindowDialogButtonRow {
            Layout.bottomMargin: 10
            DialogButton {
                visible: ClipLibrary.driveConnected
                buttonText: Translation.tr("Sign out")
                colEnabled: Appearance.colors.colError
                onClicked: ClipLibrary.signOut()
            }
            Item { Layout.fillWidth: true }
            DialogButton {
                visible: ClipLibrary.driveSigningIn && ClipLibrary.driveAuthUrl.length > 0
                buttonText: Translation.tr("Open sign-in page")
                onClicked: Qt.openUrlExternally(ClipLibrary.driveAuthUrl)
            }
            DialogButton {
                buttonText: ClipLibrary.driveSigningIn ? Translation.tr("Cancel") : Translation.tr("Close")
                onClicked: driveDialog.closeDialog()
            }
            DialogButton {
                visible: ClipLibrary.driveInstalled && !ClipLibrary.driveConnected && !ClipLibrary.driveSigningIn
                buttonText: Translation.tr("Sign in")
                onClicked: ClipLibrary.signIn()
            }
            DialogButton {
                visible: ClipLibrary.driveConnected
                enabled: !ClipLibrary.syncing
                buttonText: Translation.tr("Sync now")
                onClicked: ClipLibrary.sync()
            }
        }
    }

    ClipDialog {
        id: shortcutsDialog
        anchors.fill: parent
        backgroundWidth: 540

        WindowDialogTitle {
            text: Translation.tr("Shortcuts & sound")
        }
        WindowDialogParagraph {
            Layout.fillWidth: true
            text: Translation.tr("Click a shortcut, then press the new keys. Esc cancels and Backspace clears it. Keys that Hyprland already uses for something else never reach this window.")
        }
        ShortcutRow {
            name: "save"
            label: Translation.tr("Save the last %1 seconds").arg(Config.options.clips.clipSeconds)
        }
        ShortcutRow {
            name: "saveBuffer"
            label: Translation.tr("Save the whole buffer (%1 seconds)").arg(Config.options.clips.bufferSeconds)
        }
        ShortcutRow {
            name: "toggle"
            label: Translation.tr("Start or stop clipping")
        }
        ShortcutRow {
            name: "openApp"
            label: Translation.tr("Open or close Clips")
        }
        WindowDialogSeparator {}
        ConfigSwitch {
            Layout.fillWidth: true
            buttonIcon: "volume_up"
            text: Translation.tr("Play a sound when a clip is saved")
            checked: Config.options.clips.saveSoundEnabled
            onCheckedChanged: Config.options.clips.saveSoundEnabled = checked
        }
        RowLayout {
            Layout.fillWidth: true
            enabled: Config.options.clips.saveSoundEnabled
            opacity: enabled ? 1 : 0.5
            spacing: 6
            MaterialTextField {
                id: soundField
                Layout.fillWidth: true
                placeholderText: Translation.tr("Sound file (mp3, ogg, wav…)")
                text: Config.options.clips.saveSound
                onTextChanged: Config.options.clips.saveSound = text.trim()
            }
            ToolIconButton {
                symbol: "play_arrow"
                tooltip: Translation.tr("Play it")
                onClicked: ClipLibrary.playSound(soundField.text)
            }
        }
        WindowDialogParagraph {
            Layout.fillWidth: true
            text: Translation.tr("Saving a clip also shows a notification with a frame from it. Its Open button shows the clip here.")
        }
        WindowDialogButtonRow {
            Layout.bottomMargin: 10
            Item { Layout.fillWidth: true }
            DialogButton {
                buttonText: Translation.tr("Done")
                onClicked: {
                    shortcutsDialog.close();
                    root.forceActiveFocus();
                }
            }
        }
    }

    // ================= Components =================
    component ShortcutRow: RowLayout {
        id: shortcutRow
        required property string name
        property string label
        readonly property string combo: Config.options.clips.shortcuts[shortcutRow.name] ?? ""
        property bool capturing: false
        Layout.fillWidth: true
        spacing: 10

        StyledText {
            Layout.fillWidth: true
            text: shortcutRow.label
            color: Appearance.colors.colOnSecondaryContainer
            elide: Text.ElideRight
        }
        RippleButton {
            id: keyButton
            implicitHeight: 36
            implicitWidth: Math.max(170, keyLabel.implicitWidth + 28)
            buttonRadius: height / 2
            toggled: shortcutRow.capturing
            colBackground: Appearance.colors.colLayer4
            colBackgroundHover: Appearance.colors.colLayer4Hover
            colRipple: Appearance.colors.colLayer4Active
            onClicked: {
                shortcutRow.capturing = true;
                keyButton.forceActiveFocus();
            }
            onActiveFocusChanged: {
                if (!activeFocus) shortcutRow.capturing = false;
            }
            Keys.onPressed: event => {
                if (!shortcutRow.capturing) return;
                event.accepted = true;
                const plain = (event.modifiers & (Qt.ControlModifier | Qt.ShiftModifier | Qt.AltModifier | Qt.MetaModifier)) === 0;
                if (plain && event.key === Qt.Key_Escape) {
                    shortcutRow.capturing = false;
                } else if (plain && (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete)) {
                    shortcutRow.capturing = false;
                    root.setShortcut(shortcutRow.name, "");
                } else {
                    const combo = root.shortcutFromEvent(event);
                    if (!combo) return; // Only modifiers so far
                    shortcutRow.capturing = false;
                    root.setShortcut(shortcutRow.name, combo);
                }
            }
            contentItem: StyledText {
                id: keyLabel
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                text: shortcutRow.capturing ? Translation.tr("Press keys…")
                    : shortcutRow.combo ? root.shortcutLabel(shortcutRow.combo) : Translation.tr("Not set")
                color: shortcutRow.capturing ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3
            }
        }
    }

    component NavButton: RippleButton {
        id: navButton
        property string symbol
        property string label
        property int count: 0
        property bool active: false
        Layout.fillWidth: true
        implicitHeight: 44
        buttonRadius: Appearance.rounding.full
        toggled: active
        colBackgroundToggled: Appearance.colors.colSecondaryContainer
        colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
        colRippleToggled: Appearance.colors.colSecondaryContainerActive
        contentItem: RowLayout {
            anchors {
                fill: parent
                leftMargin: 14
                rightMargin: 16
            }
            spacing: 12
            MaterialSymbol {
                text: navButton.symbol
                iconSize: 22
                fill: navButton.active ? 1 : 0
                color: navButton.active ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer0
            }
            StyledText {
                Layout.fillWidth: true
                text: navButton.label
                elide: Text.ElideRight
                color: navButton.active ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer0
                font.weight: navButton.active ? Font.Medium : Font.Normal
            }
            StyledText {
                text: navButton.count
                color: navButton.active ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
        }
    }

    component GameButton: RippleButton {
        id: gameButton
        property var game
        property bool active: false
        implicitHeight: 52
        buttonRadius: Appearance.rounding.normal
        toggled: active
        colBackgroundToggled: Appearance.colors.colSecondaryContainer
        colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
        colRippleToggled: Appearance.colors.colSecondaryContainerActive
        contentItem: RowLayout {
            anchors {
                fill: parent
                leftMargin: 6
                rightMargin: 16
            }
            spacing: 10
            Rectangle {
                id: gameArt
                Layout.preferredWidth: 72
                Layout.preferredHeight: 40
                radius: Appearance.rounding.verysmall
                color: Appearance.colors.colLayer2
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: gameArt.width
                        height: gameArt.height
                        radius: gameArt.radius
                    }
                }
                Image {
                    id: gameArtImage
                    anchors.fill: parent
                    source: gameButton.game.header ? `file://${gameButton.game.header}` : ""
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 160
                    asynchronous: true
                }
                IconImage {
                    anchors.centerIn: parent
                    implicitSize: 26
                    visible: gameArtImage.status !== Image.Ready && !!gameButton.game.class
                    source: Quickshell.iconPath(AppSearch.guessIcon(gameButton.game.class), "image-missing")
                }
                StyledText {
                    anchors.centerIn: parent
                    visible: gameArtImage.status !== Image.Ready && !gameButton.game.class
                    text: gameButton.game.name.charAt(0).toUpperCase()
                    color: Appearance.colors.colOnLayer2
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.weight: Font.DemiBold
                }
            }
            StyledText {
                Layout.fillWidth: true
                text: gameButton.game.name
                elide: Text.ElideRight
                color: gameButton.active ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer0
                font.weight: gameButton.active ? Font.Medium : Font.Normal
            }
            StyledText {
                text: gameButton.game.count
                color: gameButton.active ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
        }
    }

    component SidebarPill: RippleButton {
        id: sidebarPill
        property string symbol
        property alias label: pillText.text
        implicitHeight: 34
        buttonRadius: height / 2
        opacity: enabled ? 1 : 0.5
        colBackground: Appearance.colors.colPrimary
        colBackgroundHover: Appearance.colors.colPrimaryHover
        colRipple: Appearance.colors.colPrimaryActive
        contentItem: RowLayout {
            anchors.centerIn: parent
            spacing: 4
            MaterialSymbol {
                text: sidebarPill.symbol
                iconSize: 18
                color: Appearance.colors.colOnPrimary
            }
            StyledText {
                id: pillText
                color: Appearance.colors.colOnPrimary
                font.pixelSize: Appearance.font.pixelSize.small
            }
        }
    }

    component ToolIconButton: RippleButton {
        id: toolButton
        property string symbol
        property string tooltip
        implicitWidth: 40
        implicitHeight: 40
        buttonRadius: height / 2
        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: toolButton.symbol
            iconSize: 22
            color: Appearance.colors.colOnLayer1
        }
        StyledToolTip {
            visible: toolButton.tooltip.length > 0 && toolButton.hovered
            text: toolButton.tooltip
        }
    }

    component SelectionAction: RippleButton {
        id: selectionAction
        property string symbol
        property alias label: actionText.text
        implicitHeight: 36
        implicitWidth: actionRow.implicitWidth + 24
        buttonRadius: height / 2
        colBackground: "transparent"
        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
        colRipple: Appearance.colors.colSecondaryContainerActive
        contentItem: RowLayout {
            id: actionRow
            anchors.centerIn: parent
            spacing: 6
            MaterialSymbol {
                text: selectionAction.symbol
                iconSize: 20
                color: Appearance.colors.colOnSecondaryContainer
            }
            StyledText {
                id: actionText
                color: Appearance.colors.colOnSecondaryContainer
            }
        }
    }

    component MenuEntry: RippleButton {
        id: menuEntry
        property string symbol
        property alias label: entryText.text
        property bool danger: false
        Layout.fillWidth: true
        implicitWidth: entryRow.implicitWidth + 28
        implicitHeight: 38
        buttonRadius: Appearance.rounding.small
        colBackgroundHover: Appearance.colors.colLayer3Hover
        colRipple: Appearance.colors.colLayer3Active
        onClicked: clipMenu.close()
        contentItem: RowLayout {
            id: entryRow
            anchors {
                fill: parent
                leftMargin: 12
                rightMargin: 16
            }
            spacing: 12
            MaterialSymbol {
                text: menuEntry.symbol
                iconSize: 20
                color: menuEntry.danger ? Appearance.colors.colError : Appearance.colors.colOnLayer3
            }
            StyledText {
                id: entryText
                Layout.fillWidth: true
                color: menuEntry.danger ? Appearance.colors.colError : Appearance.colors.colOnLayer3
            }
        }
    }

    component MenuDivider: Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: 4
        Layout.bottomMargin: 4
        implicitHeight: 1
        color: Appearance.colors.colOutlineVariant
    }
}
