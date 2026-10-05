import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import qs.Common
import qs.Widgets

ColumnLayout {
    id: root
    required property string label
    property string description: ""
    property string unit: "px"
    property real value: 0
    property real minimum: 0
    property real maximum: 100
    property real step: 1
    property bool slider: unit === "%"
    signal edited(real number)
    spacing: 4
    function commit(number) {
        if (Number.isFinite(number)) edited(Math.max(minimum, Math.min(maximum, number)));
    }
    Text { Layout.fillWidth: true; text: root.label; wrapMode: Text.WordWrap; color: Theme.surfaceText; font.pixelSize: 14 }
    Text { Layout.fillWidth: true; visible: text.length > 0; text: root.description; wrapMode: Text.WordWrap; color: Theme.surfaceTextSecondary; font.pixelSize: 12 }
    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        DankButton { text: "−"; Layout.preferredWidth: 34; buttonHeight: 34; Accessible.name: "Зменшити: " + root.label; onClicked: root.commit(root.value - root.step) }
        DankTextField {
            Layout.preferredWidth: 86
            Layout.minimumWidth: 64
            text: String(Math.round(root.value * 100) / 100)
            Accessible.name: root.label + " (" + root.unit + ")"
            validator: DoubleValidator { bottom: root.minimum; top: root.maximum; decimals: 2; locale: "C" }
            onEditingFinished: root.commit(Number(text.replace(",", ".")))
        }
        DankButton { text: "+"; Layout.preferredWidth: 34; buttonHeight: 34; Accessible.name: "Збільшити: " + root.label; onClicked: root.commit(root.value + root.step) }
        Text { text: root.unit; color: Theme.surfaceTextSecondary; font.pixelSize: 12 }
        Item { Layout.fillWidth: true }
    }
    Controls.Slider {
        id: range
        visible: root.slider
        Layout.fillWidth: true
        from: root.minimum; to: root.maximum; stepSize: root.step
        value: root.value
        Accessible.name: root.label
        onMoved: root.commit(value)
        background: Rectangle { x: range.leftPadding; y: range.topPadding + range.availableHeight / 2 - 2; width: range.availableWidth; height: 4; radius: 2; color: Theme.outline }
        handle: Rectangle { x: range.leftPadding + range.visualPosition * (range.availableWidth - width); y: range.topPadding + range.availableHeight / 2 - height / 2; width: 18; height: 18; radius: 9; color: Theme.primary; border.width: range.activeFocus ? 2 : 0; border.color: Theme.surfaceText }
    }
}
