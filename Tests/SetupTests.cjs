const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
const storage = fs.mkdtempSync(path.join(os.tmpdir(), 'casamenu-setup-'));
try {
 const run = () => spawnSync(process.execPath, ['HomeKit/setup.mjs', storage], {env: {...process.env, CASAMENU_TEST_EMPTY_INVENTORY:'1'}, encoding:'utf8'});
 assert.equal(run().status, 0, 'First launch must work without Gree');
 const file = path.join(storage,'config.json');
 const original = fs.readFileSync(file);
 const config = JSON.parse(original);
 assert.match(config.bridge.pin, /^\d{3}-\d{2}-\d{3}$/);
 assert.equal(config.platforms[0].host, '127.0.0.1');
 assert.equal(fs.statSync(file).mode & 0o777, 0o600);
 assert.equal(run().status, 0);
 assert.deepEqual(fs.readFileSync(file), original, 'Existing pairing must never be overwritten');
 console.log('Setup PASS: empty home, private config, stable pairing on repeated launch');
} finally { fs.rmSync(storage,{recursive:true,force:true}); }
