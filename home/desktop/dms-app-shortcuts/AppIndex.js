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

function hyprlandAddress(address) {
    if (typeof address !== "string" || !/^(?:0x)?[0-9a-f]+$/i.test(address))
        return null;
    return "0x" + address.replace(/^0x/i, "");
}
