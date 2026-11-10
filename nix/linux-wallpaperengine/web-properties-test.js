const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const script = fs.readFileSync(process.argv[2], 'utf8');

for (const delayed of [false, true]) {
    const calls = [];
    const timers = new Map();
    const listener = {applyUserProperties(properties) {
        assert.equal(this, listener);
        calls.push(properties);
    }};
    const context = {
        window: delayed ? {} : {wallpaperPropertyListener: listener},
        setInterval(callback) { timers.set(1, callback); return 1; },
        clearInterval(id) { timers.delete(id); }
    };
    vm.runInNewContext(script, context);
    if (delayed) {
        assert.equal(calls.length, 0);
        timers.get(1)();
        assert.equal(calls.length, 0);
        context.window.wallpaperPropertyListener = listener;
        timers.get(1)();
    }
    assert.equal(calls.length, 1);
    assert.equal(timers.size, 0);
    const properties = calls[0];
    assert.equal(properties.paused.value, true);
    assert.equal(properties.speed.value, 0.5);
    assert.equal(properties.bgcolor.value, '1 0 0');
    assert.equal(properties.numberchoice.value, 2);
    assert.equal(properties.stringchoice.value, 'night');
    assert.equal(properties.text.value, 'quote" newline\n U+2028:\u2028');
    assert.equal(properties.empty.value, '');
}

const neverTimers = new Map();
vm.runInNewContext(script, {
    window: {},
    setInterval(callback) { neverTimers.set(1, callback); return 1; },
    clearInterval(id) { neverTimers.delete(id); }
});
for (let i = 0; i < 100; i++) neverTimers.get(1)();
assert.equal(neverTimers.size, 0);

console.log('Web properties preserve types and reach immediate and delayed listeners.');
