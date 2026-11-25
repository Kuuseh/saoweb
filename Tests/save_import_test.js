/* 存档导入逻辑的单元测试（在 CI 里用 node 跑，不需要浏览器） */
const assert = require('assert');
const path = require('path');

const mod = require(path.join(__dirname, '..', 'Resources', 'save_import.js'));
const { buildEntry, playtimeText, keyFor } = mod;

let failures = 0;
function check(name, fn) {
  try {
    fn();
    console.log('  OK   ' + name);
  } catch (e) {
    failures++;
    console.log('  FAIL ' + name + ' :: ' + e.message);
  }
}

check('键名映射 fileN', () => {
  assert.strictEqual(keyFor('file1'), 'RPG File1');
  assert.strictEqual(keyFor('file12'), 'RPG File12');
});

check('键名映射 global/config', () => {
  assert.strictEqual(keyFor('global'), 'RPG Global');
  assert.strictEqual(keyFor('config'), 'RPG Config');
});

check('键名映射 其他', () => {
  assert.strictEqual(keyFor('file1_extra'), 'RPG file1_extra');
});

check('playtime 格式', () => {
  assert.strictEqual(playtimeText(0), '0:00');
  assert.strictEqual(playtimeText(59), '0:00');
  assert.strictEqual(playtimeText(60), '0:01');
  assert.strictEqual(playtimeText(3600), '1:00');
  assert.strictEqual(playtimeText(3725), '1:02');
  assert.strictEqual(playtimeText(undefined), '0:00');
});

const actors = [
  null,
  { characterName: 'Actor1', characterIndex: 0, faceName: 'Face1', faceIndex: 2 },
  { characterName: 'Actor2', characterIndex: 3, faceName: 'Face2', faceIndex: 5 }
];

check('索引项：队伍角色与立绘', () => {
  const contents = { party: { _actors: [1, 2] }, system: { _playtime: 3661 } };
  const e = buildEntry(3, contents, actors, 'MyGame');
  assert.strictEqual(e.globalId, 3);
  assert.strictEqual(e.title, 'MyGame');
  assert.strictEqual(e.playtime, '1:01');
  assert.deepStrictEqual(e.characters, [
    { name: 'Actor1', index: 0 },
    { name: 'Actor2', index: 3 }
  ]);
  assert.deepStrictEqual(e.faces, [
    { name: 'Face1', index: 2 },
    { name: 'Face2', index: 5 }
  ]);
  assert.ok(typeof e.timestamp === 'number' && e.timestamp > 0);
});

check('索引项：空队伍不崩', () => {
  const e = buildEntry(1, {}, actors, 'G');
  assert.deepStrictEqual(e.characters, []);
  assert.deepStrictEqual(e.faces, []);
  assert.strictEqual(e.playtime, '0:00');
});

check('索引项：缺失角色数据不影响', () => {
  const e = buildEntry(1, { party: { _actors: [99] }, system: {} }, actors, 'G');
  assert.deepStrictEqual(e.characters, [{ name: '', index: 0 }]);
});

if (failures > 0) {
  console.log('RESULT: ' + failures + ' failure(s)');
  process.exit(1);
}
console.log('RESULT: all passed');
process.exit(0);
