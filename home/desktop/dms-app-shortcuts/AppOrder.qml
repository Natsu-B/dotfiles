import QtQuick
import QtQml.Models
import "AppIndex.js" as AppIndex

// Pin the fixed apps in the native Running Apps model and dim closed apps.
// Binding restores the original model binding when this extension is unloaded.
QtObject {
    id: root
    required property var widget
    required property var allWindows
    required property var activateSlot

    property Binding showPinnedApps: Binding {
        target: root.widget
        property: "visible"
        value: true
        restoreMode: Binding.RestoreBindingOrValue
    }

    property Component bindingComponent: Component {
        Binding {
            required property var listModel
            target: listModel
            property: "values"
            value: AppIndex.pinnedEntries(root.widget, root.allWindows)
            restoreMode: Binding.RestoreBindingOrValue
        }
    }

    property Component appComponent: Component {
        Item {
            id: app
            objectName: "dotfilesPinnedAppHook"
            required property var appItem
            readonly property int slot: AppIndex.fixedApps.findIndex(fixed => AppIndex.matches(fixed, appItem.appId)) + 1
            readonly property bool idle: appItem.isGrouped
                ? appItem.groupData?.pinnedIdle === true : appItem.toplevelObject?.pinnedIdle === true
            anchors.fill: parent
            z: 100

            Binding {
                target: app.appItem
                property: "opacity"
                when: app.slot > 0
                value: app.idle ? 0.4 : 1
                restoreMode: Binding.RestoreBindingOrValue
            }
            Binding {
                target: app.appItem
                property: "isFocused"
                when: app.slot > 0
                value: app.slot > 0 && root.allWindows.some(window => window.activated &&
                    AppIndex.matches(AppIndex.fixedApps[app.slot - 1], window.appId))
                restoreMode: Binding.RestoreBindingOrValue
            }
            Binding {
                target: app.appItem
                property: "tooltipText"
                when: app.idle
                value: app.slot > 0 ? AppIndex.fixedApps[app.slot - 1].label + " — 未起動（クリックして起動）" : ""
                restoreMode: Binding.RestoreBindingOrValue
            }

            MouseArea {
                anchors.fill: parent
                visible: app.idle
                enabled: app.idle
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onClicked: mouse => {
                    if (mouse.button === Qt.LeftButton)
                        root.activateSlot(app.slot);
                }
            }
        }
    }

    property Component watcherComponent: Component {
        QtObject {
            id: watcher
            required property var targetItem
            property var boundModel: null
            property var orderBinding: null
            property var appHook: null
            readonly property bool isAppItem: targetItem?.appId !== undefined &&
                targetItem.toplevelObject !== undefined && targetItem.isGrouped !== undefined

            function attach() {
                const model = targetItem?.model;
                if (model && model.values !== undefined && model.objectProp !== undefined && model !== boundModel) {
                    if (orderBinding)
                        orderBinding.destroy();
                    boundModel = model;
                    orderBinding = root.bindingComponent.createObject(watcher, {listModel: model});
                }
                if (!appHook && isAppItem)
                    appHook = root.appComponent.createObject(targetItem, {appItem: targetItem});
            }

            Component.onCompleted: Qt.callLater(attach)
            Component.onDestruction: {
                if (appHook)
                    appHook.destroy();
            }
            property Connections modelChanges: Connections {
                target: watcher.targetItem
                ignoreUnknownSignals: true
                function onModelChanged() { Qt.callLater(watcher.attach); }
            }

            property Instantiator descendants: Instantiator {
                // Stop at each app delegate: adding its click overlay must not
                // rebuild observers while that overlay is still being created.
                model: watcher.targetItem && !watcher.isAppItem ? Array.from(watcher.targetItem.children || []) : []
                delegate: QtObject {
                    id: branch
                    required property var modelData
                    property var observer: null
                    function observe() {
                        if (observer && observer.targetItem === modelData)
                            return;
                        if (observer)
                            observer.destroy();
                        observer = root.watcherComponent.createObject(branch, {targetItem: modelData});
                    }
                    // The same dynamic component is used at every tree depth.
                    // Finish this creation before creating its descendants.
                    onModelDataChanged: Qt.callLater(observe)
                    Component.onCompleted: Qt.callLater(observe)
                }
            }
        }
    }

    property var tree: null
    Component.onCompleted: tree = watcherComponent.createObject(root, {targetItem: widget})
}
