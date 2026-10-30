import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.models
import qs.modules.ii.dock.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

/**
 * Windows-style start menu: search, pinned apps, every app A-Z, quick actions
 * and recent files, with the user's folders, settings and power options along
 * the bottom. Typing anywhere searches (apps, math, commands, clipboard...).
 */
FocusScope {
    id: root

    property bool shown: false
    property int closeDuration: 160
    // Dock side the menu rises from: bottom | left | right
    property string side: "bottom"
    signal closeRequested()

    readonly property int columns: 6
    readonly property real padding: 22
    readonly property real tileWidth: 98
    readonly property real tileHeight: 86
    readonly property int pinnedRows: 3
    readonly property var options: Config.options.startMenu

    // home | apps (every app, A-Z)
    property string view: "home"
    // 0 = home, 1 = All apps; animated, so the pages slide. A fraction rather than
    // pixels, so the body getting its width when the menu opens doesn't animate.
    property real pagePosition: root.view === "apps" ? 1 : 0
    Behavior on pagePosition {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }
    readonly property string query: searchField.text
    readonly property bool searching: root.query !== ""
    readonly property var results: root.searching ? LauncherSearch.results.slice(0, 30) : []
    readonly property var resultItems: root.results.map(result => ({
        key: `${result.type}|${result.name}|${result.id}`,
        result: result
    }))
    readonly property var allApps: AppSearch.list.filter(app => !app.noDisplay)
        .sort((a, b) => a.name.toLowerCase().localeCompare(b.name.toLowerCase()))
    readonly property var pinned: Launcher.pinnedEntries
    // Keyboard selection in the list that's showing; -1 when nothing is selected
    property int selectedIndex: -1

    // 0 = collapsed into the dock, 1 = open
    property real progress: 0
    // Milliseconds since opening; the contents cascade in row by row
    property real entranceTime: 0
    readonly property bool sideways: root.side !== "bottom"
    // Share of the menu that's showing while collapsed; it grows out of the dock from there
    readonly property real collapsedSize: 0.55

    implicitWidth: root.columns * root.tileWidth + root.padding * 2
    implicitHeight: mainColumn.implicitHeight

    Component.onCompleted: {
        LauncherSearch.query = "";
        searchField.forceActiveFocus();
        if (root.shown) openAnim.start();
    }
    Component.onDestruction: LauncherSearch.query = ""
    onShownChanged: {
        if (root.shown) {
            // Reopened while collapsing
            closeAnim.stop();
            openAnim.restart();
        } else {
            openAnim.stop();
            closeAnim.start();
        }
    }

    // Entrance progress (0-1, eased) of the contents on menu row `row`, top to bottom
    function revealAt(row) {
        const t = Math.max(0, Math.min(1, (root.entranceTime - 40 - row * 26) / 300));
        return 1 - Math.pow(1 - t, 3);
    }

    // Same, but overshoots a little before settling, for icons popping in
    function popAt(row) {
        const t = Math.max(0, Math.min(1, (root.entranceTime - 40 - row * 26) / 380)) - 1;
        return 1 + 2.7 * t * t * t + 1.7 * t * t;
    }

    // Pinned and quick action tiles arrive in a diagonal wave
    function gridRow(firstRow, index, columns) {
        return firstRow + Math.floor(index / columns) + (index % columns) * 0.3;
    }

    onQueryChanged: {
        LauncherSearch.query = root.query;
        // Not root.searching: that binding may not have caught up yet
        root.selectedIndex = root.query !== "" ? 0 : -1;
    }
    onViewChanged: {
        root.selectedIndex = -1;
        appList.positionViewAtBeginning();
    }

    ParallelAnimation {
        id: openAnim
        NumberAnimation {
            target: root
            property: "progress"
            to: 1
            duration: 420
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
        }
        NumberAnimation {
            target: root
            property: "entranceTime"
            from: 0
            to: 800
            duration: 800
        }
    }

    NumberAnimation {
        id: closeAnim
        target: root
        property: "progress"
        to: 0
        duration: root.closeDuration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
    }

    // `active` is read in the tile's binding, so toggles stay current
    readonly property var quickActions: [
        { symbol: "imagesmode", label: Translation.tr("Wallpaper"), run: () => {
            root.closeRequested();
            GlobalStates.wallpaperSelectorOpen = true;
        } },
        { symbol: "screenshot_region", label: Translation.tr("Screenshot"),
            run: () => root.runClosed(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "region", "screenshot"]) },
        { symbol: "colorize", label: Translation.tr("Color picker"), run: () => root.runClosed(["hyprpicker", "-a"]) },
        { symbol: "content_paste", label: Translation.tr("Clipboard"), run: () => root.searchFor(Config.options.search.prefix.clipboard) },
        { symbol: "mood", label: Translation.tr("Emoji"), run: () => root.searchFor(Config.options.search.prefix.emojis) },
        { symbol: "dark_mode", label: Translation.tr("Dark mode"), active: () => Appearance.m3colors.darkmode,
            run: () => Quickshell.execDetached(["bash", "-c",
                `${Directories.wallpaperSwitchScriptPath} --mode ${Appearance.m3colors.darkmode ? "light" : "dark"} --noswitch`]) },
        { symbol: "nightlight", label: Translation.tr("Night light"), active: () => Hyprsunset.temperatureActive,
            run: () => Hyprsunset.toggleTemperature() },
        { symbol: "coffee", label: Translation.tr("Keep awake"), active: () => Idle.inhibit, run: () => Idle.toggleInhibit() }
    ]

    function searchFor(text) {
        searchField.text = text;
        searchField.forceActiveFocus();
    }

    function currentList() {
        return root.searching ? root.results : root.view === "apps" ? root.allApps : root.pinned;
    }

    function moveSelection(delta) {
        const count = root.currentList().length;
        if (count === 0) return;
        root.selectedIndex = root.selectedIndex < 0 ? 0 : Math.max(0, Math.min(count - 1, root.selectedIndex + delta));
        if (root.searching) resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
        else if (root.view === "apps") appList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
        else pinnedFlickable.showRow(Math.floor(root.selectedIndex / root.columns));
    }

    function activate(index) {
        if (root.searching) {
            const result = root.results[index];
            if (!result) return;
            result.execute();
            root.closeRequested();
            return;
        }
        root.launch(root.currentList()[index]);
    }

    function launch(entry) {
        if (!entry) return;
        entry.execute();
        const dockId = root.dockIdFor(entry);
        if (dockId) TaskbarApps.noteLaunch(dockId);
        root.closeRequested();
    }

    // The dock pins by window app ID, which usually matches the desktop entry ID
    // and otherwise its StartupWMClass
    function dockIdFor(entry) {
        return [entry.id, entry.startupClass].find(id => id && TaskbarApps.isPinned(id));
    }

    // Runs after the menu has closed, so it isn't in screenshots or color picks
    function runClosed(command) {
        root.closeRequested();
        Quickshell.execDetached(["bash", "-c", `sleep 0.3; exec "$@"`, "bash"].concat(command));
    }

    function openPath(path) {
        Quickshell.execDetached(["xdg-open", FileUtils.trimFileProtocol(path)]);
        root.closeRequested();
    }

    function handleKey(event) {
        if (contextMenu.entry !== null || powerMenu.open) {
            if (event.key === Qt.Key_Escape) {
                contextMenu.entry = null;
                powerMenu.open = false;
                event.accepted = true;
            }
            return;
        }
        const grid = !root.searching && root.view === "home";
        switch (event.key) {
        case Qt.Key_Escape:
            if (root.searching) searchField.text = "";
            else if (root.view !== "home") root.view = "home";
            else root.closeRequested();
            break;
        case Qt.Key_Down:
            root.moveSelection(grid ? root.columns : 1);
            break;
        case Qt.Key_Up:
            root.moveSelection(grid ? -root.columns : -1);
            break;
        case Qt.Key_Left:
        case Qt.Key_Right:
            if (!grid) return; // Moves the text cursor
            root.moveSelection(event.key === Qt.Key_Left ? -1 : 1);
            break;
        case Qt.Key_Tab:
            if (root.searching) return;
            root.view = root.view === "home" ? "apps" : "home";
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            root.activate(root.selectedIndex);
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    function relativeTime(seconds) {
        const age = Date.now() / 1000 - seconds;
        if (age < 60) return Translation.tr("Just now");
        if (age < 3600) return Translation.tr("%1 min ago").arg(Math.floor(age / 60));
        if (age < 86400) return Translation.tr("%1 h ago").arg(Math.floor(age / 3600));
        if (age < 172800) return Translation.tr("Yesterday");
        return Qt.formatDate(new Date(seconds * 1000), "d MMM");
    }

    function fileSymbol(mime) {
        if (mime.startsWith("image/")) return "image";
        if (mime.startsWith("video/")) return "movie";
        if (mime.startsWith("audio/")) return "music_note";
        if (mime === "application/pdf") return "picture_as_pdf";
        if (/zip|tar|rar|7z|compressed|x-xz|bzip|zstd/.test(mime)) return "folder_zip";
        if (mime.startsWith("text/") || /json|xml|javascript|document|spreadsheet|presentation/.test(mime)) return "description";
        return "draft";
    }

    function folderName(path) {
        const parent = path.split("/").slice(0, -1).join("/");
        const home = FileUtils.trimFileProtocol(Directories.home).replace(/\/$/, "");
        return parent.startsWith(home) ? "~" + parent.slice(home.length) : parent;
    }

    StyledRectangularShadow {
        target: background
        opacity: background.opacity
    }

    // Grows out of the dock: the panel expands away from it while the contents
    // slide out of the dock side, then cascade in row by row. Collapsing reverses it.
    Rectangle {
        id: background
        readonly property real size: root.collapsedSize + (1 - root.collapsedSize) * root.progress
        width: root.sideways ? root.width * background.size : root.width
        height: root.sideways ? root.height : root.height * background.size
        x: root.side === "right" ? root.width - background.width : 0
        y: root.side === "bottom" ? root.height - background.height : 0
        color: Config.options.appearance.uiBackground === "oled" ? "#000000" : Appearance.colors.colLayer0
        radius: Appearance.rounding.windowRounding
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        clip: true
        opacity: Math.min(1, root.progress * 3)

        // Clicking empty space keeps typing going to the search field
        MouseArea {
            anchors.fill: parent
            onPressed: searchField.forceActiveFocus()
        }

        ColumnLayout {
            id: mainColumn
            // Pinned to the side away from the dock, so it slides out as the panel grows
            x: root.side === "left" ? background.width - root.width : 0
            y: 0
            width: root.width
            spacing: 0
            opacity: root.shown ? 1 : root.progress

            // Search
            Rectangle {
                Layout.fillWidth: true
                Layout.margins: root.padding
                Layout.bottomMargin: 14
                implicitHeight: 42
                opacity: root.revealAt(0)
                transform: Translate { y: (1 - root.revealAt(0)) * 14 }
                // Zooms in a touch as it arrives
                scale: 0.92 + 0.08 * root.revealAt(0)
                radius: Appearance.rounding.full
                color: Appearance.colors.colLayer1
                border.width: searchField.activeFocus ? 2 : 1
                border.color: searchField.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border

                RowLayout {
                    anchors {
                        fill: parent
                        leftMargin: 14
                        rightMargin: 8
                    }
                    spacing: 8

                    MaterialSymbol {
                        text: "search"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer1
                    }

                    TextField {
                        id: searchField
                        Layout.fillWidth: true
                        focus: true
                        background: null
                        padding: 0
                        placeholderText: Translation.tr("Search apps, settings, math, commands…")
                        placeholderTextColor: Appearance.colors.colSubtext
                        color: Appearance.colors.colOnLayer1
                        selectedTextColor: Appearance.colors.colOnSecondaryContainer
                        selectionColor: Appearance.colors.colSecondaryContainer
                        renderType: Text.NativeRendering
                        font {
                            family: Appearance.font.family.main
                            pixelSize: Appearance.font.pixelSize.small
                            variableAxes: Appearance.font.variableAxes.main
                        }
                        Keys.onPressed: event => root.handleKey(event)
                    }

                    RippleButton {
                        visible: root.searching
                        focusPolicy: Qt.NoFocus
                        implicitWidth: 28
                        implicitHeight: 28
                        buttonRadius: Appearance.rounding.full
                        onClicked: searchField.text = ""
                        contentItem: MaterialSymbol {
                            text: "close"
                            iconSize: 18
                            horizontalAlignment: Text.AlignHCenter
                            color: Appearance.colors.colOnLayer1
                        }
                    }
                }
            }

            // Body: home, all apps or search results, at the height of home
            Item {
                id: body
                Layout.fillWidth: true
                Layout.leftMargin: root.padding
                Layout.rightMargin: root.padding
                implicitHeight: Math.max(homeView.implicitHeight, 400)
                // Pages slide past the edges
                clip: true

                ColumnLayout {
                    id: homeView
                    readonly property bool current: !root.searching && root.view === "home"
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                    }
                    spacing: 6
                    enabled: homeView.current
                    visible: opacity > 0
                    // Fades for search; between pages it only slides
                    opacity: root.searching ? 0 : 1
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    // Slides off to the left as All apps comes in from the right
                    transform: Translate {
                        x: -root.pagePosition * body.width
                    }

                    SectionHeader {
                        reveal: root.revealAt(1)
                        title: Translation.tr("Pinned")
                        actionText: Translation.tr("All apps")
                        actionSymbol: "chevron_right"
                        onActionClicked: root.view = "apps"
                    }

                    StyledFlickable {
                        id: pinnedFlickable
                        Layout.fillWidth: true
                        implicitHeight: root.pinnedRows * root.tileHeight
                        contentHeight: pinnedGrid.implicitHeight
                        clip: true

                        function showRow(row) {
                            const top = row * root.tileHeight;
                            if (top < contentY) contentY = top;
                            else if (top + root.tileHeight > contentY + height) contentY = top + root.tileHeight - height;
                        }

                        Grid {
                            id: pinnedGrid
                            columns: root.columns

                            Repeater {
                                model: root.pinned
                                delegate: StartMenuAppTile {
                                    id: tile
                                    required property var modelData
                                    required property int index
                                    readonly property real row: root.gridRow(2, index, root.columns)
                                    width: root.tileWidth
                                    height: root.tileHeight
                                    entry: modelData
                                    reveal: root.revealAt(tile.row)
                                    pop: root.popAt(tile.row)
                                    selected: !root.searching && root.view === "home" && root.selectedIndex === index
                                    onClicked: root.launch(modelData)
                                    onMenuRequested: (x, y) => contextMenu.openAt(tile, x, y, modelData)
                                }
                            }
                        }

                        StyledText {
                            x: 20
                            y: (pinnedFlickable.height - height) / 2
                            width: pinnedFlickable.width - 40
                            visible: root.pinned.length === 0
                            opacity: root.revealAt(2)
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            text: Translation.tr("Right-click an app in All apps to pin it here")
                            color: Appearance.colors.colSubtext
                        }
                    }

                    SectionHeader {
                        visible: root.options.showQuickActions
                        reveal: root.revealAt(5)
                        Layout.topMargin: 8
                        title: Translation.tr("Quick actions")
                    }

                    GridLayout {
                        visible: root.options.showQuickActions
                        Layout.fillWidth: true
                        columns: 4
                        rowSpacing: 6
                        columnSpacing: 6

                        Repeater {
                            model: root.quickActions
                            delegate: StartMenuActionTile {
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                reveal: root.revealAt(root.gridRow(6, index, 4))
                                symbol: modelData.symbol
                                label: modelData.label
                                active: modelData.active?.() ?? false
                                onClicked: modelData.run()
                            }
                        }
                    }

                    SectionHeader {
                        visible: root.options.showRecent
                        reveal: root.revealAt(8)
                        Layout.topMargin: 8
                        title: Translation.tr("Recent")
                        actionText: Translation.tr("Downloads")
                        actionSymbol: "folder_open"
                        onActionClicked: root.openPath(Directories.downloads)
                    }

                    GridLayout {
                        visible: root.options.showRecent
                        Layout.fillWidth: true
                        Layout.bottomMargin: 6
                        // Room for three rows, so the menu doesn't change height as files load
                        Layout.minimumHeight: 3 * 48 + 2 * rowSpacing
                        Layout.alignment: Qt.AlignTop
                        columns: 2
                        rowSpacing: 2
                        columnSpacing: 6

                        Repeater {
                            model: Launcher.recentFiles
                            delegate: StartMenuListRow {
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                Layout.alignment: Qt.AlignTop
                                reveal: root.revealAt(root.gridRow(9, index, 2))
                                symbol: root.fileSymbol(modelData.mime)
                                symbolColor: Appearance.colors.colPrimary
                                title: modelData.name
                                subtitle: `${root.relativeTime(modelData.time)} · ${root.folderName(modelData.path)}`
                                onClicked: root.openPath(modelData.path)
                            }
                        }

                        StyledText {
                            Layout.columnSpan: 2
                            Layout.fillWidth: true
                            Layout.topMargin: 12
                            visible: Launcher.recentFiles.length === 0
                            opacity: root.revealAt(9)
                            horizontalAlignment: Text.AlignHCenter
                            text: Translation.tr("Files you open show up here")
                            color: Appearance.colors.colSubtext
                        }
                    }
                }

                // Every app, A-Z
                ColumnLayout {
                    id: appsView
                    readonly property bool current: !root.searching && root.view === "apps"
                    anchors.fill: parent
                    spacing: 6
                    enabled: appsView.current
                    visible: opacity > 0
                    opacity: root.searching ? 0 : 1
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    transform: Translate {
                        x: (1 - root.pagePosition) * body.width
                    }

                    SectionHeader {
                        title: Translation.tr("All apps")
                        actionText: Translation.tr("Back")
                        actionSymbol: "chevron_left"
                        actionSymbolFirst: true
                        onActionClicked: root.view = "home"
                    }

                    ListView {
                        id: appList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.bottomMargin: 6
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        model: root.allApps
                        ScrollBar.vertical: StyledScrollBar {}

                        delegate: ColumnLayout {
                            id: appRow
                            required property var modelData
                            required property int index
                            readonly property string letter: root.letterOf(modelData)
                            width: appList.width - 12
                            spacing: 0

                            // A letter heading above the first app of each letter
                            StyledText {
                                visible: appRow.index === 0 || root.letterOf(root.allApps[appRow.index - 1]) !== appRow.letter
                                Layout.leftMargin: 12
                                Layout.topMargin: appRow.index === 0 ? 2 : 10
                                Layout.bottomMargin: 2
                                text: appRow.letter
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colPrimary
                            }

                            StartMenuListRow {
                                id: appButton
                                Layout.fillWidth: true
                                iconUrl: Launcher.iconFor(appRow.modelData)
                                title: appRow.modelData.name
                                selected: root.selectedIndex === appRow.index
                                verb: Translation.tr("Open")
                                onClicked: root.launch(appRow.modelData)
                                onMenuRequested: (x, y) => contextMenu.openAt(appButton, x, y, appRow.modelData)
                            }
                        }
                    }
                }

                // Search results, in a card that grows and shrinks with them
                ColumnLayout {
                    id: searchView
                    anchors.fill: parent
                    spacing: 6
                    enabled: root.searching
                    visible: opacity > 0
                    opacity: root.searching ? 1 : 0
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    transform: Translate {
                        y: root.searching ? 0 : 16
                        Behavior on y {
                            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                        }
                    }

                    SectionHeader {
                        id: searchHeader
                        title: root.results.length > 0 ? Translation.tr("Best match") : Translation.tr("No results")
                    }

                    Rectangle {
                        id: resultCard
                        Layout.fillWidth: true
                        implicitHeight: Math.min(searchView.height - searchHeader.height - searchView.spacing - 6,
                            root.results.length > 0 ? resultList.contentHeight + resultList.topMargin + resultList.bottomMargin : 0)
                        Behavior on implicitHeight {
                            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                        }
                        radius: Appearance.rounding.normal
                        color: Appearance.colors.colLayer1
                        clip: true

                        ListView {
                            id: resultList
                            anchors.fill: parent
                            topMargin: 4
                            bottomMargin: 4
                            spacing: 2
                            boundsBehavior: Flickable.StopAtBounds
                            ScrollBar.vertical: StyledScrollBar {}
                            // Results matched by key, so the ones that stay keep their place
                            // and only new or dropped ones animate, as in the overview
                            model: ScriptModel {
                                values: root.resultItems
                                objectProp: "key"
                            }

                            add: Transition {
                                NumberAnimation {
                                    property: "opacity"
                                    from: 0
                                    to: 1
                                    duration: Appearance.animation.elementMoveFast.duration
                                }
                                NumberAnimation {
                                    property: "scale"
                                    from: 0.85
                                    to: 1
                                    duration: Appearance.animation.elementMove.duration
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                                }
                            }
                            remove: Transition {
                                NumberAnimation {
                                    property: "opacity"
                                    to: 0
                                    duration: Appearance.animation.elementMoveFast.duration
                                }
                                NumberAnimation {
                                    property: "x"
                                    to: 48
                                    duration: Appearance.animation.elementMoveFast.duration
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
                                }
                            }
                            displaced: Transition {
                                NumberAnimation {
                                    property: "y"
                                    duration: Appearance.animation.elementMove.duration
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                                }
                                // Finishes an entrance this interrupted
                                NumberAnimation {
                                    properties: "opacity,scale"
                                    to: 1
                                    duration: Appearance.animation.elementMoveFast.duration
                                }
                            }

                            delegate: StartMenuListRow {
                                id: resultRow
                                required property var modelData
                                required property int index
                                readonly property var result: modelData.result
                                readonly property var entry: result.id ? DesktopEntries.byId(result.id) : null
                                x: 4
                                width: resultList.width - 8
                                // The best match gets a bigger icon. Rows keep one height: a row
                                // that changes height while the list animates lands on its neighbour.
                                iconSize: index === 0 ? 34 : 28
                                implicitHeight: 50
                                iconUrl: result.iconType === LauncherSearchResult.IconType.System
                                    ? Launcher.iconFor({ icon: result.iconName }) : ""
                                symbol: result.iconType === LauncherSearchResult.IconType.Material ? result.iconName
                                    : result.iconType === LauncherSearchResult.IconType.None ? "search" : ""
                                glyph: result.iconType === LauncherSearchResult.IconType.Text ? result.iconName : ""
                                title: result.name
                                subtitle: result.type ?? ""
                                verb: result.verb ?? ""
                                selected: root.selectedIndex === index
                                onHoveredChanged: if (hovered) root.selectedIndex = index
                                onClicked: root.activate(index)
                                onMenuRequested: (x, y) => {
                                    if (resultRow.entry) contextMenu.openAt(resultRow, x, y, resultRow.entry);
                                }
                            }
                        }
                    }

                    Item {
                        Layout.fillHeight: true
                    }
                }
            }

            // Footer: user, folders, settings and power
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 62
                color: Appearance.colors.colLayer1
                opacity: root.revealAt(12)

                Rectangle {
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                    }
                    implicitHeight: 1
                    color: Appearance.colors.colLayer0Border
                }

                RowLayout {
                    anchors {
                        fill: parent
                        leftMargin: root.padding
                        rightMargin: root.padding - 6
                    }
                    spacing: 4

                    UserAvatar {
                        implicitWidth: 34
                        implicitHeight: 34
                        iconSize: 24
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 8
                        spacing: -2
                        StyledText {
                            Layout.fillWidth: true
                            text: SystemInfo.username
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Up %1").arg(DateTime.uptime)
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }

                    FooterButton {
                        symbol: "folder"
                        tooltip: Translation.tr("Files")
                        onClicked: root.openPath(Directories.home)
                    }
                    FooterButton {
                        symbol: "download"
                        tooltip: Translation.tr("Downloads")
                        onClicked: root.openPath(Directories.downloads)
                    }
                    FooterButton {
                        symbol: "image"
                        tooltip: Translation.tr("Pictures")
                        onClicked: root.openPath(Directories.pictures)
                    }
                    FooterButton {
                        symbol: "settings"
                        tooltip: Translation.tr("Settings")
                        onClicked: {
                            root.closeRequested();
                            GlobalStates.settingsOpen = true;
                        }
                    }
                    FooterButton {
                        id: powerButton
                        symbol: "power_settings_new"
                        tooltip: Translation.tr("Power")
                        toggled: powerMenu.open
                        onClicked: powerMenu.open = !powerMenu.open
                    }
                }
            }
        }

        // Power options, above the power button
        Item {
            id: powerMenu
            property bool open: false
            anchors.fill: parent
            visible: powerMenu.open

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onPressed: powerMenu.open = false
            }

            StyledRectangularShadow {
                target: powerBox
            }

            Rectangle {
                id: powerBox
                anchors {
                    right: parent.right
                    bottom: parent.bottom
                    rightMargin: 12
                    bottomMargin: 62 + 6
                }
                implicitWidth: powerContent.implicitWidth + 24
                implicitHeight: powerContent.implicitHeight + 24
                radius: Appearance.rounding.normal
                color: Config.options.appearance.uiBackground === "oled" ? "#000000" : Appearance.m3colors.m3surfaceContainer
                border.width: 1
                border.color: Appearance.colors.colLayer0Border

                MouseArea {
                    anchors.fill: parent
                }

                PowerPopup {
                    id: powerContent
                    anchors.centerIn: parent
                    onChosen: () => root.closeRequested()
                }
            }
        }

        // Right-click menu for an app
        Item {
            id: contextMenu
            property var entry: null
            property point anchorPoint
            readonly property bool pinnedToStart: contextMenu.entry !== null && Launcher.isPinned(contextMenu.entry)

            function openAt(source, x, y, entry) {
                contextMenu.anchorPoint = source.mapToItem(contextMenu, x, y);
                contextMenu.entry = entry;
            }

            anchors.fill: parent
            visible: contextMenu.entry !== null

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onPressed: contextMenu.entry = null
            }

            StyledRectangularShadow {
                target: menuBox
            }

            Rectangle {
                id: menuBox
                x: Math.max(8, Math.min(contextMenu.anchorPoint.x, contextMenu.width - width - 8))
                y: Math.max(8, Math.min(contextMenu.anchorPoint.y, contextMenu.height - height - 8))
                color: Config.options.appearance.uiBackground === "oled" ? "#000000" : Appearance.m3colors.m3surfaceContainer
                radius: Appearance.rounding.normal
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
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
                            const entry = contextMenu.entry;
                            contextMenu.entry = null;
                            root.launch(entry);
                        }
                    }

                    // Desktop entry actions, like "New Private Window"
                    Repeater {
                        model: contextMenu.entry?.actions ?? []
                        delegate: ContextMenuItem {
                            required property var modelData
                            iconSource: modelData.icon ? SystemAppearance.iconPath(modelData.icon, true) : ""
                            iconName: "chevron_right"
                            label: modelData.name
                            onClicked: {
                                modelData.execute();
                                contextMenu.entry = null;
                                root.closeRequested();
                            }
                        }
                    }

                    ContextMenuSeparator {}

                    ContextMenuItem {
                        iconName: contextMenu.pinnedToStart ? "keep_off" : "keep"
                        label: contextMenu.pinnedToStart ? Translation.tr("Unpin from Start") : Translation.tr("Pin to Start")
                        onClicked: {
                            Launcher.togglePin(contextMenu.entry);
                            contextMenu.entry = null;
                        }
                    }

                    ContextMenuItem {
                        visible: contextMenu.pinnedToStart && root.pinned[0]?.id !== contextMenu.entry?.id
                        iconName: "vertical_align_top"
                        label: Translation.tr("Move to front")
                        onClicked: {
                            Launcher.moveToFront(contextMenu.entry);
                            contextMenu.entry = null;
                        }
                    }

                    ContextMenuItem {
                        readonly property bool inDock: contextMenu.entry !== null && root.dockIdFor(contextMenu.entry) !== undefined
                        iconName: inDock ? "keep_off" : "keep"
                        label: inDock ? Translation.tr("Unpin from dock") : Translation.tr("Pin to dock")
                        onClicked: {
                            TaskbarApps.togglePin(root.dockIdFor(contextMenu.entry) ?? contextMenu.entry.id);
                            contextMenu.entry = null;
                        }
                    }
                }
            }
        }
    }

    function letterOf(entry) {
        const first = (entry?.name ?? "").charAt(0).toUpperCase();
        return first !== "" && first.toLowerCase() !== first.toUpperCase() ? first : "#";
    }

    component SectionHeader: RowLayout {
        id: header
        property real reveal: 1
        property string title
        property string actionText: ""
        property string actionSymbol: ""
        property bool actionSymbolFirst: false
        signal actionClicked()
        Layout.fillWidth: true
        Layout.leftMargin: 10
        implicitHeight: 30
        opacity: header.reveal
        transform: Translate { y: (1 - header.reveal) * 14 }

        StyledText {
            Layout.fillWidth: true
            text: header.title
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnLayer0
        }

        RippleButton {
            visible: header.actionText !== ""
            focusPolicy: Qt.NoFocus
            implicitHeight: 28
            horizontalPadding: 12
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colLayer1
            colBackgroundHover: Appearance.colors.colLayer1Hover
            colRipple: Appearance.colors.colLayer1Active
            onClicked: header.actionClicked()
            contentItem: RowLayout {
                spacing: 2
                layoutDirection: header.actionSymbolFirst ? Qt.LeftToRight : Qt.RightToLeft
                MaterialSymbol {
                    text: header.actionSymbol
                    iconSize: 18
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    text: header.actionText
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer1
                }
            }
        }
    }

    component FooterButton: RippleButton {
        id: footerButton
        property string symbol
        property string tooltip
        focusPolicy: Qt.NoFocus
        implicitWidth: 38
        implicitHeight: 38
        buttonRadius: Appearance.rounding.full
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colBackgroundToggled: Appearance.colors.colSecondaryContainer
        colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
        contentItem: MaterialSymbol {
            text: footerButton.symbol
            iconSize: 20
            horizontalAlignment: Text.AlignHCenter
            color: footerButton.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
        }
        StyledToolTip {
            text: footerButton.tooltip
        }
    }
}
