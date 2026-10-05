import Qt.labs.folderlistmodel
import QtCore
import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Dialogs
import Quickshell
import qs.Common
import qs.Modals.FileBrowser
import qs.Widgets

Item {
    id: root
    property bool open: false
    property var settings: ({})
    property var targetScreen: null
    signal closeRequested()
    signal configurationChanged(var value)
    signal settingsRequested()

    property point lastHoverPosition: Qt.point(-1, -1)
    implicitWidth: 1080
    implicitHeight: 760
    focus: open
    visible: open

    property var activeSettings: ({})
    readonly property real adaptiveScale: Math.max(.75, Math.min(1.5, Math.min((targetScreen?.width || width) / 1920, (targetScreen?.height || height) / 1080)))
    readonly property real uiScale: Math.max(.5, Math.min(2, settingNumber("uiScale", 1))) * adaptiveScale
    readonly property string targetName: targetScreen ? targetScreen.name : ""
    property string boundScreenName: ""
    readonly property bool screenAlive: boundScreenName !== "" && Quickshell.screens.some(s => s.name === boundScreenName)
    property string directoryPath: ""
    property string configuredDirectory: ""
    property string selectedPath: ""
    property string pendingPath: ""
    property var filteredPaths: []
    property int page: 0
    property int selectedImageStatus: Image.Null
    property string errorText: ""
    property bool applying: false
    property bool initialSelectionPending: false
    property bool directoryDialogPending: false
    readonly property bool nativeDialogOpen: directoryDialogPending || folderDialog.visible

    readonly property real sliceWidth: Math.max(20, settingNumber("sliceWidth", 180)) * uiScale
    readonly property real expandedWidth: Math.max(20, settingNumber("expandedWidth", 468)) * uiScale
    readonly property real sliceHeight: Math.max(20, settingNumber("sliceHeight", 332)) * uiScale
    readonly property real expandedHeight: Math.max(20, settingNumber("expandedHeight", settingNumber("sliceHeight", 332))) * uiScale
    readonly property real sliceSpacing: settingNumber("sliceSpacing", 15) * uiScale
    readonly property real sliceSkewAngle: Math.max(-45, Math.min(45, settingNumber("skewAngle", 0)))
    readonly property real sliceFit: Math.min(1, Math.max(.01, (gallery.width - 20) / expandedWidth), Math.max(.01, (gallery.height - 12) / Math.max(sliceHeight, expandedHeight)))
    readonly property real cornerRadius: Math.max(0, settingNumber("cornerRadius", 20)) * uiScale * sliceFit
    readonly property real dimOpacity: Math.max(0, Math.min(1, settingNumber("dimOpacity", .3)))
    readonly property real inactiveDimOpacity: Math.max(0, Math.min(1, settingNumber("inactiveDimOpacity", .3)))
    readonly property int pageSize: Math.max(1, Math.min(25, Math.floor(settingNumber("visibleCount", 9))))
    // Use the narrowest aspect ratio for every card, rather than clamping each card differently.
    readonly property real effectiveAngle: Math.atan(Math.max(-.4 * Math.min(sliceWidth / sliceHeight, expandedWidth / expandedHeight), Math.min(.4 * Math.min(sliceWidth / sliceHeight, expandedWidth / expandedHeight), Math.tan(sliceSkewAngle * Math.PI / 180)))) * 180 / Math.PI
    function skew(w, h) { return h * Math.tan(effectiveAngle * Math.PI / 180); }
    function leftEdge(w, h, y) {
        const s = skew(w, h);
        return Math.max(0, s) + (Math.max(0, -s) - Math.max(0, s)) * y / h;
    }
    function rightEdge(w, h, y) {
        const s = skew(w, h);
        return w + Math.min(0, s) + (-Math.max(0, s) - Math.min(0, s)) * y / h;
    }
    function cardWidth(index) { return (index === gallery.selectedOnPage ? expandedWidth : sliceWidth) * sliceFit; }
    function cardHeight(index) { return (index === gallery.selectedOnPage ? expandedHeight : sliceHeight) * sliceFit; }
    function advance(index) {
        const w = cardWidth(index), h = cardHeight(index), nextW = cardWidth(index + 1), nextH = cardHeight(index + 1);
        const top = Math.max(-h / 2, -nextH / 2), bottom = Math.min(h / 2, nextH / 2);
        function correction(y) { return root.leftEdge(nextW, nextH, y + nextH / 2) - root.rightEdge(w, h, y + h / 2); }
        return Math.max(20, sliceSpacing * sliceFit - Math.min(correction(top), correction(bottom)));
    }
    function cardX(index) {
        const focus = Math.max(0, gallery.selectedOnPage);
        let x = (gallery.width - cardWidth(focus)) / 2;
        if (index < focus) for (let i = focus - 1; i >= index; --i) x -= advance(i);
        else for (let i = focus; i < index; ++i) x += advance(i);
        return x;
    }
    readonly property int pageCount: Math.max(1, Math.ceil(filteredPaths.length / pageSize))
    readonly property var pagePaths: filteredPaths.slice(page * pageSize, (page + 1) * pageSize)
    readonly property int poolSize: Math.min(pageSize + 2, filteredPaths.length)
    readonly property int firstPooledPath: Math.max(0, page * pageSize - 1)
    function pooledPathIndex(slot) {
        if (!poolSize) return -1;
        return firstPooledPath + ((slot - firstPooledPath % poolSize + poolSize) % poolSize);
    }
    readonly property string currentWallpaper: SessionData.perMonitorWallpaper && boundScreenName ? (SessionData.getMonitorWallpaper(boundScreenName) || "") : (SessionData.wallpaperPath || "")

    function settingNumber(key, fallback) {
        const value = activeSettings[key];
        const n = Number(value);
        return value === undefined || value === null || value === "" || !Number.isFinite(n) ? fallback : n;
    }
    function updateSetting(key, value) {
        const next = Object.assign({}, activeSettings);
        next[key] = value;
        activeSettings = next;
        configurationChanged(next);
    }
    function imageDirectory(path) {
        return path && !path.startsWith("#") && path.lastIndexOf('/') > 0 ? path.substring(0, path.lastIndexOf('/')) : "";
    }
    function localPath(path) {
        const value = path ? path.toString() : "";
        if (!value.startsWith("file://"))
            return value;
        try {
            return decodeURIComponent(value.substring(7));
        } catch (_) {
            return "";
        }
    }
    function fileUrl(path) {
        return "file://" + path.split('/').map(segment => encodeURIComponent(segment)).join('/');
    }
    function matchesTerms(terms, name, path) {
        const haystack = (name + " " + path).toLowerCase();
        return terms.every(term => haystack.indexOf(term) >= 0);
    }
    function chooseDirectory() {
        const explicit = (activeSettings.directory || "").trim();
        return explicit || imageDirectory(currentWallpaper) || CacheData.wallpaperLastPath || Paths.strip(Paths.pictures);
    }
    function begin() {
        boundScreenName = targetName;
        if (!screenAlive) {
            closeRequested();
            return;
        }
        activeSettings = Object.assign({}, settings || {});
        configuredDirectory = (activeSettings.directory || "").trim();
        errorText = "";
        applying = false;
        pendingPath = "";
        selectedPath = "";
        page = 0;
        searchField.text = "";
        initialSelectionPending = true;
        directoryPath = chooseDirectory();
        // A model already at Ready may not emit statusChanged on reopening.
        Qt.callLater(() => {
            if (root.open && folderModel.status === FolderListModel.Ready)
                root.rebuild();
            root.forceActiveFocus();
        });
    }
    function rebuild() {
        const paths = [];
        if (folderModel.status === FolderListModel.Ready) {
            const query = searchField.text.trim().toLowerCase();
            const terms = query ? query.split(/\s+/) : [];
            for (let i = 0; i < folderModel.count; ++i) {
                const path = localPath(folderModel.get(i, "filePath"));
                if (path && matchesTerms(terms, folderModel.get(i, "fileName") || "", path))
                    paths.push(path);
            }
        }
        filteredPaths = paths;
        if (initialSelectionPending && folderModel.status === FolderListModel.Ready) {
            const preferred = pendingPath || currentWallpaper;
            selectedPath = paths.indexOf(preferred) >= 0 ? preferred : (paths[0] || "");
            pendingPath = "";
            initialSelectionPending = false;
        }
        else if (folderModel.status === FolderListModel.Ready && paths.indexOf(selectedPath) < 0)
            selectedPath = paths[0] || "";
        const index = paths.indexOf(selectedPath);
        if (index >= 0)
            page = Math.floor(index / pageSize);
        else
            page = Math.max(0, Math.min(page, pageCount - 1));
        updateImageStatus();
    }
    function updateImageStatus() {
        selectedImageStatus = Image.Null;
        Qt.callLater(() => {
            if (!root.open)
                return;
            const absoluteIndex = root.filteredPaths.indexOf(root.selectedPath);
            const item = root.poolSize && absoluteIndex >= 0 ? cards.itemAt(absoluteIndex % root.poolSize) : null;
            if (item && item.imagePath === root.selectedPath)
                root.selectedImageStatus = item.imageStatus;
        });
    }
    function select(path) {
        if (!path || filteredPaths.indexOf(path) < 0)
            return;
        selectedPath = path;
        page = Math.floor(filteredPaths.indexOf(path) / pageSize);
        errorText = "";
        updateImageStatus();
    }
    function moveSelection(step) {
        if (!filteredPaths.length)
            return;
        const index = filteredPaths.indexOf(selectedPath);
        select(filteredPaths[Math.max(0, Math.min(filteredPaths.length - 1, (index < 0 ? 0 : index) + step))]);
    }
    function changePage(step) {
        page = Math.max(0, Math.min(pageCount - 1, page + step));
        if (pagePaths.length)
            select(pagePaths[0]);
    }
    function applySelected() {
        if (applying || !open)
            return;
        if (!screenAlive) {
            closeRequested();
            return;
        }
        if (!selectedPath || folderModel.status !== FolderListModel.Ready || selectedImageStatus !== Image.Ready) {
            errorText = selectedImageStatus === Image.Error ? "Не вдалося відкрити зображення" : "Дочекайтеся завантаження зображення";
            return;
        }
        // Recheck the live FolderListModel, not just the filtered snapshot.
        let present = false;
        for (let i = 0; i < folderModel.count; ++i) {
            if (localPath(folderModel.get(i, "filePath")) === selectedPath) {
                present = true;
                break;
            }
        }
        if (!present) {
            errorText = "Файл більше не існує в цій теці";
            rebuild();
            return;
        }
        applying = true;
        const path = selectedPath;
        if (SessionData.perMonitorWallpaper) {
            SessionData.setMonitorWallpaper(boundScreenName, path);
            if (SessionData.getMonitorWallpaper(boundScreenName) === path)
                SessionData.setMonitorCyclingFolderPath(boundScreenName, "");
        } else {
            SessionData.setWallpaper(path);
            if (SessionData.wallpaperPath === path) {
                SessionData.wallpaperCyclingFolderPath = "";
                SessionData.saveSettings();
            }
        }
        const applied = SessionData.perMonitorWallpaper ? SessionData.getMonitorWallpaper(boundScreenName) === path : SessionData.wallpaperPath === path;
        if (applied)
            closeRequested();
        else {
            applying = false;
            errorText = "DMS не підтвердив застосування шпалер. Спробуйте ще раз.";
        }
    }
    function handleKey(event) {
        if (event.key === Qt.Key_Escape) { closeRequested(); return true; }
        if (event.key === Qt.Key_PageDown) { changePage(1); return true; }
        if (event.key === Qt.Key_PageUp) { changePage(-1); return true; }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { applySelected(); return true; }
        if (event.key === Qt.Key_Left) { moveSelection(-1); return true; }
        if (event.key === Qt.Key_Right) { moveSelection(1); return true; }
        if (event.key === Qt.Key_Up) { moveSelection(-1); return true; }
        if (event.key === Qt.Key_Down) { moveSelection(1); return true; }
        return false;
    }

    onOpenChanged: {
        if (open) begin();
        else {
            openDirectoryTimer.stop();
            directoryDialogPending = false;
            if (browser.item) browser.item.close();
            if (folderDialog.visible) folderDialog.close();
            boundScreenName = "";
            filteredPaths = [];
            selectedPath = "";
        }
    }
    onSettingsChanged: {
        activeSettings = Object.assign({}, settings || {});
        const explicit = (activeSettings.directory || "").trim();
        if (open && explicit !== configuredDirectory) {
            configuredDirectory = explicit;
            directoryPath = chooseDirectory();
            initialSelectionPending = true;
        }
    }
    onTargetNameChanged: { if (open && boundScreenName && targetName !== boundScreenName) closeRequested(); }
    onScreenAliveChanged: { if (open && boundScreenName && !screenAlive) closeRequested(); }
    onPageSizeChanged: {
        if (selectedPath && filteredPaths.indexOf(selectedPath) >= 0)
            page = Math.floor(filteredPaths.indexOf(selectedPath) / pageSize);
        else
            page = Math.min(page, pageCount - 1);
        updateImageStatus();
    }
    onPageChanged: updateImageStatus()
    onSelectedPathChanged: updateImageStatus()
    Keys.onPressed: event => { event.accepted = handleKey(event); }

    FolderListModel {
        id: folderModel
        folder: root.open && root.directoryPath ? root.fileUrl(root.directoryPath) : "file:///nonexistent-dms-glass-wallpaper-source/"
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.bmp", "*.gif", "*.webp", "*.jxl", "*.avif", "*.heif", "*.exr"]
        caseSensitive: false
        showFiles: true
        showDirs: false
        showDotAndDotDot: false
        showHidden: false
        sortField: FolderListModel.Name
        sortReversed: false
        onStatusChanged: { if (root.open) root.rebuild(); }
        onCountChanged: { if (root.open && status === FolderListModel.Ready) root.rebuild(); }
    }
    FolderDialog {
        id: folderDialog
        title: "Вибрати теку шпалер"
        parentWindow: root.Window.window
        modality: Qt.WindowModal
        onAccepted: {
            root.directoryDialogPending = false;
            const path = root.localPath(selectedFolder);
            if (root.open && path) {
                root.configuredDirectory = path;
                root.directoryPath = path;
                root.initialSelectionPending = true;
                root.pendingPath = "";
                root.selectedPath = "";
                root.errorText = "";
                root.updateSetting("directory", path);
                if (folderModel.status === FolderListModel.Ready)
                    Qt.callLater(() => { if (root.open) root.rebuild(); });
            }
            Qt.callLater(() => { if (root.open) root.forceActiveFocus(); });
        }
        onRejected: {
            root.directoryDialogPending = false;
            Qt.callLater(() => { if (root.open) root.forceActiveFocus(); });
        }
    }
    Timer {
        id: openDirectoryTimer
        interval: 80
        onTriggered: {
            if (root.open && root.Window.window) folderDialog.open();
            else root.directoryDialogPending = false;
        }
    }
    function openDirectoryChooser() {
        if (!open || !root.Window.window || nativeDialogOpen) return;
        folderDialog.currentFolder = root.fileUrl(root.directoryPath || root.chooseDirectory());
        directoryDialogPending = true;
        openDirectoryTimer.start();
    }
    Loader {
        id: browser
        active: false
        sourceComponent: FileBrowserSurfaceModal {
            browserTitle: "Відкрити зображення"
            browserIcon: "folder_open"
            browserType: "wallpaper"
            showHiddenFiles: false
            fileExtensions: folderModel.nameFilters
            targetScreen: root.targetScreen
            onFileSelected: path => {
                const file = root.localPath(path);
                const dir = root.imageDirectory(file);
                if (dir) {
                    root.pendingPath = file;
                    root.selectedPath = file;
                    root.initialSelectionPending = true;
                    root.directoryPath = dir;
                    root.updateSetting("directory", dir);
                    if (folderModel.status === FolderListModel.Ready)
                        Qt.callLater(() => root.rebuild());
                }
                close();
            }
            onDialogClosed: Qt.callLater(() => { if (root.open) root.forceActiveFocus(); })
        }
    }
    function openFileChooser() {
        browser.active = true;
        Qt.callLater(() => { if (browser.item && root.open) browser.item.open(); });
    }

    palette.text: Theme.surfaceText
    palette.buttonText: Theme.surfaceText
    palette.base: Theme.surfaceContainer
    palette.button: Theme.surfaceContainerHigh
    palette.highlight: Theme.primary
    Rectangle {
        anchors.fill: parent
        color: Theme.withAlpha(Theme.surface, root.dimOpacity)
    }
    MouseArea { anchors.fill: parent; onClicked: root.closeRequested() }
    Rectangle {
        x: panel.x - 12; y: panel.y - 8
        width: panel.width + 24; height: gallery.y
        radius: Math.max(0, root.cornerRadius)
        color: Theme.withAlpha(Theme.surfaceContainer, .88)
    }
    Rectangle {
        x: panel.x - 12; y: panel.y + footerActions.y - 8
        width: panel.width + 24; height: footerStatus.y + footerStatus.height - footerActions.y + 16
        radius: Math.max(0, root.cornerRadius)
        color: Theme.withAlpha(Theme.surfaceContainer, .88)
    }
    MouseArea { x: panel.x; y: panel.y; width: panel.width; height: panel.height; onClicked: {} }
    Column {
        id: panel
        width: Math.min(root.width - 28, 1560 * root.adaptiveScale)
        height: Math.min(root.height - 28, Math.max(root.sliceHeight, root.expandedHeight) + 240)
        anchors.centerIn: parent
        spacing: 8
        Row {
            width: parent.width
            spacing: 12
            Text {
                width: Math.max(100, parent.width - 210)
                height: 40
                verticalAlignment: Text.AlignVCenter
                text: "Шпалери · " + (SessionData.perMonitorWallpaper ? root.boundScreenName : "Усі монітори")
                color: Theme.surfaceText
                font.pixelSize: 22
                font.bold: true
                elide: Text.ElideRight
            }
            DankButton {
                text: "⚙"
                Accessible.name: "Налаштування"
                ToolTip.visible: hovered
                ToolTip.text: Accessible.name
                onClicked: root.settingsRequested()
            }
            DankButton {
                text: "Закрити"
                Accessible.name: text
                onClicked: root.closeRequested()
            }
        }
        Row {
            width: parent.width
            spacing: 10
            Basic.TextField {
                id: searchField
                width: Math.max(120, parent.width - chooseButton.width - chooseFolderButton.width - 36)
                height: 40
                font.pixelSize: 14
                verticalAlignment: TextInput.AlignVCenter
                leftPadding: 10
                rightPadding: 10
                placeholderTextColor: Theme.surfaceTextMedium
                color: Theme.surfaceText
                selectionColor: Theme.primary
                background: Rectangle {
                    radius: 10
                    color: Theme.surfaceContainerHigh
                    border.color: searchField.activeFocus ? Theme.primary : Theme.outline
                    border.width: searchField.activeFocus ? 2 : 1
                }
                placeholderText: "Пошук за назвою або шляхом"
                Accessible.name: placeholderText
                onTextChanged: root.rebuild()
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape || event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        event.accepted = root.handleKey(event);
                    }
                }
            }
            DankButton {
                id: chooseFolderButton
                text: "Вибрати теку…"
                Accessible.name: text
                onClicked: root.openDirectoryChooser()
            }
            DankButton {
                id: chooseButton
                text: "Відкрити зображення…"
                Accessible.name: text
                onClicked: root.openFileChooser()
            }
        }
        Text {
            width: parent.width
            color: Theme.surfaceTextMedium
            text: "Тека: " + root.directoryPath
            elide: Text.ElideMiddle
            Accessible.name: text
        }
        Item {
            id: gallery
            width: parent.width
            height: Math.max(0, parent.height - 240)
            clip: true
            readonly property int selectedOnPage: root.pagePaths.indexOf(root.selectedPath)
            // Focused card remains centered; other cards may be clipped but remain reachable by wheel and page keys.
            MouseArea {
                anchors.fill: parent
                z: 100
                acceptedButtons: Qt.NoButton
                onWheel: event => {
                    root.lastHoverPosition = mapToGlobal(event.x, event.y);
                    if (event.angleDelta.y !== 0)
                        root.moveSelection(event.angleDelta.y < 0 ? 1 : -1);
                    event.accepted = true;
                }
            }
            Repeater {
                id: cards
                model: root.open ? root.poolSize : 0
                WallpaperThumbnail {
                    id: card
                    required property int index
                    readonly property int pathIndex: root.pooledPathIndex(index)
                    readonly property int pageIndex: pathIndex - root.page * root.pageSize
                    property bool recycled: false
                    onPathIndexChanged: {
                        recycled = true;
                        recycleTimer.restart();
                    }
                    Timer { id: recycleTimer; interval: 0; onTriggered: card.recycled = false }
                    visible: pathIndex >= root.firstPooledPath && pathIndex < Math.min(root.filteredPaths.length, (root.page + 1) * root.pageSize + 1)
                    imagePath: root.filteredPaths[pathIndex] || ""
                    selected: root.selectedPath === imagePath
                    currentWallpaper: root.currentWallpaper === imagePath
                    dimOpacity: root.inactiveDimOpacity
                    cornerRadius: root.cornerRadius
                    skewAngle: root.effectiveAngle
                    width: root.cardWidth(pageIndex)
                    height: root.cardHeight(pageIndex)
                    x: root.cardX(pageIndex)
                    y: (gallery.height - height) / 2
                    z: selected ? 2 : 1
                    Behavior on x { enabled: !recycled; NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                    Behavior on y { enabled: !recycled; NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                    Behavior on width { enabled: !recycled; NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                    Behavior on height { enabled: !recycled; NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                    onChosen: position => {
                        if (Math.hypot(position.x - root.lastHoverPosition.x, position.y - root.lastHoverPosition.y) < 3) return;
                        root.lastHoverPosition = position;
                        root.select(imagePath);
                    }
                    onActivated: {
                        root.select(imagePath);
                        root.selectedImageStatus = imageStatus;
                        root.applySelected();
                    }
                    onImageStatusChanged: {
                        if (selected)
                            root.selectedImageStatus = imageStatus;
                    }
                }
            }
            Column {
                anchors.centerIn: parent
                spacing: 10
                visible: root.open && root.filteredPaths.length === 0
                Text {
                    text: folderModel.status !== FolderListModel.Ready ? "Тека недоступна або завантажується: " + root.directoryPath : searchField.text ? "За цим запитом немає зображень" : "У теці немає зображень: " + root.directoryPath
                    color: Theme.surfaceText
                    width: Math.min(gallery.width - 20, 600)
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                }
                DankButton {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Вибрати зображення…"
                    onClicked: root.openFileChooser()
                }
            }
        }
        Row {
            id: footerActions
            width: parent.width
            spacing: 12
            DankButton {
                id: previousPageButton
                text: "Попередня сторінка"
                enabled: root.page > 0
                onClicked: root.changePage(-1)
            }
            Text {
                id: pageLabel
                height: 38
                verticalAlignment: Text.AlignVCenter
                color: Theme.surfaceText
                text: (root.page + 1) + " / " + root.pageCount + " · " + root.filteredPaths.length + " зображень"
            }
            DankButton {
                id: nextPageButton
                text: "Наступна сторінка"
                enabled: root.page < root.pageCount - 1
                onClicked: root.changePage(1)
            }
            Item { width: Math.max(0, parent.width - previousPageButton.width - pageLabel.implicitWidth - nextPageButton.width - applyButton.width - parent.spacing * 4); height: 1 }
            DankButton {
                id: applyButton
                text: "Застосувати"
                enabled: root.screenAlive && !root.applying && root.filteredPaths.indexOf(root.selectedPath) >= 0 && root.selectedImageStatus === Image.Ready
                onClicked: root.applySelected()
            }
        }
        Text {
            id: footerStatus
            width: parent.width
            height: 24
            color: root.errorText ? Theme.error : Theme.surfaceTextMedium
            text: root.errorText || (root.selectedImageStatus === Image.Error ? "Не вдалося відкрити зображення" : root.selectedPath || "Виберіть зображення. Escape — без змін, Enter — застосувати.")
            elide: Text.ElideMiddle
            Accessible.name: text
        }
    }
}
