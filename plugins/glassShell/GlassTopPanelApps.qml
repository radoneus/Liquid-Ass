import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Common
import qs.Services

Item {
    id: root
    property var panelScreen
    property var parentWindow
    property real panelHeight: 23
    property real panelInset: 0
    property real popupOffset: panelHeight * 1.5
    property real scaleFactor: 1
    property real itemGap: 2
    property real iconSize: 22 * scaleFactor
    property real cellWidth: 28 * scaleFactor
    readonly property bool popupVisible: previewWindow.visible
    property string hoveredId: ""
    property real popupX: 0
    property int toplevelsRevision: 0
    property var mostRecent: ({})
    property var groups: {
        toplevelsRevision;
        const byId = new Map();
        for (const tl of CompositorService.sortedToplevels || []) {
            const id = String(tl.appId || tl.lastIpcObject?.class || "unknown");
            if (!byId.has(id)) byId.set(id, { id, windows: [] });
            byId.get(id).windows.push(tl);
        }
        return Array.from(byId.values());
    }
    Connections {
        target: CompositorService
        function onToplevelsChanged() { root.toplevelsRevision++; }
    }
    Connections {
        target: ToplevelManager
        function onActiveToplevelChanged() {
            const active = ToplevelManager.activeToplevel;
            if (!active) return;
            const id = String(active.appId || "unknown");
            root.mostRecent = Object.assign({}, root.mostRecent, {[id]: active});
        }
    }
    readonly property var hoveredGroup: groups.find(g => g.id === hoveredId) || null
    function hyprlandWindow(window) {
        return Hyprland.toplevels?.values?.find(tl => tl.wayland === window || tl.address === window?.address) || null;
    }
    implicitWidth: icons.implicitWidth
    implicitHeight: panelHeight
    onHoveredGroupChanged: {
        if (!hoveredGroup) { hoveredId = ""; hoverDelay.stop(); closeDelay.stop(); }
    }
    function openGroup(id, item) {
        hoveredId = id;
        const pos = item.mapToGlobal(0, 0);
        popupX = Math.max(4, Math.min(panelScreen.width - previewWindow.cardWidth - 8, pos.x - panelScreen.x));
        closeDelay.stop();
        hoverDelay.restart();
    }
    function keepOpen() { closeDelay.stop(); }
    function scheduleClose() { hoverDelay.stop(); closeDelay.restart(); }
    Timer { id: hoverDelay; interval: 180; onTriggered: previewWindow.open = !!root.hoveredGroup }
    Timer { id: closeDelay; interval: 260; onTriggered: { previewWindow.open = false; root.hoveredId = ""; } }
    Row {
        id: icons
        spacing: root.itemGap
        Repeater {
            model: root.groups
            delegate: Item {
                id: appIcon
                required property var modelData
                width: root.cellWidth
                height: root.panelHeight
                readonly property var entry: DesktopEntries.heuristicLookup(Paths.moddedAppId(modelData.id))
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: (entry?.name || modelData.id) + (modelData.windows.length > 1 ? " · " + modelData.windows.length + " вікна" : "")
                function activateGroup() {
                    const windows = modelData.windows;
                    const recent = root.mostRecent[modelData.id];
                    const active = windows.includes(recent) ? recent : windows.find(w => w.activated) || windows[0];
                    if (active && root.groups.some(g => g.windows.includes(active))) CompositorService.activateToplevel(active);
                    root.scheduleClose();
                }
                Keys.onReturnPressed: { activateGroup(); event.accepted = true; }
                Keys.onSpacePressed: { activateGroup(); event.accepted = true; }
                Rectangle {
                    anchors.fill: parent; color: "transparent"
                    border.width: appIcon.activeFocus ? 1 : 0
                    border.color: Theme.primary; radius: 4 * root.scaleFactor
                }
                Image {
                    anchors.centerIn: parent
                    width: root.iconSize; height: root.iconSize
                    source: Paths.getAppIcon(appIcon.modelData.id, appIcon.entry) || Quickshell.iconPath("application-x-executable")
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }
                Rectangle {
                    visible: appIcon.modelData.windows.length > 1
                    width: 11 * root.scaleFactor; height: 11 * root.scaleFactor; radius: width / 2
                    anchors.right: parent.right; anchors.bottom: parent.bottom
                    color: Theme.primaryContainer
                    Text {
                        anchors.centerIn: parent
                        text: appIcon.modelData.windows.length > 9 ? "9+" : appIcon.modelData.windows.length
                        color: Theme.surfaceText; font.pixelSize: 8 * root.scaleFactor
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: root.openGroup(appIcon.modelData.id, appIcon)
                    onExited: root.scheduleClose()
                    onClicked: appIcon.activateGroup()
                }
            }
        }
    }
    PanelWindow {
        id: previewWindow
        property bool open: false
        readonly property int cardWidth: 270
        visible: open && !!root.hoveredGroup && !!root.panelScreen
        screen: root.panelScreen
        anchors { top: true; left: true; right: true; bottom: true }
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusiveZone: -1
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "dms-glass-app-preview"
        mask: Region { item: previewBox }
        Rectangle {
            id: previewBox
            x: root.popupX
            y: root.panelInset + root.popupOffset
            width: previewWindow.cardWidth
            height: Math.min(root.panelScreen?.height - y - 10 * root.scaleFactor || 400 * root.scaleFactor, Math.max(144 * root.scaleFactor, list.contentHeight + 16 * root.scaleFactor))
            radius: 13 * root.scaleFactor
            color: Theme.withAlpha(Theme.surfaceContainer, .94)
            border.color: Theme.outline
            border.width: 1
            MouseArea { anchors.fill: parent; hoverEnabled: true; onEntered: root.keepOpen(); onExited: root.scheduleClose() }
            Flickable {
                id: list
                anchors.fill: parent
                anchors.margins: 8 * root.scaleFactor
                contentHeight: cards.implicitHeight
                clip: true
                Column {
                    id: cards
                    width: list.width
                    spacing: 8 * root.scaleFactor
                    Repeater {
                        model: root.hoveredGroup?.windows || []
                        delegate: Rectangle {
                            id: card
                            required property var modelData
                            width: cards.width; height: 150; radius: 8
                            color: Theme.surfaceContainerHigh
                            clip: true
                            ScreencopyView {
                                id: capture
                                anchors.fill: parent
                                captureSource: previewWindow.visible ? card.modelData?.wayland || null : null
                                live: previewWindow.visible
                                visible: hasContent
                            }
                            Column {
                                anchors.centerIn: parent
                                visible: !capture.hasContent
                                spacing: 5 * root.scaleFactor
                                Image {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 38; height: 38
                                    source: Paths.getAppIcon(root.hoveredId, DesktopEntries.heuristicLookup(root.hoveredId))
                                            || Quickshell.iconPath("application-x-executable")
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                }
                                Text { text: card.modelData?.title || root.hoveredId; color: Theme.surfaceText; font.pixelSize: 12 * root.scaleFactor; width: card.width - 20 * root.scaleFactor; elide: Text.ElideRight }
                                Text { text: "Прев’ю недоступне"; color: Theme.surfaceTextSecondary; font.pixelSize: 11 * root.scaleFactor }
                            }
                            Rectangle {
                                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                                height: 35; color: Theme.withAlpha(Theme.surfaceContainer, .88)
                                Text {
                                    anchors.fill: parent; anchors.margins: 6 * root.scaleFactor
                                    text: (card.modelData?.title || root.hoveredId)
                                          + " · стіл " + (root.hyprlandWindow(card.modelData)?.workspace?.id ?? "—")
                                          + " · " + (root.hyprlandWindow(card.modelData)?.workspace?.monitor?.name || "—")
                                    color: Theme.surfaceText; font.pixelSize: 11; elide: Text.ElideRight
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onEntered: root.keepOpen()
                                onClicked: {
                                    if (root.hoveredGroup?.windows.includes(card.modelData)) CompositorService.activateToplevel(card.modelData);
                                    previewWindow.open = false;
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
