.pragma library

// Reserve these slots even while an app has no windows. Match native app IDs,
// never titles (which change with tabs, documents and conversations).
var fixedApps = [
    {appId: "google-chrome", label: "Chrome", aliases: ["google-chrome", "google-chrome-stable"]},
    {appId: "kitty", label: "kitty", aliases: ["kitty"]},
    {appId: "code", label: "VS Code", aliases: ["code", "code-url-handler"]},
    {appId: "chatgpt", label: "ChatGPT", aliases: ["chatgpt"]},
    {appId: "discord", label: "Discord", aliases: ["discord"]},
    {appId: "slack", label: "Slack", aliases: ["slack"]}
];

function matches(app, appId) {
    return app.aliases.indexOf(String(appId || "").toLowerCase()) >= 0;
}

function fixedApp(index) {
    return Number.isInteger(index) ? fixedApps[index - 1] || null : null;
}

// DMS 2 registers instances by screen/instance ID; older versions nested
// screen widgets below the widget ID. Unwrap registrations to actual items.
function runningWidgets(registry) {
    if (!registry)
        return [];
    const values = registry.runningApps
        ? Object.values(registry.runningApps)
        : Object.values(registry).filter(entry => entry?.widgetId === "runningApps").map(entry => entry.item);
    return values.filter((item, index) => item && values.indexOf(item) === index);
}

function entries(widget) {
    const bar = widget ? ((widget._groupByApp ? widget.groupedWindows : widget.sortedToplevels) || []) : [];
    return fixedApps.concat(bar.filter(entry => !fixedApps.some(app => matches(app, entry.appId)))).slice(0, 10);
}

function nextWindow(windows) {
    if (!windows.length)
        return null;
    const active = windows.findIndex(w => w.activated);
    return windows[(active + 1) % windows.length] || null;
}

function windowAt(widget, index, toplevels) {
    if (!Number.isInteger(index) || index < 1 || index > 10)
        return null;
    const app = fixedApp(index);
    if (app)
        return nextWindow(Array.from(toplevels || []).filter(w => matches(app, w.appId)));
    const entry = entries(widget)[index - 1];
    if (!entry)
        return null;
    if (!widget._groupByApp)
        return entry;
    return nextWindow((entry.windows || []).map(w => w.toplevel).filter(Boolean));
}

// Keep native app icons in shortcut order; retain the existing order within
// each app and among the other apps, including those beyond Win+0.
function orderedEntries(widget) {
    const values = widget ? ((widget._groupByApp ? widget.groupedWindows : widget.sortedToplevels) || []) : [];
    return values.map((entry, index) => {
        const fixed = fixedApps.findIndex(app => matches(app, entry.appId));
        return {entry: entry, index: index, rank: fixed < 0 ? fixedApps.length : fixed};
    }).sort((a, b) => a.rank - b.rank || a.index - b.index).map(item => item.entry);
}

// Include a launchable placeholder for every fixed app, even on an empty desktop.
// Real windows are used globally so workspace/display filters do not dim open apps.
function pinnedEntries(widget, toplevels) {
    const grouped = !widget || widget._groupByApp;
    const windows = Array.from(toplevels || []);
    const pinned = [];
    for (const app of fixedApps) {
        const running = windows.filter(window => matches(app, window.appId));
        if (grouped)
            pinned.push({appId: app.appId, pinnedIdle: running.length === 0,
                windows: running.map(toplevel => ({toplevel: toplevel, windowId: windows.indexOf(toplevel),
                    windowTitle: toplevel.title || ""}))});
        else if (running.length)
            pinned.push(...running);
        else
            pinned.push({appId: app.appId, pinnedIdle: true, title: "未起動", activated: false,
                address: "pinned:" + app.appId, aqueousKey: "pinned:" + app.appId});
    }
    return pinned.concat(orderedEntries(widget).filter(entry => !fixedApps.some(app => matches(app, entry.appId))));
}

function hyprlandAddress(address) {
    if (typeof address !== "string" || !/^(?:0x)?[0-9a-f]+$/i.test(address))
        return null;
    return "0x" + address.replace(/^0x/i, "");
}
