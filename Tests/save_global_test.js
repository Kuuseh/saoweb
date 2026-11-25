/* 校验随包携带的存档索引（Resources/save_global.txt）
 *
 * 契约来自本项目 rpg_managers.js 的实测实现：
 *   - 索引 0 空置，存档 N 位于索引 N（1..maxSavefiles）
 *   - isThisGameFile 要求 globalId === 'RPGMV' 且 title === $dataSystem.gameTitle
 *   - isAnySavefileExists 从索引 1 开始遍历
 */
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const LZString = require(path.join(__dirname, 'vendor', 'lz-string.js'));

const GLOBAL_ID = 'RPGMV';

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

check('索引 0 位空置（MV 约定）', () => {
  assert.strictEqual(decoded[0], null, '索引 0 应为 null，实际: ' + JSON.stringify(decoded[0]));
});

check('槽位数量合理', () => {
  assert.ok(decoded.length >= 2 && decoded.length <= 100, '槽位数异常: ' + decoded.length);
});

check('globalId 必须是 RPGMV', () => {
  const filled = decoded.filter(Boolean);
  assert.ok(filled.length >= 1, '没有有效槽位');
  for (const e of filled) {
    assert.strictEqual(e.globalId, GLOBAL_ID, 'globalId 错误: ' + JSON.stringify(e.globalId));
  }
});

check('savefileId 与索引位置一致', () => {
  for (let i = 1; i < decoded.length; i++) {
    if (!decoded[i]) continue;
    assert.strictEqual(decoded[i].savefileId, i, '索引 ' + i + ' 的 savefileId 是 ' + decoded[i].savefileId);
  }
});

check('索引字段完整', () => {
  const filled = decoded.filter(Boolean);
  for (const e of filled) {
    assert.strictEqual(typeof e.title, 'string');
    assert.ok(e.title.length > 0, 'title 为空');
    assert.ok(Array.isArray(e.characters), 'characters 不是数组');
    assert.ok(Array.isArray(e.faces), 'faces 不是数组');
    assert.ok(/^\d+:\d{2}$/.test(e.playtime), 'playtime 格式异常: ' + e.playtime);
    assert.strictEqual(typeof e.timestamp, 'number');
  }
});

check('至少有一个存档带角色立绘信息', () => {
  const withChars = decoded.filter(e => e && e.characters && e.characters.length > 0);
  assert.ok(withChars.length >= 1, '所有槽位的角色信息都是空的');
});

check('title 与 System.json 的 gameTitle 一致', () => {
  const www = process.env.SAO_WWW;
  if (!www || !fs.existsSync(path.join(www, 'data', 'System.json'))) {
    console.log('       （跳过：未提供 SAO_WWW 环境变量）');
    return;
  }
  const sys = JSON.parse(fs.readFileSync(path.join(www, 'data', 'System.json'), 'utf8'));
  const filled = decoded.filter(Boolean);
  assert.strictEqual(filled[0].title, sys.gameTitle, 'title 与游戏标题不一致');
});

if (failures > 0) {
  console.log('RESULT: ' + failures + ' failure(s)');
  process.exit(1);
}
console.log('RESULT: all passed');
process.exit(0);
