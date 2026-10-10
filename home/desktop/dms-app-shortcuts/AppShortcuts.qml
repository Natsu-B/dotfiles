import Quickshell.Io
import Quickshell.Hyprland
import qs.Modules.Plugins
import qs.Services
import "AppIndex.js" as AppIndex

// An in-process IPC extension; no extra bar widget or polling daemon.
PluginComponent {
    id: root

    IpcHandler {
        target: "dotfiles-apps"

        function activate(index: int): string {
            const widget = BarWidgetService.getWidgetOnFocusedScreen("runningApps");
            const window = AppIndex.windowAt(widget, index);
            if (!window)
                return "APP_INDEX_UNAVAILABLE";
            // Keep a single active window in front; repeated shortcuts cycle
            // within a grouped app instead of toggling its minimized state.
            if (CompositorService.isHyprland) {
                // Passive Wayland activation can be ignored with Hyprland's
                // default focus_on_activate=false. This user shortcut is an
                // explicit focus command, scoped to the chosen native address.
                const native = Array.from(Hyprland.toplevels.values).find(t => t.wayland === window);
                const selector = AppIndex.hyprlandSelector(native?.address);
                if (!selector)
                    return "APP_WINDOW_UNAVAILABLE";
                Hyprland.dispatch("hl.dsp.focus({window=" + JSON.stringify(selector) + "})");
            } else {
                CompositorService.activateToplevel(window);
            }
            return "APP_ACTIVATED";
        }

        function list(): string {
            const widget = BarWidgetService.getWidgetOnFocusedScreen("runningApps");
            return JSON.stringify(AppIndex.entries(widget).slice(0, 10).map((entry, i) => ({
                number: i + 1, appId: entry.appId || "unknown"
            })));
        }
    }
}
