import qs.modules.common
import qs.modules.common.functions
// Quickshell only registers directories something imports; the widgets are loaded by URL
import qs.modules.ii.dock.widgets
import QtQuick
import QtQuick.Layouts

/**
 * A row of dock widgets (a column on a side dock), used inside the dock and in
 * the corner islands. Neighbours of the same group (DockWidgets) merge into one
 * segmented pill.
 */
Item {
    id: root

    property var widgets: []
    property bool inDock: true
    readonly property bool holdOpen: grid.children.some(child => child.item?.holdOpen ?? false)
    // Along the dock; 0 while nothing in it is showing
    readonly property real length: DockStyle.vertical ? grid.implicitHeight : grid.implicitWidth

    // Runs of two or more showing widgets of the same group, as lists of loaders
    readonly property var runs: {
        const result = [];
        let current = null;
        for (const child of grid.children) {
            if (child.widgetId === undefined || !(child.item?.available ?? false)) continue;
            const group = DockWidgets.find(child.widgetId)?.group ?? "";
            if (group !== "" && current?.group === group) {
                current.loaders.push(child);
            } else {
                current = { group: group, loaders: [child] };
                result.push(current);
            }
        }
        return result.filter(run => run.group !== "" && run.loaders.length > 1);
    }

    function groupPosition(loader) {
        for (const run of root.runs) {
            const index = run.loaders.indexOf(loader);
            if (index < 0) continue;
            return index === 0 ? "first" : index === run.loaders.length - 1 ? "last" : "middle";
        }
        return "";
    }

    visible: root.length > 0
    Layout.fillHeight: !DockStyle.vertical
    Layout.fillWidth: DockStyle.vertical
    implicitWidth: grid.implicitWidth
    implicitHeight: grid.implicitHeight

    // Shared pills behind grouped widgets
    Repeater {
        model: root.runs.length
        delegate: Rectangle {
            id: groupPill
            required property int index
            readonly property var run: root.runs[index] ?? null
            readonly property Item first: run?.loaders[0] ?? null
            readonly property Item last: run?.loaders[run.loaders.length - 1] ?? null
            readonly property Item button: first?.item ?? null

            visible: first !== null && button !== null
            x: DockStyle.vertical ? (first?.x ?? 0) + (button?.leftInset ?? 0) : (first?.x ?? 0)
            y: DockStyle.vertical ? (first?.y ?? 0) : (first?.y ?? 0) + (button?.topInset ?? 0)
            width: DockStyle.vertical ? (button?.background.width ?? 0) : (last ? last.x + last.width - x : 0)
            height: DockStyle.vertical ? (last ? last.y + last.height - y : 0) : (button?.background.height ?? 0)
            radius: DockStyle.material ? Math.min(width, height) / 2 : Appearance.rounding.normal
            color: DockStyle.material ? (button?.tone ?? Appearance.colors.colSecondaryContainer) : Appearance.colors.colLayer2
            transform: Translate {
                x: root.inDock && DockStyle.magnifying ? DockMagnify.shiftOf(groupPill.first) : 0
            }
        }
    }

    GridLayout {
        id: grid
        anchors.fill: parent
        columns: DockStyle.vertical ? 1 : -1
        rowSpacing: DockStyle.spacing
        columnSpacing: DockStyle.spacing

        Repeater {
            model: root.widgets
            delegate: Loader {
                id: loader
                required property string modelData
                readonly property string widgetId: loader.modelData
                readonly property string groupPosition: root.groupPosition(loader)
                // Grouped widgets touch
                readonly property real alongStart: loader.groupPosition === "middle" || loader.groupPosition === "last" ? -DockStyle.spacing : 0
                readonly property real innerMargin: loader.item?.innerMargin ?? DockStyle.pinnedInnerMargin
                readonly property real outerMargin: loader.item?.outerMargin ?? 0

                visible: loader.item?.available ?? false
                Layout.fillHeight: !DockStyle.vertical
                Layout.fillWidth: DockStyle.vertical
                Layout.topMargin: DockStyle.mTop(loader.innerMargin, loader.outerMargin, loader.alongStart)
                Layout.bottomMargin: DockStyle.mBottom(loader.innerMargin, loader.outerMargin)
                Layout.leftMargin: DockStyle.mLeft(loader.innerMargin, loader.outerMargin, loader.alongStart)
                Layout.rightMargin: DockStyle.mRight(loader.innerMargin, loader.outerMargin)

                Component.onCompleted: {
                    const info = DockWidgets.find(loader.modelData);
                    if (info)
                        loader.setSource(Qt.resolvedUrl(`widgets/${info.file}.qml`), { inDock: root.inDock, toneName: info.tone ?? "secondaryContainer" });
                }

                Binding {
                    target: loader.item
                    property: "groupPosition"
                    value: loader.groupPosition
                    when: loader.item !== null && loader.item.groupPosition !== undefined
                }
            }
        }
    }
}
