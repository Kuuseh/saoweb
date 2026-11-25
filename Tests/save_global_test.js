/* 校验随包携带的存档索引（Resources/save_global.txt）
 *
 * 用游戏自带的 lz-string 解压，确认能还原成 20 条合法索引。
 * 这样「索引打错包」会在 CI 里被拦住，而不是等到手机上才发现。
 */
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const LZString = require(path.join(__dirname, 'vendor', 'lz-string.js'));

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

const indexPath = path.join(__dirname, '..', 'Resources', 'save_global.txt');
check('索引文件存在', () => {
  assert.ok(fs.existsSync(indexPath), '缺少 Resources/save_global.txt');
});

let decoded = null;
check('索引可解压', () => {
  const raw = fs.readFileSync(indexPath, 'utf8').trim();
  assert.ok(raw.length > 100, '索引过短: ' + raw.length);
  const json = LZString.decompressFromBase64(raw);
  assert.ok(json, '解压结果为空');
  decoded = JSON.parse(json);
  assert.ok(Array.isArray(decoded), '不是数组');
});

check('索引槽位数量合理', () => {
  assert.ok(decoded.length >= 1 && decoded.length <= 20, '槽位数异常: ' + (decoded && decoded.length));
});

check('索引字段完整', () => {
  const filled = decoded.filter(Boolean);
  assert.ok(filled.length >= 1, '没有有效槽位');
  for (const e of filled) {
    assert.strictEqual(typeof e.globalId, 'number');
    assert.strictEqual(typeof e.title, 'string');
    assert.ok(Array.isArray(e.characters), 'characters 不是数组');
    assert.ok(Array.isArray(e.faces), 'faces 不是数组');
    assert.strictEqual(typeof e.playtime, 'string');
    assert.ok(/^\d+:\d{2}$/.test(e.playtime), 'playtime 格式异常: ' + e.playtime);
    assert.strictEqual(typeof e.timestamp, 'number');
  }
});

check('至少有一个存档带角色立绘信息', () => {
  const withChars = decoded.filter(e => e && e.characters && e.characters.length > 0);
  assert.ok(withChars.length >= 1, '所有槽位的角色信息都是空的');
});

if (failures > 0) {
  console.log('RESULT: ' + failures + ' failure(s)');
  process.exit(1);
}
console.log('RESULT: all passed');
process.exit(0);
