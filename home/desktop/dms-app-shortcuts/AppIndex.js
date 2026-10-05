.pragma library

// Read the rendered widget's model rather than reconstructing its order.
function entries(widget) {
    if (!widget)
        return [];
    return (widget._groupByApp ? widget.groupedWindows : widget.sortedToplevels) || [];
}

function windowAt(widget, index) {
    if (!Number.isInteger(index) || index < 1 || index > 10)
        return null;
    const entry = entries(widget)[index - 1];
    if (!entry)
        return null;
    if (!widget._groupByApp)
        return entry;
    const windows = entry.windows || [];
    if (!windows.length)
        return null;
    const active = windows.findIndex(w => w.toplevel?.activated);
    return windows[(active + 1) % windows.length].toplevel || null;
}

function hyprlandSelector(address) {
    if (typeof address !== "string" || !/^(?:0x)?[0-9a-f]+$/i.test(address))
        return null;
    // Quickshell exposes bare hex; the Lua selector uses the 0x prefix.
    return "address:0x" + address.replace(/^0x/i, "");
}
