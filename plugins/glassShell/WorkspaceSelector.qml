import QtQuick
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Hyprland
import qs.Common
import qs.Services

// The owning overlay provides screen, focus and Alt-release handling. This
// component owns only workspace selection and the capture lifetime.
Item {
    id: root
    property bool open: false
    property var settings: ({})
    property var targetScreen: null
    signal closeRequested()
    signal settingsRequested()
    focus: open
    Keys.onReturnPressed: event => { confirm(); event.accepted = true; }
    Keys.onEnterPressed: event => { confirm(); event.accepted = true; }
    Keys.onEscapePressed: event => { cancel(); event.accepted = true; }

    readonly property var options: settings?.switcher ?? settings?.workspaceSelector ?? settings ?? ({})
    readonly property string displayMode: ["wheel", "slice", "grid", "compact"].includes(options.displayMode) ? options.displayMode : "wheel"
    readonly property real dimOpacity: Math.max(0, Math.min(1, Number(options.dimOpacity ?? 0.3)))
    readonly property real inactiveDimOpacity: Math.max(0, Math.min(1, Number(options.inactiveDimOpacity ?? 0.25)))
    readonly property real previewBlur: Math.max(0, Math.min(32, Number(options.previewBlur ?? 0)))
    readonly property real hoverScale: Math.max(1, Math.min(1.2, Number(options.hoverScale ?? 1.06)))
    readonly property real monitorScale: Math.max(0.75, Math.min(1.5,
        Math.min((targetScreen?.width ?? width) / 1920, (targetScreen?.height ?? height) / 1080)))
    readonly property real uiScale: Math.max(0.5, Math.min(3, Number(options.uiScale ?? 1) || 1)) * monitorScale
    readonly property real effectiveRadius: Math.max(0, Number(options.cornerRadius ?? 14))
    readonly property var allWorkspaces: Hyprland.workspaces?.values ?? []
    readonly property var workspaceRows: {
        const found = {};
        for (let id = 1; id <= 6; id++) found[id] = null;
        for (const ws of allWorkspaces) {
            if (ws && Number.isInteger(ws.id) && ws.id > 0)
                found[ws.id] = ws;
        }
        return Object.keys(found).map(Number).sort((a, b) => a - b).map(id => ({ id: id, workspace: found[id] }));
    }
    // Hyprland workspace objects do not expose a reliable `active` flag.
    // A desktop is current when it is the active workspace of either monitor.
    readonly property var activeWorkspaceIds: (Hyprland.monitors?.values ?? [])
        .map(monitor => monitor?.activeWorkspace?.id)
        .filter(id => Number.isInteger(id) && id > 0)
    function isCurrentWorkspace(id) {
        return activeWorkspaceIds.includes(id) || Hyprland.focusedWorkspace?.id === id;
    }
    function titlesFor(workspace) {
        return (workspace?.toplevels?.values ?? []).map(window =>
            window?.wayland?.title || window?.lastIpcObject?.title ||
            window?.lastIpcObject?.class || window?.wayland?.appId || "Вікно");
    }
    property int selectedId: -1
    readonly property int selectedIndex: workspaceRows.findIndex(row => row.id === selectedId)

    function option(name, fallback, minimum) {
        const value = Number(options[name]);
        return Number.isFinite(value) ? Math.max(minimum, value) : fallback;
    }
    function scaledOption(name, fallback, minimum) {
        return Math.max(minimum, option(name, fallback, minimum) * uiScale);
    }
    function monitorNameFor(id, workspace) {
        return workspace?.monitor?.name ?? targetScreen?.name ?? "";
    }
    function monitorIpcFor(id, workspace) {
        const name = monitorNameFor(id, workspace);
        const monitor = workspace?.monitor ?? Hyprland.monitors?.values?.find(mon => mon?.name === name);
        return monitor?.lastIpcObject ?? null;
    }
    function choose(id) {
        if (workspaceRows.some(row => row.id === id)) selectedId = id;
    }
    function next() {
        if (!workspaceRows.length) return;
        const idx = selectedIndex;
        selectedId = workspaceRows[(idx + 1) % workspaceRows.length].id;
    }
    function prev() {
        if (!workspaceRows.length) return;
        const idx = selectedIndex < 0 ? 0 : selectedIndex;
        selectedId = workspaceRows[(idx - 1 + workspaceRows.length) % workspaceRows.length].id;
    }
    function confirm() {
        if (!open) return;
        const id = selectedId;
        if (workspaceRows.some(row => row.id === id))
            HyprlandService.focusWorkspace(id);
        closeRequested();
    }
    function cancel() {
        if (open) closeRequested();
    }
    onOpenChanged: {
        if (!open) return;
        Hyprland.refreshMonitors();
        Hyprland.refreshWorkspaces();
        Hyprland.refreshToplevels();
        selectedId = Hyprland.focusedWorkspace?.id ?? (targetScreen ? Hyprland.monitors?.values?.find(mon => mon.name === targetScreen.name)?.activeWorkspace?.id : -1) ?? 1;
        if (!workspaceRows.some(row => row.id === selectedId)) selectedId = 1;
        Qt.callLater(() => { if (root.open) root.forceActiveFocus(); });
    }
    onWorkspaceRowsChanged: {
        if (open && !workspaceRows.some(row => row.id === selectedId))
            selectedId = Hyprland.focusedWorkspace?.id ?? 1;
    }
    visible: open
    clip: true

    readonly property real availableWidth: Math.max(1, width - 40)
    readonly property real availableHeight: Math.max(1, height - 48)
    readonly property real sliceHeight: Math.min(availableHeight, scaledOption("sliceHeight", 520, 64))
    readonly property real sliceExpandedHeight: Math.min(availableHeight, scaledOption("sliceExpandedHeight", 520, 64))
    readonly property real sliceWidth: Math.min(availableWidth, scaledOption("sliceWidth", 135, 30))
    readonly property real sliceExpandedWidth: Math.min(availableWidth, scaledOption("sliceExpandedWidth", 924, 96))
    readonly property real sliceStep: Math.max(20, sliceWidth + option("sliceSpacing", -22, -10000) * uiScale)
    readonly property int sliceVisibleCount: option("sliceVisibleCount", 12, 1)
    readonly property real wheelRadius: Math.min(scaledOption("wheelOuterRadius", 520, 80), availableWidth / 2, availableHeight / 2)
    readonly property real wheelInnerRadius: Math.min(wheelRadius - 12, Math.max(24, scaledOption("wheelInnerRadius", 135, 24)))
    readonly property int gridColumns: option("gridColumns", 5, 1)
    readonly property int gridRows: option("gridRows", 4, 1)
    readonly property real gridWidth: scaledOption("gridCellWidth", 240, 64)
    readonly property real gridHeight: scaledOption("gridCellHeight", 170, 52)
    readonly property real gridSpacing: scaledOption("gridSpacing", 14, 0)
    readonly property real compactWidth: scaledOption("compactCellWidth", 92, 44)
    readonly property real compactHeight: scaledOption("compactCellHeight", 110, 40)
    readonly property real compactSpacing: scaledOption("compactSpacing", 8, 0)

    // A sector's bounding box includes its outer arc extrema, not merely its
    // center: one complete desktop image is cropped by the sector mask.
    function sectorBounds(index, count) {
        const gap = count > 1 ? Math.min(360 / count * 0.18, option("wheelGap", 0, 0)) : 0;
        const from = option("wheelStartAngle", 90, -360) + index * 360 / count + gap / 2;
        const to = option("wheelStartAngle", 90, -360) + (index + 1) * 360 / count - gap / 2;
        const angles = [from, to];
        for (let quadrant = Math.ceil(from / 90); quadrant * 90 < to; quadrant++) angles.push(quadrant * 90);
        let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
        for (const angle of angles) {
            for (const radius of [wheelInnerRadius, wheelRadius]) {
                const x = radius * Math.cos(angle * Math.PI / 180);
                const y = radius * Math.sin(angle * Math.PI / 180);
                minX = Math.min(minX, x); maxX = Math.max(maxX, x);
                minY = Math.min(minY, y); maxY = Math.max(maxY, y);
            }
        }
        return { x: minX - 2, y: minY - 2, width: maxX - minX + 4, height: maxY - minY + 4, start: from, end: to };
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.withAlpha(Theme.surface, root.dimOpacity)
        MouseArea { anchors.fill: parent; onClicked: root.cancel() }
    }

    Item {
        id: wheel
        anchors.centerIn: parent
        width: root.wheelRadius * 2
        height: width
        visible: root.displayMode === "wheel"
        Repeater {
            model: root.open && wheel.visible ? root.workspaceRows : []
            delegate: WorkspaceTile {
                required property var modelData
                required property int index
                readonly property var sector: root.sectorBounds(index, root.workspaceRows.length)
                readonly property var workspace: modelData.workspace
                workspaceId: modelData.id
                workspaceObj: workspace
                monitorName: root.monitorNameFor(workspaceId, workspace)
                monitorIpc: root.monitorIpcFor(workspaceId, workspace)
                capturing: root.open
                selected: root.selectedId === workspaceId
                activeWorkspace: root.isCurrentWorkspace(workspaceId)
                shape: "wheel"
                dimOpacity: root.inactiveDimOpacity
                previewBlur: root.previewBlur
                hoverScale: root.hoverScale
                labelScale: root.uiScale
                z: hovering ? 2 : selected ? 1 : 0
                x: wheel.width / 2 + sector.x
                y: wheel.height / 2 + sector.y
                width: sector.width
                height: sector.height
                centerX: -sector.x
                centerY: -sector.y
                outerRadius: root.wheelRadius
                innerRadius: root.wheelInnerRadius
                startAngle: sector.start
                endAngle: sector.end
                onHovered: root.choose(workspaceId)
                onActivated: { root.choose(workspaceId); root.confirm(); }
            }
        }
        Rectangle {
            anchors.centerIn: parent
            width: root.wheelInnerRadius * 2 - 8
            height: width
            radius: width / 2
            color: Theme.surfaceContainer
            border.width: 1
            border.color: Theme.primary
            Column {
                anchors.centerIn: parent
                width: parent.width * .8
                spacing: 4
                readonly property var row: root.workspaceRows.find(item => item.id === root.selectedId)
                readonly property var titles: root.titlesFor(row?.workspace)
                Text {
                    width: parent.width
                    text: "Стіл " + (root.selectedId > 0 ? root.selectedId : "—") + (parent.row?.workspace?.name && parent.row.workspace.name !== String(root.selectedId) ? " · " + parent.row.workspace.name : "")
                    color: Theme.surfaceText
                    font.pixelSize: Math.max(18, 19 * root.uiScale)
                    font.bold: true
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                }
                Text {
                    width: parent.width
                    text: root.monitorNameFor(root.selectedId, parent.row?.workspace) + " · " + parent.titles.length + " вікон"
                    color: Theme.surfaceText
                    font.pixelSize: Math.max(12, 12 * root.uiScale)
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                }
                Text {
                    width: parent.width
                    text: (parent.titles.slice(0, 3).join("\n") || "Немає вікон") + (parent.titles.length > 3 ? "\n+" + (parent.titles.length - 3) : "")
                    color: Theme.surfaceText
                    font.pixelSize: Math.max(12, 12 * root.uiScale)
                    maximumLineCount: 4
                    wrapMode: Text.WrapAnywhere
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                    Controls.ToolTip.visible: centerHover.hovered && parent.titles.length > 0
                    Controls.ToolTip.text: parent.titles.join("\n")
                    HoverHandler { id: centerHover }
                }
                Text {
                    width: parent.width
                    text: root.isCurrentWorkspace(root.selectedId) ? "Зараз на екрані" : "Enter — перейти"
                    color: Theme.primary
                    font.pixelSize: Math.max(12, 12 * root.uiScale)
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }

    Item {
        id: slices
        anchors.centerIn: parent
        width: Math.min(root.availableWidth, root.scaledOption("cardWidth", 1600, 200))
        height: Math.max(root.sliceHeight, root.sliceExpandedHeight)
        visible: root.displayMode === "slice"
        Repeater {
            model: root.open && slices.visible ? root.workspaceRows : []
            delegate: WorkspaceTile {
                required property var modelData
                required property int index
                readonly property var workspace: modelData.workspace
                readonly property int difference: index - root.selectedIndex
                workspaceId: modelData.id
                workspaceObj: workspace
                monitorName: root.monitorNameFor(workspaceId, workspace)
                monitorIpc: root.monitorIpcFor(workspaceId, workspace)
                capturing: root.open && Math.abs(difference) < root.sliceVisibleCount
                visible: Math.abs(difference) < root.sliceVisibleCount
                selected: root.selectedId === workspaceId
                activeWorkspace: root.isCurrentWorkspace(workspaceId)
                shape: "slice"
                skew: Math.max(-width * 0.4, Math.min(width * 0.4, height * Math.tan(root.option("sliceSkewAngle", 0, -45) * Math.PI / 180)))
                dimOpacity: root.inactiveDimOpacity
                previewBlur: root.previewBlur
                hoverScale: root.hoverScale
                labelScale: root.uiScale
                cornerRadius: root.effectiveRadius
                x: (slices.width - root.sliceExpandedWidth) / 2 + (difference > 0 ? root.sliceExpandedWidth - root.sliceStep + difference * root.sliceStep : difference * root.sliceStep)
                y: (slices.height - height) / 2
                width: selected ? root.sliceExpandedWidth : root.sliceWidth
                height: selected ? root.sliceExpandedHeight : root.sliceHeight
                z: hovering ? 101 : selected ? 100 : 50 - Math.abs(difference)
                Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutQuad } }
                Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutQuad } }
                Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutQuad } }
                onHovered: root.choose(workspaceId)
                onActivated: { root.choose(workspaceId); root.confirm(); }
            }
        }
    }

    GridView {
        id: grid
        anchors.centerIn: parent
        visible: root.displayMode === "grid"
        clip: true
        width: Math.min(root.availableWidth, root.gridColumns * (root.gridWidth + root.gridSpacing))
        height: Math.min(root.availableHeight, root.gridRows * (root.gridHeight + root.gridSpacing))
        cellWidth: root.gridWidth + root.gridSpacing
        cellHeight: root.gridHeight + root.gridSpacing
        model: root.open && visible ? root.workspaceRows : []
        currentIndex: root.selectedIndex
        highlightFollowsCurrentItem: true
        highlightMoveDuration: 160
        delegate: WorkspaceTile {
            required property var modelData
            readonly property var workspace: modelData.workspace
            workspaceId: modelData.id
            workspaceObj: workspace
            monitorName: root.monitorNameFor(workspaceId, workspace)
            monitorIpc: root.monitorIpcFor(workspaceId, workspace)
            capturing: root.open
            selected: root.selectedId === workspaceId
            activeWorkspace: root.isCurrentWorkspace(workspaceId)
            dimOpacity: root.inactiveDimOpacity
            previewBlur: root.previewBlur
            hoverScale: root.hoverScale
            labelScale: root.uiScale
            z: hovering ? 2 : selected ? 1 : 0
            cornerRadius: root.effectiveRadius
            width: root.gridWidth
            height: root.gridHeight
            onHovered: root.choose(workspaceId)
            onActivated: { root.choose(workspaceId); root.confirm(); }
        }
    }

    ListView {
        id: compact
        anchors.centerIn: parent
        visible: root.displayMode === "compact"
        orientation: ListView.Horizontal
        clip: true
        spacing: root.compactSpacing
        width: Math.min(root.availableWidth, root.workspaceRows.length * (root.compactWidth + spacing))
        height: root.compactHeight
        model: root.open && visible ? root.workspaceRows : []
        currentIndex: root.selectedIndex
        preferredHighlightBegin: (width - root.compactWidth) / 2
        preferredHighlightEnd: (width + root.compactWidth) / 2
        highlightRangeMode: ListView.ApplyRange
        delegate: WorkspaceTile {
            required property var modelData
            readonly property var workspace: modelData.workspace
            workspaceId: modelData.id
            workspaceObj: workspace
            monitorName: root.monitorNameFor(workspaceId, workspace)
            monitorIpc: root.monitorIpcFor(workspaceId, workspace)
            capturing: root.open
            selected: root.selectedId === workspaceId
            activeWorkspace: root.isCurrentWorkspace(workspaceId)
            dimOpacity: root.inactiveDimOpacity
            previewBlur: root.previewBlur
            hoverScale: root.hoverScale
            labelScale: root.uiScale
            width: root.compactWidth
            height: root.compactHeight
            cornerRadius: root.effectiveRadius
            z: hovering ? 2 : selected ? 1 : 0
            onHovered: root.choose(workspaceId)
            onActivated: { root.choose(workspaceId); root.confirm(); }
        }
    }

    Controls.Button {
        anchors { right: parent.right; top: parent.top; margins: 18 }
        width: 40; height: 36
        text: "⚙"
        Accessible.name: "Налаштування"
        Controls.ToolTip.visible: hovered
        Controls.ToolTip.text: "Налаштування"
        onClicked: root.settingsRequested()
        contentItem: Text { text: parent.text; color: Theme.surfaceText; font.pixelSize: 20; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
        background: Rectangle {
            radius: 12
            color: Theme.withAlpha(Theme.surfaceContainer, 0.85)
            border.width: parent.activeFocus ? 2 : 0
            border.color: Theme.primary
        }
    }
}
