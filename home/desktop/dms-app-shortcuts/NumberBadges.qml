import QtQuick
import QtQml.Models
import qs.Common
import qs.Widgets
import "AppIndex.js" as AppIndex

// Decorate the existing Running Apps items, preserving their menus, tooltips,
// drag handling and window-count badges. Observe child changes instead of polling.
QtObject {
    id: root
    required property var widget

    property Component badgeComponent: Component {
        Rectangle {
            objectName: "dotfilesAppNumberBadge"
            required property var appItem
            readonly property int slot: AppIndex.slotFor(root.widget, appItem.appId, appItem.toplevelObject)
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.rightMargin: Math.max(0, parent.width - root.widget.iconCellSize)
            width: 14
            height: 14
            radius: 7
            z: 20
            visible: slot > 0
            color: Theme.surface
            border.width: 1
            border.color: Theme.primary
            Accessible.name: "Win+" + (slot % 10)
            Accessible.role: Accessible.StaticText

            StyledText {
                anchors.centerIn: parent
                text: String(parent.slot % 10)
                font.pixelSize: 10
                font.bold: true
                color: Theme.primary
            }
        }
    }

    property Component watcherComponent: Component {
      QtObject {
        id: watcher
        required property var targetItem
        property var badge: null

        function attach() {
            if (!targetItem || badge || targetItem.appId === undefined ||
                    targetItem.toplevelObject === undefined || targetItem.isGrouped === undefined)
                return;
            badge = root.badgeComponent.createObject(targetItem, {appItem: targetItem});
        }

        Component.onCompleted: attach()
        Component.onDestruction: {
            if (badge)
                badge.destroy();
        }

        property Instantiator descendants: Instantiator {
            model: watcher.targetItem ? Array.from(watcher.targetItem.children || [])
                .filter(item => item.objectName !== "dotfilesAppNumberBadge") : []
            delegate: QtObject {
                id: branch
                required property var modelData
                property var observer: null
                function observe() {
                    if (observer)
                        observer.destroy();
                    observer = root.watcherComponent.createObject(branch, {targetItem: modelData});
                }
                onModelDataChanged: observe()
                Component.onCompleted: {
                    if (!observer)
                        observe();
                }
            }
        }
      }
    }

    property var tree: null
    Component.onCompleted: tree = watcherComponent.createObject(root, {targetItem: widget})
}
