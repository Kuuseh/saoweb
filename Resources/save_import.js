/* 存档导入 + 存档索引重建
 *
 * MV 浏览器模式的存档分两部分：
 *   1. RPG FileN        ← 单个存档（LZString 压缩的 JSON）
 *   2. RPG Global       ← 存档索引数组，CONTINUE 列表只认它
 *
 * 只写 1 不写 2，游戏里看不到任何存档。这里两件都做：
 *   - 把 www/save/*.rpgsave 读进 RPG FileN（已存在且能解析就跳过）
 *   - 按每个存档的真实内容重建 RPG Global 索引
 */
(function () {
  'use strict';

  var SAVE_SLOTS = 20;

  function safeDecompress(raw) {
    try {
      if (!window.LZString) return null;
      var json = window.LZString.decompressFromBase64(raw);
      if (!json) return null;
      return JSON.parse(json);
    } catch (e) {
      return null;
    }
  }

  function safeCompress(obj) {
    return window.LZString.compressToBase64(JSON.stringify(obj));
  }

  function playtimeText(playtime) {
    var t = Number(playtime) || 0;
    var hour = Math.floor(t / 3600);
    var min = Math.floor(t / 60) % 60;
    return hour + ':' + (min < 10 ? '0' : '') + min;
  }

  function keyFor(base) {
    var m = base.match(/^file(\d+)$/i);
    if (m) return 'RPG File' + m[1];
    if (/^global$/i.test(base)) return 'RPG Global';
    if (/^config$/i.test(base)) return 'RPG Config';
    return 'RPG ' + base;
  }

  /* 把一份存档内容转换成 MV 的索引项（对应 DataManager.makeSavefileInfo） */
  function buildEntry(index, contents, actors, gameTitle) {
    var party = contents && contents.party ? contents.party : {};
    var system = contents && contents.system ? contents.system : {};
    var ids = Array.isArray(party._actors) ? party._actors : [];
    var characters = [];
    var faces = [];
    for (var i = 0; i < ids.length; i++) {
      var actor = (actors && actors[ids[i]]) || {};
      characters.push({ name: actor.characterName || '', index: actor.characterIndex || 0 });
      faces.push({ name: actor.faceName || '', index: actor.faceIndex || 0 });
    }
    return {
      globalId: index,
      title: gameTitle || '',
      characters: characters,
      faces: faces,
      playtime: playtimeText(system._playtime || 0),
      timestamp: Date.now()
    };
  }

  async function fetchJSON(path) {
    try {
      var r = await fetch(path);
      if (!r.ok) return null;
      return await r.json();
    } catch (e) {
      return null;
    }
  }

  async function run() {
    var report = { imported: 0, repaired: 0, indexed: 0, skipped: 0, globalChanged: false, errors: [] };
    var globalBefore = localStorage.getItem('RPG Global') || '';

    var meta = await Promise.all([fetchJSON('data/System.json'), fetchJSON('data/Actors.json')]);
    var systemData = meta[0] || {};
    var actorsData = meta[1] || [];
    var gameTitle = systemData.gameTitle || '';

    var list = [];
    try {
      var res = await fetch('/__savelist');
      if (res.ok) list = await res.json();
    } catch (e) {
      report.errors.push('savelist: ' + e.message);
    }

    /* 1. 把文件写进 localStorage：键不存在、或已有值解析不了，才写入 */
    for (var i = 0; i < list.length; i++) {
      var seg = list[i].split('|');
      var dir = seg[0];
      var name = seg[1];
      if (!name) continue;
      var base = name.replace(/\.rpgsave$/i, '');
      var key = keyFor(base);
      var existing = localStorage.getItem(key);
      if (existing !== null && safeDecompress(existing) !== null) {
        report.skipped++;
        continue;
      }
      try {
        var fr = await fetch('/' + dir + '/' + encodeURIComponent(name));
        if (!fr.ok) { report.errors.push('404 ' + name); continue; }
        var txt = await fr.text();
        if (!txt) { report.errors.push('empty ' + name); continue; }
        localStorage.setItem(key, txt);
        localStorage.setItem('RPG ' + base, txt);
        if (existing !== null) report.repaired++; else report.imported++;
      } catch (e) {
        report.errors.push(name + ': ' + e.message);
      }
    }

    /* 2. 重建存档索引 */
    var globalInfo = [];
    var current = localStorage.getItem('RPG Global');
    if (current) {
      var parsed = safeDecompress(current);
      if (Array.isArray(parsed)) globalInfo = parsed;
    }

    var indexed = 0;
    for (var slot = 1; slot <= SAVE_SLOTS; slot++) {
      var raw = localStorage.getItem('RPG File' + slot);
      if (!raw) continue;
      var contents = safeDecompress(raw);
      if (!contents) { report.errors.push('slot ' + slot + ': bad data'); continue; }
      globalInfo[slot - 1] = buildEntry(slot, contents, actorsData, gameTitle);
      indexed++;
    }
    report.indexed = indexed;

    if (indexed > 0) {
      var encoded = safeCompress(globalInfo);
      localStorage.setItem('RPG Global', encoded);
      var verify = safeDecompress(localStorage.getItem('RPG Global'));
      report.globalOk = Array.isArray(verify) && verify.length > 0;
      report.globalChanged = encoded !== globalBefore;
    } else {
      report.globalOk = false;
    }

    return JSON.stringify(report);
  }

  if (typeof window !== 'undefined') {
    window.__saoImportRun = run;
  }
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = { buildEntry: buildEntry, playtimeText: playtimeText, keyFor: keyFor };
  }
})();
