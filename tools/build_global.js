/* 在 PC 上预先生成 MV 的存档索引（RPG Global）
 *
 * 依赖游戏自带的 js/libs/lz-string.js，不依赖浏览器环境。
 * 输出: www/save/__global.txt   （LZString 压缩后的索引数组，App 直接写进 localStorage）
 */
const fs = require('fs');
const path = require('path');

const www = process.argv[2];
if (!www) {
  console.error('usage: node build_global.js <www dir>');
  process.exit(2);
}

const LZString = require(path.join(www, 'js', 'libs', 'lz-string.js'));

const systemData = JSON.parse(fs.readFileSync(path.join(www, 'data', 'System.json'), 'utf8'));
const actorsData = JSON.parse(fs.readFileSync(path.join(www, 'data', 'Actors.json'), 'utf8'));
const gameTitle = systemData.gameTitle || '';

function playtimeText(t) {
  t = Number(t) || 0;
  const hour = Math.floor(t / 3600);
  const min = Math.floor(t / 60) % 60;
  return hour + ':' + (min < 10 ? '0' : '') + min;
}

/* JsonEx 把数组存成 {"@c": 类号, "@a": [...]}，空数组是 {"@c": 类号} */
function jsonExArray(v) {
  if (Array.isArray(v)) return v;
  if (v && typeof v === 'object' && Array.isArray(v['@a'])) return v['@a'];
  return [];
}

function buildEntry(index, contents) {
  const party = (contents && contents.party) || {};
  const system = (contents && contents.system) || {};
  const ids = jsonExArray(party._actors);
  const characters = ids.map(id => {
    const a = actorsData[id] || {};
    return { name: a.characterName || '', index: a.characterIndex || 0 };
  });
  const faces = ids.map(id => {
    const a = actorsData[id] || {};
    return { name: a.faceName || '', index: a.faceIndex || 0 };
  });
  // MV 存的是帧数（_framesOnSave），读档时换算成秒
  const seconds = Number(system._playtime) || (Number(system._framesOnSave) || 0) / 60;
  return {
    globalId: index,
    title: gameTitle,
    characters: characters,
    faces: faces,
    playtime: playtimeText(seconds),
    timestamp: Date.now()
  };
}

const globalInfo = [];
const report = [];

for (let slot = 1; slot <= 20; slot++) {
  const candidates = [
    path.join(www, 'save', 'file' + slot + '.rpgsave'),
    path.join(www, 'save_extra', 'file' + slot + '.rpgsave')
  ];
  const file = candidates.find(f => fs.existsSync(f));
  if (!file) continue;
  const raw = fs.readFileSync(file, 'utf8').trim();
  if (!raw) { report.push('slot ' + slot + ': 空文件'); continue; }
  let json;
  try {
    json = LZString.decompressFromBase64(raw);
  } catch (e) {
    report.push('slot ' + slot + ': 解压异常 ' + e.message);
    continue;
  }
  if (!json) { report.push('slot ' + slot + ': 解压结果为空'); continue; }
  let contents;
  try {
    contents = JSON.parse(json);
  } catch (e) {
    report.push('slot ' + slot + ': JSON 解析失败 ' + e.message);
    continue;
  }
  globalInfo[slot - 1] = buildEntry(slot, contents);
  report.push('slot ' + slot + ': OK  队伍=' + ((contents.party && contents.party._actors) || []).length
    + '  时长=' + globalInfo[slot - 1].playtime
    + '  存档=' + path.basename(path.dirname(file)) + '/' + path.basename(file));
}

const filled = globalInfo.filter(Boolean).length;
if (filled === 0) {
  console.error('没有可用存档，未生成索引');
  report.forEach(r => console.error('  ' + r));
  process.exit(1);
}

const encoded = LZString.compressToBase64(JSON.stringify(globalInfo));
const outDir = path.join(www, 'save');
fs.mkdirSync(outDir, { recursive: true });
fs.writeFileSync(path.join(outDir, '__global.txt'), encoded, 'utf8');

// 自检：能解回来才算成功
const back = JSON.parse(LZString.decompressFromBase64(encoded));
if (!Array.isArray(back) || back.length !== globalInfo.length) {
  console.error('自检失败：压缩/解压不一致');
  process.exit(1);
}

report.forEach(r => console.log('  ' + r));
console.log('索引已生成: save/__global.txt  ' + encoded.length + ' 字节, ' + filled + ' 个存档槽');
