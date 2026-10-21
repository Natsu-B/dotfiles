// Exercise the same JS selection used inside the loaded DMS plugin.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(process.argv[2], 'utf8').replace(/^\.pragma library\s*\n/, '');
const model = {};
vm.runInNewContext(source, model);
const chrome = { appId: 'google-chrome', activated: false };
const a = { appId: 'chatgpt', activated: false };
const b = { appId: 'ChatGPT', activated: false };
const other = { appId: 'other', activated: false };
const other2 = { appId: 'other', activated: false };
const widget = { _groupByApp: true, groupedWindows: [
    { appId: 'other', windows: [{toplevel: other}, {toplevel: other2}] },
    { appId: 'chatgpt', windows: [{toplevel: a}, {toplevel: b}] },
    { appId: 'google-chrome', windows: [{toplevel: chrome}] }
], sortedToplevels: [other, a, b, chrome] };
const windows = [other, a, b, chrome];
assert.deepEqual(Array.from(model.entries(null), e => e.appId),
    ['google-chrome', 'kitty', 'code', 'chatgpt', 'discord', 'slack']);
assert.equal(model.windowAt(widget, 1, windows), chrome);
assert.equal(model.windowAt(widget, 2, windows), null); // kitty reserves its slot while closed
assert.equal(model.fixedApp(2).appId, 'kitty');
assert.equal(model.windowAt(widget, 4, windows), a);
a.activated = true;
assert.equal(model.windowAt(widget, 4, windows), b);
a.activated = false; b.activated = true;
assert.equal(model.windowAt(widget, 4, windows), a); // cycling wraps
chrome.activated = true;
assert.equal(model.windowAt(widget, 1, windows), chrome); // no minimize toggle
widget.groupedWindows.reverse();
assert.equal(model.windowAt(widget, 1, windows), chrome); // reordering cannot change reserved slots
assert.equal(model.windowAt(widget, 4, windows), a);
assert.equal(model.windowAt(widget, 7, windows), other); // non-fixed apps fill the remaining slots
other.activated = true;
assert.equal(model.windowAt(widget, 7, windows), other2);
assert.equal(model.windowAt(null, 4, windows), a); // fixed slots do not depend on a rendered bar
widget._groupByApp = false;
assert.equal(model.windowAt(widget, 7, windows), other);
assert.equal(model.windowAt(widget, 8, windows), null);
for (const index of [0, -1, 1.5, 11, '1'])
    assert.equal(model.windowAt(widget, index, windows), null);
assert.equal(model.windowAt(null, 7, windows), null);
assert.equal(model.fixedApp(7), null);
const many = {_groupByApp: false, sortedToplevels: Array.from({length: 10}, (_,i) => ({appId: String(i)}))};
assert.equal(model.entries(many).length, 10);
assert.equal(model.windowAt(many, 10, windows), many.sortedToplevels[3]);
assert.equal(model.slotFor(widget, 'google-chrome-stable', chrome), 1);
assert.equal(model.slotFor(widget, 'ChatGPT', b), 4);
assert.equal(model.slotFor(widget, 'other', other), 7);
assert.equal(model.slotFor(many, '3', many.sortedToplevels[3]), 10);
assert.equal(model.slotFor(many, '4', many.sortedToplevels[4]), 0); // no shortcut after Win+0
assert.equal(model.slotFor(null, 'kitty', null), 2);
assert.equal(model.slotFor(null, 'missing', null), 0);
widget._groupByApp = true;
assert.equal(model.slotFor(widget, 'other', other2), 7); // grouped windows share the same number
assert.equal(model.hyprlandAddress('abc123'), '0xabc123');
assert.equal(model.hyprlandAddress('0xABC123'), '0xABC123');
for (const address of ['', undefined, null, 123, 'active', 'abc"})', '0x', ' 123'])
    assert.equal(model.hyprlandAddress(address), null);
console.log('App slots: fixed IDs, closed apps, bar reordering, global windows, cycling and address validation verified');
