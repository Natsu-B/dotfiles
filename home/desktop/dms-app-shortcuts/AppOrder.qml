import QtQuick
import QtQml.Models
import "AppIndex.js" as AppIndex

// Sort the native Running Apps model without replacing its icon delegates.
// Binding restores the original model binding when this extension is unloaded.
QtObject {
    id: root
    required property var widget

    property Component bindingComponent: Component {
        Binding {
            required property var listModel
            target: listModel
            property: "values"
            value: AppIndex.orderedEntries(root.widget)
            restoreMode: Binding.RestoreBindingOrValue
        }
    }

    property Component watcherComponent: Component {
        QtObject {
            id: watcher
            required property var targetItem
            property var boundModel: null
            property var orderBinding: null

            function attach() {
                const model = targetItem?.model;
                if (!model || model.values === undefined || model.objectProp === undefined || model === boundModel)
                    return;
                if (orderBinding)
                    orderBinding.destroy();
                boundModel = model;
                orderBinding = root.bindingComponent.createObject(watcher, {listModel: model});
            }

            Component.onCompleted: attach()
            property Connections modelChanges: Connections {
                target: watcher.targetItem
                ignoreUnknownSignals: true
                function onModelChanged() { watcher.attach(); }
            }

            property Instantiator descendants: Instantiator {
                model: watcher.targetItem ? Array.from(watcher.targetItem.children || []) : []
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
