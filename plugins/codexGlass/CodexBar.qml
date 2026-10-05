import QtQuick
import QtQuick.Controls
import qs.Modules.Plugins

PluginComponent {
    id: root
    horizontalBarPill: Component {
        CodexQuota {
            scaleFactor: 1
            width: implicitWidth + 12
            height: root.widgetThickness
            HoverHandler { id: hover }
            ToolTip.visible: hover.hovered
            ToolTip.text: tooltipText
        }
    }
}
