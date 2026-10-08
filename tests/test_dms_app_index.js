// Exercise the same JS model selection used inside the loaded DMS plugin.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(process.argv[2], 'utf8').replace(/^\.pragma library\s*\n/, '');
const model = {};
vm.runInNewContext(source, model);
const a = { appId: 'chat', activated: false };
const b = { appId: 'chat', activated: false };
const c = { appId: 'terminal', activated: false };
const widget = { _groupByApp: true, groupedWindows: [
    { appId: 'terminal', windows: [{toplevel: c}] },
    { appId: 'chat', windows: [{toplevel: a}, {toplevel: b}] }
], sortedToplevels: [a, b, c] };
assert.equal(model.windowAt(widget, 1), c); // bar group order, not raw window order
assert.equal(model.windowAt(widget, 2), a); // first window when the app is inactive
a.activated = true;
assert.equal(model.windowAt(widget, 2), b);
a.activated = false; b.activated = true;
assert.equal(model.windowAt(widget, 2), a); // grouped cycling wraps
c.activated = true;
assert.equal(model.windowAt(widget, 1), c); // single app stays in front
for (const index of [0, -1, 1.5, 3, 11, '1'])
    assert.equal(model.windowAt(widget, index), null);
assert.equal(model.windowAt(null, 1), null);
assert.equal(model.windowAt({_groupByApp: true, groupedWindows: [{windows: []}]}, 1), null);
widget.groupedWindows.reverse();
assert.equal(model.windowAt(widget, 1), a); // a live bar reorder is used immediately
widget._groupByApp = false;
assert.equal(model.windowAt(widget, 1), a);
assert.equal(model.windowAt(widget, 3), c);
assert.equal(model.windowAt(widget, 10), null);
const ten = {_groupByApp: false, sortedToplevels: Array.from({length: 10}, (_,i) => ({appId: String(i)}))};
assert.equal(model.windowAt(ten, 10), ten.sortedToplevels[9]);
assert.equal(model.hyprlandSelector('abc123'), 'address:0xabc123');
assert.equal(model.hyprlandSelector('0xABC123'), 'address:0xABC123');
for (const address of ['', undefined, null, 123, 'active', 'abc"})', '0x', ' 123'])
    assert.equal(model.hyprlandSelector(address), null);
console.log('Bar app index: order, cycling, missing entries, 10th app and native address selection verified');
