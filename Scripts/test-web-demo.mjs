import assert from 'node:assert/strict';
import { cleanupValue, pressureLevel, rangePosition } from '../docs/script.js';

assert.equal(pressureLevel(89.9), 'normal');
assert.equal(pressureLevel(90), 'warning');
assert.equal(pressureLevel(95), 'critical');
assert.equal(cleanupValue(96, 0), 96);
assert.equal(cleanupValue(96, 1), 84);
assert.ok(cleanupValue(96, 0.5) < 96);
assert.equal(rangePosition(70), 0);
assert.equal(rangePosition(99), 100);

console.log('Web storage model: OK');
