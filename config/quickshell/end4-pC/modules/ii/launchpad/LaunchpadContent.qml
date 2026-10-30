import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id: root

    property bool shown: false
    property int closeDuration: 200
    signal closeRequested()

    // 0 = hidden, 1 = shown; drives the zoom/fade in and out.
    property real progress: 0

    readonly property int columns: Math.max(1, Config.options.launchpad.columns)
    readonly property int rows: Math.max(1, Config.options.launchpad.rows)
    readonly property int pageSize: columns * rows
    readonly property string query: searchField.text.trim()
    readonly property var hiddenApps: Config.options.launchpad.hiddenApps
    readonly property var allApps: AppSearch.list.filter(app => !app.noDisplay)
        .sort((a, b) => a.name.toLowerCase().localeCompare(b.name.toLowerCase()))
    // Hidden apps stay out of the grid but can still be found by searching.
    property var gridApps: []
    // Search results get their own single page, so typing never rebuilds the grid.
    property var results: []
    readonly property bool searching: root.query !== ""
    readonly property var apps: root.searching ? root.results : root.gridApps
    readonly property int pageCount: Math.max(1, Math.ceil(gridApps.length / pageSize))
    // Keyboard selection as an index into `apps`; -1 when nothing is selected.
    property int selectedIndex: -1

    readonly property real cellWidth: pageView.width / root.columns
    readonly property real cellHeight: pageView.height / root.rows
    readonly property var style: Config.options.launchpad
    readonly property int iconSize: Math.round(Math.max(32, Math.min(cellHeight * 0.5, cellWidth * 0.48, 100))
        * Math.max(0.5, Math.min(1.5, root.style.iconScale ?? 1)))

    readonly property string wallpaperPath: {
        const path = Wallpapers.confirmedPath || Config.options.background.wallpaperPath;
        return /\.(mp4|webm|mkv|avi|mov)$/i.test(path) ? Config.options.background.thumbnailPath : path;
    }

    // Icon files by icon name, found by a helper process. Theme icons can't be
    // looked up off the UI thread (KDE's icon loader isn't thread-safe and it
    // broke icons elsewhere in the shell), but plain files decode safely in the
    // background, so tiles load the files instead of theme icons.
    property var iconFiles: ({})
    readonly property string iconTheme: SystemAppearance.iconTheme
    onIconThemeChanged: root.resolveIcons()

    property bool resolveAgain: false
    function resolveIcons() {
        if (root.iconTheme === "") return;
        if (iconResolver.running) {
            root.resolveAgain = true;
            return;
        }
        const names = [...new Set(AppSearch.list.map(app => app.icon).filter(name => name && name !== ""))];
        iconResolver.command = ["python3", SystemAppearance.iconResolverPath, root.iconTheme].concat(names);
        iconResolver.running = true;
    }

    function iconFor(entry) {
        const name = entry?.icon ?? "";
        const file = root.iconFiles[name];
        if (name !== "" && file === undefined) return ""; // Still being resolved
        if (file) return "file://" + file;
        // Not in the theme's folders: let the UI thread's theme lookup try.
        return SystemAppearance.iconPath(name, "application-x-executable");
    }

    Process {
        id: iconResolver
        onExited: {
            if (!root.resolveAgain) return;
            root.resolveAgain = false;
            root.resolveIcons();
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.iconFiles = JSON.parse(text);
                } catch (e) {
                    console.warn("[Launchpad] Could not resolve icons:", e);
                }
            }
        }
    }

    function updateApps() {
        root.gridApps = root.allApps.filter(app => !root.hiddenApps.includes(app.id));
        root.updateResults();
    }

    function updateResults() {
        root.results = root.searching ? AppSearch.fuzzyQuery(root.query).slice(0, root.pageSize) : [];
    }

    onQueryChanged: {
        root.updateResults();
        root.selectedIndex = root.searching ? 0 : -1;
    }
    onHiddenAppsChanged: root.updateApps()
    // Desktop entries change one at a time while they're (re)scanned, e.g. during
    // package updates, so wait for them to settle instead of rebuilding per entry.
    onAllAppsChanged: appsDebounce.restart()

    Timer {
        id: appsDebounce
        interval: 150
        onTriggered: {
            root.updateApps();
            root.resolveIcons();
        }
    }

    // The Launchpad stays loaded between opens, so it starts over once it's
    // hidden instead of when it's created.
    onShownChanged: {
        if (root.shown) {
            searchField.forceActiveFocus();
            openAnim.restart();
        } else {
            closeAnim.restart();
        }
    }
    Component.onCompleted: {
        root.updateApps();
        root.resolveIcons();
        if (root.shown) openAnim.restart();
        searchField.forceActiveFocus();
    }

    function reset() {
        appMenu.entry = null;
        searchField.text = "";
        root.selectedIndex = -1;
        pageView.currentIndex = 0;
        pageView.positionViewAtBeginning();
    }

    NumberAnimation {
        id: openAnim
        target: root
        property: "progress"
        to: 1
        duration: 380
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
    }

    NumberAnimation {
        id: closeAnim
        target: root
        property: "progress"
        to: 0
        duration: root.closeDuration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
        onFinished: if (!root.shown) root.reset()
    }

    function launch(entry) {
        if (!entry) return;
        entry.execute();
        const pinnedId = root.pinnedIdFor(entry);
        if (pinnedId) TaskbarApps.noteLaunch(pinnedId);
        root.closeRequested();
    }

    // The dock pins by window app ID, which usually matches the desktop entry ID
    // and otherwise its StartupWMClass.
    function pinnedIdFor(entry) {
        return [entry.id, entry.startupClass].find(id => id && TaskbarApps.isPinned(id));
    }

    function togglePin(entry) {
        TaskbarApps.togglePin(root.pinnedIdFor(entry) ?? entry.id);
    }

    function toggleHidden(entry) {
        const hidden = Config.options.launchpad.hiddenApps;
        Config.options.launchpad.hiddenApps = hidden.includes(entry.id)
            ? hidden.filter(id => id !== entry.id)
            : hidden.concat([entry.id]);
    }

    function goToPage(page) {
        pageView.currentIndex = Math.max(0, Math.min(root.pageCount - 1, page));
    }

    function moveSelection(delta) {
        if (root.apps.length === 0) return;
        if (root.selectedIndex < 0)
            root.selectedIndex = root.searching ? 0 : Math.min(pageView.currentIndex * root.pageSize, root.apps.length - 1);
        else
            root.selectedIndex = Math.max(0, Math.min(root.apps.length - 1, root.selectedIndex + delta));
        if (!root.searching) root.goToPage(Math.floor(root.selectedIndex / root.pageSize));
    }

    function handleKey(event) {
        if (appMenu.entry !== null) {
            if (event.key === Qt.Key_Escape) appMenu.entry = null;
            event.accepted = true;
            return;
        }
        switch (event.key) {
        case Qt.Key_Escape:
            if (searchField.text !== "") searchField.text = "";
            else root.closeRequested();
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (root.selectedIndex >= 0) root.launch(root.apps[root.selectedIndex]);
            break;
        case Qt.Key_Left:
            root.moveSelection(-1);
            break;
        case Qt.Key_Right:
            root.moveSelection(1);
            break;
        case Qt.Key_Up:
            root.moveSelection(-root.columns);
            break;
        case Qt.Key_Down:
            root.moveSelection(root.columns);
            break;
        case Qt.Key_PageUp:
            root.goToPage(pageView.currentIndex - 1);
            break;
        case Qt.Key_PageDown:
            root.goToPage(pageView.currentIndex + 1);
            break;
        case Qt.Key_Tab:
        case Qt.Key_Backtab:
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    // Backdrop: the wallpaper, blurred, like macOS
    Item {
        anchors.fill: parent
        opacity: root.progress

        // "tint" stays opaque enough (>= 0.79) for Hyprland to blur the desktop
        // behind it; "dim" just darkens it.
        Rectangle {
            anchors.fill: parent
            visible: root.style.background !== "dim"
            color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.12)
        }

        Image {
            id: wallpaper
            anchors.fill: parent
            visible: false
            source: root.style.background === "wallpaper" ? root.wallpaperPath : ""
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(Math.round(root.width / 3), Math.round(root.height / 3))
            asynchronous: true
        }

        MultiEffect {
            anchors.fill: wallpaper
            source: wallpaper
            visible: wallpaper.status === Image.Ready
            autoPaddingEnabled: false
            blurEnabled: (root.style.blur ?? 1) > 0
            blur: Math.max(0, Math.min(1, root.style.blur ?? 1))
            blurMax: 48
        }

        Rectangle {
            anchors.fill: parent
            color: root.style.background === "dim" ? "black" : Appearance.m3colors.m3background
            opacity: Math.max(0, Math.min(0.95, root.style.dim ?? 0.5))
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.closeRequested()
        }
    }

    Item {
        id: content
        anchors.fill: parent
        opacity: root.progress
        scale: root.style.openAnimation === "zoom" ? 1.08 - 0.08 * root.progress : 1
        transform: Translate {
            y: root.style.openAnimation === "rise" ? (1 - root.progress) * root.height * 0.06 : 0
        }

        // Search field
        Rectangle {
            id: searchBox
            anchors {
                top: parent.top
                topMargin: Math.round(root.height * 0.05)
                horizontalCenter: parent.horizontalCenter
            }
            implicitWidth: 300
            implicitHeight: 40
            radius: Appearance.rounding.full
            color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.9)
            border.width: 1
            border.color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.85)

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.IBeamCursor
                onPressed: searchField.forceActiveFocus()
            }

            RowLayout {
                anchors {
                    fill: parent
                    leftMargin: 12
                    rightMargin: 12
                }
                spacing: 6

                MaterialSymbol {
                    text: "search"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer0
                    opacity: 0.7
                }

                TextField {
                    id: searchField
                    Layout.fillWidth: true
                    background: null
                    padding: 0
                    placeholderText: Translation.tr("Search")
                    placeholderTextColor: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.4)
                    color: Appearance.colors.colOnLayer0
                    selectedTextColor: Appearance.colors.colOnSecondaryContainer
                    selectionColor: Appearance.colors.colSecondaryContainer
                    renderType: Text.NativeRendering
                    font {
                        family: Appearance.font.family.main
                        pixelSize: Appearance.font.pixelSize.normal
                        variableAxes: Appearance.font.variableAxes.main
                    }
                    Keys.onPressed: event => root.handleKey(event)
                }
            }
        }

        ListView {
            id: pageView
            anchors {
                top: searchBox.bottom
                topMargin: Math.round(root.height * 0.035)
                bottom: pageDots.top
                bottomMargin: Math.round(root.height * 0.02)
                horizontalCenter: parent.horizontalCenter
            }
            width: Math.min(parent.width - 160, root.height * 1.55)
            clip: true
            orientation: ListView.Horizontal
            snapMode: ListView.SnapOneItem
            highlightRangeMode: ListView.StrictlyEnforceRange
            preferredHighlightBegin: 0
            preferredHighlightEnd: width
            highlightMoveDuration: 380
            boundsBehavior: Flickable.StopAtBounds
            // Every page stays alive (one tile per app), so paging never builds tiles.
            cacheBuffer: Math.max(0, width * root.pageCount)
            opacity: root.searching ? 0 : 1
            enabled: !root.searching
            visible: opacity > 0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            // A diffing model, so existing pages stay when the page count changes.
            model: ScriptModel {
                values: Array.from({ length: root.pageCount }, (_, i) => i)
            }

            onCurrentIndexChanged: {
                // Paging with the mouse moves the keyboard selection along.
                if (!root.searching && root.selectedIndex >= 0 && Math.floor(root.selectedIndex / root.pageSize) !== currentIndex)
                    root.selectedIndex = -1;
            }

            delegate: Item {
                id: page
                required property int index
                width: pageView.width
                height: pageView.height

                // Clicking between icons closes, like on macOS.
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.closeRequested()
                }

                Grid {
                    columns: root.columns

                    Repeater {
                        model: ScriptModel {
                            values: root.gridApps.slice(page.index * root.pageSize, (page.index + 1) * root.pageSize)
                        }
                        delegate: LaunchpadAppButton {
                            id: tile
                            required property var modelData
                            required property int index
                            width: root.cellWidth
                            height: root.cellHeight
                            entry: modelData
                            iconUrl: root.iconFor(modelData)
                            iconSize: root.iconSize
                            showLabel: root.style.showLabels ?? true
                            selected: !root.searching && root.selectedIndex === page.index * root.pageSize + index
                            onClicked: root.launch(modelData)
                            onMenuRequested: (x, y) => appMenu.openAt(tile, x, y, modelData)
                        }
                    }
                }
            }

            // One page per wheel notch or touchpad swipe.
            WheelHandler {
                target: null
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                property real accumulated: 0
                onWheel: event => {
                    if (pageCooldown.running) return;
                    const delta = Math.abs(event.angleDelta.x) > Math.abs(event.angleDelta.y) ? event.angleDelta.x : event.angleDelta.y;
                    accumulated += delta;
                    if (Math.abs(accumulated) < 120) return;
                    root.goToPage(pageView.currentIndex + (accumulated > 0 ? -1 : 1));
                    accumulated = 0;
                    // Touchpads keep sending deltas for a while after a swipe.
                    if (event.pixelDelta.x !== 0 || event.pixelDelta.y !== 0) pageCooldown.restart();
                }
            }

            Timer {
                id: pageCooldown
                interval: 450
            }
        }

        Item {
            anchors.fill: pageView
            opacity: root.searching ? 1 : 0
            visible: opacity > 0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.closeRequested()
            }

            Grid {
                columns: root.columns

                Repeater {
                    model: ScriptModel {
                        values: root.results
                    }
                    delegate: LaunchpadAppButton {
                        id: resultTile
                        required property var modelData
                        required property int index
                        width: root.cellWidth
                        height: root.cellHeight
                        entry: modelData
                        iconUrl: root.iconFor(modelData)
                        iconSize: root.iconSize
                        showLabel: root.style.showLabels ?? true
                        selected: root.selectedIndex === index
                        dimmed: root.hiddenApps.includes(modelData.id)
                        onClicked: root.launch(modelData)
                        onMenuRequested: (x, y) => appMenu.openAt(resultTile, x, y, modelData)
                    }
                }
            }
        }

        StyledText {
            anchors.centerIn: pageView
            visible: root.searching && root.results.length === 0
            text: Translation.tr("No apps match “%1”").arg(root.query)
            font.pixelSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnLayer0
            opacity: 0.7
        }

        Row {
            id: pageDots
            anchors {
                bottom: parent.bottom
                bottomMargin: Math.round(root.height * 0.06)
                horizontalCenter: parent.horizontalCenter
            }
            spacing: 4
            opacity: !root.searching && root.pageCount > 1 ? 1 : 0

            Repeater {
                model: root.pageCount
                delegate: MouseArea {
                    id: dot
                    required property int index
                    implicitWidth: 20
                    implicitHeight: 20
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.goToPage(dot.index)

                    Rectangle {
                        anchors.centerIn: parent
                        implicitWidth: 8
                        implicitHeight: 8
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colOnLayer0
                        opacity: dot.index === pageView.currentIndex ? 0.9 : 0.3
                        Behavior on opacity {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                    }
                }
            }
        }
    }

    // Right-click menu for an app
    Item {
        id: appMenu
        property var entry: null
        property point anchorPoint

        function openAt(source, x, y, entry) {
            appMenu.anchorPoint = source.mapToItem(appMenu, x, y);
            appMenu.entry = entry;
        }

        anchors.fill: parent
        visible: entry !== null

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: appMenu.entry = null
        }

        StyledRectangularShadow {
            target: menuBox
        }

        Rectangle {
            id: menuBox
            x: Math.max(8, Math.min(appMenu.anchorPoint.x, appMenu.width - width - 8))
            y: Math.max(8, Math.min(appMenu.anchorPoint.y, appMenu.height - height - 8))
            color: Config.options.appearance.uiBackground === "oled" ? "#000000" : Appearance.m3colors.m3surfaceContainer
            radius: Appearance.rounding.normal
            implicitWidth: menuColumn.implicitWidth + 8
            implicitHeight: menuColumn.implicitHeight + 8

            ColumnLayout {
                id: menuColumn
                anchors {
                    fill: parent
                    margins: 4
                }
                spacing: 0

                ContextMenuItem {
                    iconName: "open_in_new"
                    label: Translation.tr("Open")
                    onClicked: {
                        const entry = appMenu.entry;
                        appMenu.entry = null;
                        root.launch(entry);
                    }
                }

                // Desktop entry actions, like "New Private Window"
                Repeater {
                    model: appMenu.entry?.actions ?? []
                    delegate: ContextMenuItem {
                        required property var modelData
                        iconSource: modelData.icon ? SystemAppearance.iconPath(modelData.icon, true) : ""
                        iconName: "chevron_right"
                        label: modelData.name
                        onClicked: {
                            modelData.execute();
                            appMenu.entry = null;
                            root.closeRequested();
                        }
                    }
                }

                ContextMenuSeparator {}

                ContextMenuItem {
                    readonly property bool pinned: appMenu.entry !== null && root.pinnedIdFor(appMenu.entry) !== undefined
                    iconName: pinned ? "keep_off" : "keep"
                    label: pinned ? Translation.tr("Unpin from dock") : Translation.tr("Pin to dock")
                    onClicked: {
                        root.togglePin(appMenu.entry);
                        appMenu.entry = null;
                    }
                }

                ContextMenuItem {
                    readonly property bool hidden: appMenu.entry !== null && root.hiddenApps.includes(appMenu.entry.id)
                    iconName: hidden ? "visibility" : "visibility_off"
                    label: hidden ? Translation.tr("Show in Launchpad") : Translation.tr("Hide from Launchpad")
                    onClicked: {
                        root.toggleHidden(appMenu.entry);
                        appMenu.entry = null;
                    }
                }
            }
        }
    }
}
