import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Common
import "/usr/share/quickshell/dms/Common/Format.js" as Format
import qs.Services
import qs.Modules.DankBar.Widgets as Bar
import qs.Widgets

Scope {
    id: root
    property var pluginService
    property var settings: ({})
    signal request(string kind, string screenName)
    signal settingsRequested(string section)
    property bool editing: false
    property string dragging: ""
    property string selected: ""
    property string dropLane: ""
    property int dropIndex: -1
    readonly property var defaults: ({
        topInset: 0, height: 28, itemGap: 3, uiScale: 1,
        left: ["runningApps"], centerBeforeClock: ["workspaces", "notifications", "wallpapers", "controlCenter", "clipboard", "language"],
        centerAfterClock: [],
        right: ["tray", "codex", "cpu", "gpu", "network"]
    })
    readonly property var panel: Object.assign({}, defaults, settings?.topPanel || {})
    readonly property var lanes: ["left", "centerBeforeClock", "centerAfterClock", "right"]
    readonly property var groupedActions: ["notifications", "wallpapers", "controlCenter", "clipboard", "language"]
    GlassTopPanelMetrics { id: metrics }
    function savePanel(value) { if (pluginService) pluginService.savePluginData("glassShell", "topPanel", value); }
    function move(widget, lane, index) {
        if (!widget || !lanes.includes(lane)) return;
        const origin = locate(widget);
        if (!origin) return;
        const next = Object.assign({}, panel);
        for (const key of lanes) next[key] = (panel[key] || []).filter(id => id !== widget);
        const target = next[lane];
        const adjusted = origin.lane === lane && origin.index < index ? index - 1 : index;
        const insertion = Math.max(0, Math.min(adjusted, target.length));
        if (origin.lane !== lane || origin.index !== insertion) {
            target.splice(insertion, 0, widget);
            savePanel(next);
        }
        selected = widget;
        dragging = "";
    }
    function locate(widget) {
        for (const lane of lanes) {
            const index = (panel[lane] || []).indexOf(widget);
            if (index >= 0) return { lane, index };
        }
        return null;
    }
    function keyboardMove(widget, direction) {
        const at = locate(widget);
        if (!at) return;
        if (direction === "left" || direction === "right") {
            const index = lanes.indexOf(at.lane) + (direction === "left" ? -1 : 1);
            if (index >= 0 && index < lanes.length) move(widget, lanes[index], (panel[lanes[index]] || []).length);
        } else if (direction === -1 || direction === 1 || direction === "up" || direction === "down") {
            const delta = direction === -1 || direction === "up" ? -1 : 1;
            move(widget, at.lane, at.index + (delta < 0 ? -1 : 2));
        }
    }
    Connections {
        target: root.pluginService
        function onGlobalVarChanged(id, key) {
            if (id !== "glassShell") return;
            if (key === "topPanelMove") {
                const command = root.pluginService.getGlobalVar(id, key, {});
                if (command.widget && command.direction) {
                    root.keyboardMove(command.widget, command.direction);
                    root.pluginService.setGlobalVar(id, key, {});
                }
            } else if (key === "topPanelEdit" && root.pluginService.getGlobalVar(id, key, false)) {
                root.editing = true;
                root.pluginService.setGlobalVar(id, key, false);
            }
        }
    }
    Variants {
        model: Quickshell.screens
        delegate: PanelWindow {
            id: win
            required property var modelData
            readonly property bool autoHide: root.panel.autoHideScreens?.[screen.name] === true
            property bool revealed: !autoHide
            property bool pointerOverPanel: false
            property bool appsPopupOpen: false
            property bool transientOpen: false
            property int popoutRevision: 0
            readonly property bool interactionActive: {
                popoutRevision;
                return root.editing || root.dragging !== "" || appsPopupOpen
                    || tooltipOwner !== null || transientOpen
                    || !!PopoutManager.currentPopoutsByScreen[screen.name]?.shouldBeVisible
                    || !!TrayMenuManager.activeTrayMenus[screen.name];
            }
            screen: modelData
            visible: !autoHide || revealed || interactionActive
            anchors { top: true; left: true; right: true }
            readonly property real diagonalScale: {
                const density = Number(modelData.physicalPixelDensity);
                const pixelRatio = Number(modelData.devicePixelRatio);
                return density > 0 && pixelRatio > 0
                    ? Math.hypot(modelData.width, modelData.height) * pixelRatio / density / (24 * 25.4)
                    : 1;
            }
            readonly property real scaleFactor: diagonalScale * Math.max(.5, Math.min(2, Number(root.panel.uiScale) || 1))
            readonly property real wingHeight: root.panel.height * scaleFactor
            readonly property real centerHeight: wingHeight * 1.5
            implicitHeight: Math.ceil(root.panel.topInset * scaleFactor + centerHeight)
            color: "transparent"
            WlrLayershell.namespace: "dms-glass-top"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.exclusiveZone: autoHide ? -1 : implicitHeight + 5 * scaleFactor
            WlrLayershell.keyboardFocus: root.editing ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            onAutoHideChanged: { revealed = !autoHide; hideDelay.stop(); }
            onInteractionActiveChanged: {
                if (interactionActive) { revealed = true; hideDelay.stop(); }
                else if (!pointerOverPanel && autoHide) hideDelay.restart();
            }
            Connections {
                target: PopoutManager
                function onPopoutChanged() { win.popoutRevision++; }
            }
            Timer {
                id: hideDelay
                interval: 500
                onTriggered: if (win.autoHide && !win.pointerOverPanel && !win.interactionActive) win.revealed = false
            }
            HoverHandler {
                target: win.contentItem
                onHoveredChanged: {
                    win.pointerOverPanel = hovered;
                    if (hovered) { win.revealed = true; hideDelay.stop(); }
                    else if (win.autoHide && !win.interactionActive) hideDelay.restart();
                }
            }
            PanelWindow {
                screen: win.screen
                visible: win.autoHide && !win.visible
                anchors { top: true; left: true; right: true }
                implicitHeight: 2
                color: "transparent"
                WlrLayershell.namespace: "dms-glass-edge-reveal"
                WlrLayershell.layer: WlrLayer.Top
                WlrLayershell.exclusiveZone: -1
                mask: Region { item: edgeHitArea }
                Item {
                    id: edgeHitArea
                    anchors.fill: parent
                    HoverHandler { onHoveredChanged: if (hovered) win.revealed = true }
                }
            }
            property var tooltipOwner: null
            property bool tooltipReady: false
            onTooltipOwnerChanged: {
                tooltipReady = false;
                tooltipDelay.stop();
                if (tooltipOwner) tooltipDelay.start();
            }
            Timer { id: tooltipDelay; interval: 350; onTriggered: win.tooltipReady = true }
            PanelWindow {
                screen: win.screen
                visible: win.tooltipReady && !!win.tooltipOwner && !root.editing
                anchors { top: true; left: true }
                implicitWidth: Math.min(520 * win.scaleFactor, tooltipText.implicitWidth + 24 * win.scaleFactor)
                implicitHeight: tooltipText.implicitHeight + 16 * win.scaleFactor
                margins.top: win.implicitHeight + 5 * win.scaleFactor
                margins.left: Math.max(8 * win.scaleFactor, Math.min(win.width - width - 8 * win.scaleFactor, (win.tooltipOwner?.mapToItem(win.contentItem, win.tooltipOwner.width / 2, 0).x || 0) - width / 2))
                color: "transparent"
                mask: Region {}
                WlrLayershell.namespace: "dms-glass-tooltip"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.exclusiveZone: -1
                Rectangle {
                    anchors.fill: parent
                    color: Theme.surfaceContainerHigh
                    radius: 8 * win.scaleFactor
                    border.color: Theme.outline
                    Text {
                        id: tooltipText
                        anchors.centerIn: parent
                        width: Math.min(496 * win.scaleFactor, implicitWidth)
                        text: win.tooltipOwner?.tooltipText || ""
                        font.pixelSize: 13 * win.scaleFactor
                        color: Theme.surfaceText
                        wrapMode: Text.Wrap
                    }
                }
            }
            mask: Region {
                Region { item: leftBlock }
                Region { item: centerBlock }
                Region { item: rightBlock }
            }
            readonly property var axis: ({ edge: "top", isVertical: false })
            readonly property var backgroundConfig: (SettingsData.barConfigs || []).find(config =>
                (config.position === 2 || config.position === 3)
                && config.screenPreferences?.includes(win.screen.name)) || ({})
            readonly property real trayIconSize: 22 * scaleFactor
            readonly property real trayCellSize: 28 * scaleFactor
            readonly property real trayIconSpacing: Math.max(0, SettingsData.trayIconSpacing) * scaleFactor
            readonly property real blockPadding: 5 * scaleFactor
            readonly property real blockGap: root.panel.itemGap * scaleFactor
            readonly property var workspaceConfig: ({ noBackground: true, removeWidgetPadding: true,
                                                     widgetPadding: 0, bottomGap: 0, widgetTransparency: 0 })
            readonly property var trayConfig: ({ noBackground: true, removeWidgetPadding: true, widgetPadding: 0,
                                                trayAutoOverflow: true, trayMaxVisibleItems: 5, trayUseInlineExpansion: false,
                                                bottomGap: 0, widgetTransparency: 0,
                                                iconScale: (trayCellSize - 6) * 48 / (wingHeight * Theme.barIconSize(48, undefined, false, 1)),
                                                trayIconSpacing: win.trayIconSpacing })
            function popout(kind, item) {
                const loader = kind === "clipboard" ? PopoutService.clipboardHistoryPopoutLoader
                    : kind === "notifications" ? PopoutService.notificationCenterLoader
                    : PopoutService.controlCenterLoader;
                if (!loader) return;
                const openLoaded = () => {
                    const popup = loader.item;
                    if (!popup) return;
                    if (popup.setBarContext) popup.setBarContext(0, 0);
                    popup.triggerScreen = win.screen;
                    const global = item.mapToItem(win.contentItem, 0, 0);
                    const pos = SettingsData.getPopupTriggerPosition(global, win.screen,
                        win.centerHeight, item.width, root.panel.topInset * win.scaleFactor, 0, win.trayConfig);
                    if (popup.setTriggerPosition)
                        popup.setTriggerPosition(pos.x, pos.y, pos.width, "center", win.screen, 0,
                                                 win.centerHeight, root.panel.topInset * win.scaleFactor, win.trayConfig);
                    const source = kind === "clipboard" ? "clipboard" :
                        kind === "notifications" ? "notifications" : kind;
                    if (typeof popup.prepareForTrigger === "function")
                        popup.prepareForTrigger(source, "click");
                    win.transientOpen = true;
                    PopoutManager.requestPopout(popup, undefined, source);
                    Qt.callLater(() => win.transientOpen = false);
                };
                loader.active = true;
                if (loader.item) openLoaded();
                else {
                    const loaded = () => {
                        if (!loader.item) return;
                        loader.loaded.disconnect(loaded);
                        openLoaded();
                    };
                    loader.loaded.connect(loaded);
                }
            }
            property date now: new Date()
            Timer { interval: 1000; running: true; repeat: true; onTriggered: win.now = new Date() }
            component PanelBackground: Rectangle {
                radius: win.backgroundConfig.noBackground ? 0 : Theme.cornerRadius
                color: {
                    if (win.backgroundConfig.noBackground) return "transparent";
                    const opacity = win.backgroundConfig.widgetTransparency ?? .62;
                    return Theme.widgetBackgroundHasAlpha
                        ? Theme.blendAlpha(Theme.widgetBaseBackgroundColor, opacity)
                        : Theme.withAlpha(Theme.widgetBaseBackgroundColor, opacity);
                }
                border.width: win.backgroundConfig.widgetOutlineEnabled
                    ? (win.backgroundConfig.widgetOutlineThickness ?? 1) : 0
                border.color: {
                    const choice = win.backgroundConfig.widgetOutlineColor;
                    const base = choice === "surfaceText" ? Theme.surfaceText
                        : choice === "secondary" ? Theme.secondary : Theme.primary;
                    return Theme.withAlpha(base, win.backgroundConfig.widgetOutlineOpacity ?? .48);
                }
            }
            Item {
                id: clock
                z: 2
                x: Math.round((win.width - width) / 2)
                y: root.panel.topInset * win.scaleFactor
                width: 78 * win.scaleFactor; height: win.centerHeight
                PanelBackground { anchors.fill: parent }
                Column {
                    anchors.centerIn: parent
                    spacing: 0
                    Text { anchors.horizontalCenter: parent.horizontalCenter; height: 20 * win.scaleFactor; lineHeight: height; lineHeightMode: Text.FixedHeight; verticalAlignment: Text.AlignVCenter; text: Qt.formatTime(win.now, "HH:mm"); color: Theme.surfaceText; font.pixelSize: 18 * win.scaleFactor; font.bold: true }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; height: 12 * win.scaleFactor; lineHeight: height; lineHeightMode: Text.FixedHeight; verticalAlignment: Text.AlignVCenter; text: Qt.formatDate(win.now, "dd.MM.yyyy"); color: Theme.surfaceTextSecondary; font.pixelSize: 10 * win.scaleFactor }
                }
            }
            Item {
                id: centerBlock
                x: clock.x - beforeLane.width - (beforeLane.width > 0 ? win.blockGap : 0)
                y: root.panel.topInset * win.scaleFactor
                width: beforeLane.width + clock.width + afterLane.width
                    + (beforeLane.width > 0 ? win.blockGap : 0) + (afterLane.width > 0 ? win.blockGap : 0)
                height: win.centerHeight
                focus: root.editing
                Keys.onEscapePressed: event => {
                    if (!root.dragging) { root.editing = false; event.accepted = true; return; }
                    root.dragging = "";
                    root.dropLane = "";
                    root.dropIndex = -1;
                    event.accepted = true;
                }
                PanelLane { id: beforeLane; anchors.verticalCenter: parent.verticalCenter; lane: "centerBeforeClock"; width: Math.min(implicitWidth, win.width * .27) }
                PanelLane { id: afterLane; x: clock.x + clock.width + win.blockGap - centerBlock.x; anchors.verticalCenter: parent.verticalCenter; lane: "centerAfterClock"; width: Math.min(implicitWidth, win.width * .32) }
            }
            Item {
                id: leftBlock
                x: Math.max(0, centerBlock.x - leftLane.implicitWidth - win.blockGap)
                y: root.panel.topInset * win.scaleFactor
                width: Math.max(0, centerBlock.x - win.blockGap - x)
                height: win.centerHeight
                PanelLane { id: leftLane; anchors.verticalCenter: parent.verticalCenter; lane: "left"; width: leftBlock.width }
            }
            Item {
                id: rightBlock
                x: centerBlock.x + centerBlock.width + win.blockGap
                y: root.panel.topInset * win.scaleFactor
                width: Math.min(rightLane.implicitWidth, Math.max(0, win.width - x))
                height: win.centerHeight
                PanelLane { id: rightLane; anchors.verticalCenter: parent.verticalCenter; lane: "right"; width: rightBlock.width }
            }
            component PanelLane: Item {
                id: laneRoot
                required property string lane
                implicitWidth: widgets.implicitWidth
                implicitHeight: lane === "left" || lane === "right" ? win.wingHeight : win.centerHeight
                width: implicitWidth
                height: implicitHeight
                clip: true
                function indexAt(windowX) {
                    const local = laneRoot.mapFromItem(win.contentItem, windowX, 0).x + scroll.contentX;
                    for (let i = 0; i < widgetRepeater.count; i++) {
                        const entry = widgetRepeater.itemAt(i);
                        if (entry && local < entry.x + entry.width / 2) return i;
                    }
                    return widgetRepeater.count;
                }
                Flickable {
                    id: scroll
                    anchors.fill: parent
                    contentWidth: widgets.implicitWidth
                    contentHeight: height
                    interactive: contentWidth > width
                    boundsBehavior: Flickable.StopAtBounds
                    Row {
                        id: widgets
                        height: laneRoot.height
                        spacing: 0
                        Repeater {
                            id: widgetRepeater
                            model: root.panel[laneRoot.lane] || []
                            delegate: Item {
                                id: entry
                                required property string modelData
                                required property int index
                                readonly property bool joinsNext: widget.groupedAction && !widget.groupEnd
                                readonly property real trailingGap: index === widgetRepeater.count - 1 ? 0
                                    : joinsNext ? win.trayIconSpacing : win.blockGap
                                width: widget.visible ? widget.width + trailingGap : 0
                                height: laneRoot.height
                                Item {
                                id: widget
                                readonly property int index: entry.index
                                readonly property string kind: entry.modelData
                                visible: kind !== "codex" || !!root.pluginService?.isPluginLoaded("codexGlass")
                                readonly property bool groupedAction: root.groupedActions.includes(kind)
                                readonly property bool groupStart: groupedAction
                                    && (index === 0 || !root.groupedActions.includes(root.panel[laneRoot.lane][index - 1]))
                                readonly property bool groupEnd: groupedAction
                                    && !root.groupedActions.includes((root.panel[laneRoot.lane] || [])[index + 1])
                                readonly property real leftPadding: !groupedAction || groupStart ? win.blockPadding : 0
                                readonly property real rightPadding: !groupedAction || groupEnd ? win.blockPadding : 0
                                readonly property real backgroundWidth: {
                                    if (!groupStart) return width;
                                    const entries = root.panel[laneRoot.lane] || [];
                                    let count = 1;
                                    for (let i = index + 1; i < entries.length && root.groupedActions.includes(entries[i]); ++i) ++count;
                                    return count * win.trayCellSize + (count - 1) * win.trayIconSpacing + 2 * win.blockPadding;
                                }
                                readonly property string actionName: ({
                                    runningApps: "Запущені застосунки", tray: "Системний трей",
                                    workspaces: "Робочі столи", language: "Перемкнути мову",
                                    clipboard: "Буфер обміну", controlCenter: "Центр керування",
                                    notifications: "Сповіщення", wallpapers: "Шпалери",
                                    cpu: "Процесор і оперативна пам'ять", gpu: "Відеокарта",
                                    network: "Мережа"
                                })[kind] || kind
                                Accessible.name: actionName
                                activeFocusOnTab: !["runningApps", "tray", "workspaces", "cpu", "gpu", "network"].includes(kind)
                                Accessible.role: activeFocusOnTab ? Accessible.Button : Accessible.StaticText
                                function activate() {
                                    if (root.editing) { root.selected = kind; return; }
                                    else if (["clipboard", "controlCenter", "notifications"].includes(kind)) win.popout(kind, widget);
                                    else if (kind === "wallpapers") root.request("wallpapers", win.screen.name);
                                    else if (kind === "language")
                                        Quickshell.execDetached(["hyprctl", "switchxkblayout", "all", languageLoader.item?.currentLayout?.toLowerCase().startsWith("uk") || languageLoader.item?.currentLayout?.toLowerCase().startsWith("ua") ? "0" : "1"]);
                                }
                                Keys.onReturnPressed: { activate(); event.accepted = true; }
                                Keys.onSpacePressed: { activate(); event.accepted = true; }
                                Keys.onEscapePressed: {
                                    if (root.dragging) { root.dragging = ""; root.dropLane = ""; root.dropIndex = -1; }
                                    else root.editing = false;
                                    event.accepted = true;
                                }
                                readonly property real fixedWidth: kind === "runningApps" ? Math.max(win.trayCellSize, appLoader.item?.implicitWidth || 0)
                                    : kind === "workspaces" ? (workspaceLoader.item?.width || 0)
                                    : kind === "tray" ? Math.max(26 * win.scaleFactor, trayLoader.item?.width || 0)
                                    : kind === "codex" ? (codexLoader.item?.implicitWidth || 64 * win.scaleFactor) + 4 * win.scaleFactor
                                    : ["cpu", "gpu", "network"].includes(kind) ? metricText.implicitWidth + 4 * win.scaleFactor
                                    : win.trayCellSize
                                width: fixedWidth + leftPadding + rightPadding; height: laneRoot.height
                                PanelBackground {
                                    visible: !widget.groupedAction || widget.groupStart
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: widget.backgroundWidth
                                    height: win.wingHeight
                                }
                                Rectangle { anchors.fill: parent; radius: 4 * win.scaleFactor; color: root.editing && root.selected === widget.kind ? Theme.withAlpha(Theme.primary, .3) : "transparent"; border.width: widget.activeFocus ? 1 : 0; border.color: Theme.primary }
                                Loader {
                                    id: appLoader
                                    active: widget.kind === "runningApps"
                                    anchors.centerIn: parent
                                    sourceComponent: GlassTopPanelApps {
                                        panelScreen: win.screen; parentWindow: win
                                        panelHeight: win.wingHeight; panelInset: root.panel.topInset * win.scaleFactor
                                        popupOffset: win.centerHeight; itemGap: win.trayIconSpacing; scaleFactor: win.scaleFactor
                                        cellWidth: win.trayCellSize; iconSize: win.trayIconSize
                                        onPopupVisibleChanged: win.appsPopupOpen = popupVisible
                                        Component.onDestruction: win.appsPopupOpen = false
                                    }
                                }
                                Loader {
                                    id: trayLoader
                                    active: widget.kind === "tray"
                                    anchors.centerIn: parent
                                    sourceComponent: Bar.SystemTrayBar {
                                        parentScreen: win.screen; parentWindow: win
                                        axis: win.axis; section: "right"
                                        barThickness: win.wingHeight
                                        widgetThickness: win.wingHeight
                                        barSpacing: root.panel.topInset * win.scaleFactor
                                        barConfig: win.trayConfig
                                        widgetData: win.trayConfig
                                        sectionAvailablePrimarySize: Math.min(160 * win.scaleFactor, win.width * .12)
                                    }
                                }
                                Loader {
                                    id: workspaceLoader
                                    active: widget.kind === "workspaces"
                                    anchors.centerIn: parent
                                    sourceComponent: Bar.WorkspaceSwitcher {
                                        screenName: win.screen.name
                                        parentScreen: win.screen
                                        axis: win.axis
                                        widgetHeight: win.wingHeight
                                        barThickness: win.wingHeight + 2 * win.scaleFactor
                                        barConfig: win.workspaceConfig
                                        enabled: !root.editing
                                    }
                                }
                                Loader {
                                    id: languageLoader
                                    active: widget.kind === "language"
                                    visible: false
                                    sourceComponent: Bar.KeyboardLayoutName {
                                        parentScreen: win.screen
                                        axis: win.axis
                                        section: "center"
                                        barThickness: win.centerHeight
                                        widgetThickness: win.wingHeight
                                        barConfig: win.trayConfig
                                        widgetData: ({ keyboardLayoutNameCompactMode: true, keyboardLayoutNameShowIcon: false })
                                    }
                                }
                                Text {
                                    visible: widget.kind === "language"
                                    anchors.centerIn: parent; color: Theme.surfaceText
                                    anchors.horizontalCenterOffset: (widget.leftPadding - widget.rightPadding) / 2
                                    font.pixelSize: 11 * win.scaleFactor; font.bold: true
                                    text: {
                                        const layout = String(languageLoader.item?.currentLayout || "").toLowerCase();
                                        if (layout.startsWith("ua") || layout.startsWith("uk") || layout.includes("ukrain")) return "ua";
                                        if (layout.startsWith("us") || layout.startsWith("en") || layout.includes("english")) return "en";
                                        return layout ? layout.slice(0, 2) : "—";
                                    }
                                }
                                Loader {
                                    id: codexLoader
                                    active: widget.kind === "codex" && !!root.pluginService?.isPluginLoaded("codexGlass")
                                    anchors.centerIn: parent
                                    source: (Quickshell.env("HOME") || "") + "/.config/DankMaterialShell/plugins/codexGlass/CodexQuota.qml"
                                    onLoaded: item.scaleFactor = Qt.binding(() => win.scaleFactor)
                                }
                                Text {
                                    id: metricText
                                    visible: ["cpu", "gpu", "network"].includes(widget.kind)
                                    anchors.centerIn: parent
                                    color: Theme.surfaceText
                                    font.pixelSize: 12 * win.scaleFactor
                                    text: widget.kind === "cpu"
                                        ? (isFinite(metrics.cpu) ? Math.round(metrics.cpu) + "%" : "—")
                                          + " " + (isFinite(metrics.cpuTemperature) ? Math.round(metrics.cpuTemperature) + "°C" : "—")
                                          + " · " + (isFinite(metrics.memoryBytes) ? (metrics.memoryBytes / 1e9).toFixed(1) + " GB" : "—")
                                        : widget.kind === "gpu"
                                        ? (isFinite(metrics.gpu) ? Math.round(metrics.gpu) + "%" : "—")
                                          + " " + (isFinite(metrics.gpuTemperature) ? Math.round(metrics.gpuTemperature) + "°C" : "—")
                                          + " " + (isFinite(metrics.vramBytes) ? (metrics.vramBytes / 1e9).toFixed(1) + " GB" : "—")
                                        : "↓ " + (isFinite(metrics.rx) ? Format.formatRate(metrics.rx) : "—")
                                          + " ↑ " + (isFinite(metrics.tx) ? Format.formatRate(metrics.tx) : "—")
                                }
                                readonly property bool tooltipHovered: !root.editing && (metricHover.containsMouse || actionHover.containsMouse)
                                onTooltipHoveredChanged: {
                                    if (tooltipHovered) win.tooltipOwner = widget;
                                    else if (win.tooltipOwner === widget) win.tooltipOwner = null;
                                }
                                Component.onDestruction: if (win.tooltipOwner === widget) win.tooltipOwner = null
                                readonly property string tooltipText: {
                                    if (widget.kind === "codex") return codexLoader.item?.tooltipText || "Codex: плагін вимкнено";
                                    const gb = n => isFinite(n) ? (n / 1e9).toFixed(1) + " GB" : "—";
                                    if (widget.kind === "cpu") return "CPU: " + (isFinite(metrics.cpu) ? Math.round(metrics.cpu) + "%" : "—") + " · температура: " + (isFinite(metrics.cpuTemperature) ? Math.round(metrics.cpuTemperature) + " °C" : "—")
                                        + "\nRAM: " + gb(metrics.memoryBytes) + " / " + gb(metrics.totalMemoryBytes);
                                    if (widget.kind === "gpu") return "GPU: " + (isFinite(metrics.gpu) ? Math.round(metrics.gpu) + "%" : "—") + " · " + (isFinite(metrics.gpuTemperature) ? Math.round(metrics.gpuTemperature) + " °C" : "—") + " · VRAM: " + gb(metrics.vramBytes) + " / " + gb(metrics.totalVramBytes);
                                    if (widget.kind === "network") return "Мережа: ↓ " + (isFinite(metrics.rx) ? Format.formatRate(metrics.rx) : "—") + " · ↑ " + (isFinite(metrics.tx) ? Format.formatRate(metrics.tx) : "—");
                                    return widget.actionName;
                                }
                                MouseArea { id: metricHover; anchors.fill: parent; enabled: !root.editing && ["codex", "cpu", "gpu", "network"].includes(widget.kind); hoverEnabled: true }
                                Item {
                                    visible: ["clipboard", "controlCenter", "notifications", "wallpapers"].includes(widget.kind)
                                    anchors.centerIn: parent
                                    anchors.horizontalCenterOffset: (widget.leftPadding - widget.rightPadding) / 2
                                    width: win.trayIconSize; height: win.trayIconSize
                                    DankIcon {
                                        anchors.centerIn: parent
                                        name: widget.kind === "clipboard" ? "content_paste"
                                            : widget.kind === "controlCenter" ? "settings"
                                            : widget.kind === "notifications"
                                              ? (SessionData.doNotDisturb ? "notifications_off" : "notifications")
                                            : "image"
                                        size: win.trayIconSize
                                        color: Theme.surfaceText
                                    }
                                    Rectangle {
                                        visible: widget.kind === "notifications" && NotificationService.unreadCount > 0
                                        anchors.top: parent.top; anchors.right: parent.right
                                        width: 5 * win.scaleFactor; height: width; radius: width / 2
                                        color: Theme.primary
                                    }
                                }
                                MouseArea {
                                    id: actionHover
                                    anchors.fill: parent
                                    enabled: root.editing || !["runningApps", "tray", "workspaces", "codex", "cpu", "gpu", "network"].includes(widget.kind)
                                    hoverEnabled: true
                                    onEntered: { if (root.dragging) { root.dropLane = laneRoot.lane; root.dropIndex = widget.index; } }
                                    onClicked: widget.activate()
                                    property real pressX: 0
                                    preventStealing: root.editing
                                    onPressed: mouse => {
                                        if (root.editing) {
                                            pressX = mouse.x;
                                            root.selected = widget.kind;
                                            centerBlock.forceActiveFocus();
                                        }
                                    }
                                    onPositionChanged: mouse => {
                                        if (!root.editing || !pressed || (Math.abs(mouse.x - pressX) < 6 && !root.dragging)) return;
                                        root.dragging = widget.kind;
                                        const x = mapToItem(win.contentItem, mouse.x, mouse.y).x;
                                        const target = x < centerBlock.x ? leftLane
                                            : x < clock.x ? beforeLane
                                            : x < clock.x + clock.width ? beforeLane
                                            : x < rightBlock.x ? afterLane : rightLane;
                                        root.dropLane = target.lane;
                                        root.dropIndex = target.indexAt(x);
                                    }
                                    onReleased: { if (root.dragging) root.move(root.dragging, root.dropLane, root.dropIndex); }
                                }
                                Rectangle {
                                    visible: root.editing && root.dragging && root.dropLane === laneRoot.lane && root.dropIndex === widget.index
                                    x: -3; width: 2; height: parent.height - 8; y: 4; color: "#a5c6ac"
                                }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
