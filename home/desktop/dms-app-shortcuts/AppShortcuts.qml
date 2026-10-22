import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQml.Models
import qs.Modules.Plugins
import qs.Services
import "AppIndex.js" as AppIndex
import "AppCommands.js" as AppCommands

// An in-process IPC extension; no extra bar widget or polling daemon.
PluginComponent {
    id: root
    property var launching: ({})
    property var allWindows: ToplevelManager.toplevels.values
    onAllWindowsChanged: {
        for (const app of AppIndex.fixedApps) {
            if (Array.from(allWindows).some(window => AppIndex.matches(app, window.appId)))
                launching[app.appId] = 0;
        }
    }

    Instantiator {
        model: Object.values(BarWidgetService.widgetRegistry.runningApps || {})
        delegate: AppOrder {
            required property var modelData
            widget: modelData
            allWindows: root.allWindows
            activateSlot: index => root.activate(index)
        }
    }

    function activate(index) {
        const widget = BarWidgetService.getWidgetOnFocusedScreen("runningApps");
        const window = AppIndex.windowAt(widget, index, root.allWindows);
        if (!window) {
            const app = AppIndex.fixedApp(index);
            if (!app)
                return "APP_INDEX_UNAVAILABLE";
            // Ignore repeats while a cold start is still creating its window.
            if (Date.now() - (root.launching[app.appId] || 0) < 15000)
                return "APP_LAUNCH_PENDING";
            root.launching[app.appId] = Date.now();
            Quickshell.execDetached(AppCommands.launch[app.appId]);
            if (CompositorService.isHyprland)
                Quickshell.execDetached([AppCommands.focus, "--app", app.aliases.join(",")]);
            return "APP_LAUNCHED";
        }
        // Repeated shortcuts cycle windows within the same app. A single
        // window stays visible rather than toggling its minimized state.
        if (CompositorService.isHyprland) {
            const native = Array.from(Hyprland.toplevels.values).find(t => t.wayland === window);
            const address = AppIndex.hyprlandAddress(native?.address);
            if (!address)
                return "APP_WINDOW_UNAVAILABLE";
            Quickshell.execDetached([AppCommands.focus, "--address", address]);
        } else {
            CompositorService.activateToplevel(window);
        }
        return "APP_ACTIVATION_REQUESTED";
    }

    IpcHandler {
        target: "dotfiles-apps"

        function activate(index: int): string {
            return root.activate(index);
        }

        function list(): string {
            const widget = BarWidgetService.getWidgetOnFocusedScreen("runningApps");
            return JSON.stringify(AppIndex.entries(widget).map((entry, i) => ({
                number: i + 1, appId: entry.appId || "unknown", fixed: i < AppIndex.fixedApps.length
            })));
        }
    }
}
