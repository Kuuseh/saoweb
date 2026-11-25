/* 存档导入 + 存档索引
 *
 * MV 浏览器模式的存档分两部分：
 *   RPG FileN   ← 单个存档（LZString 压缩）
 *   RPG Global  ← 存档索引数组，CONTINUE 列表只认它
 *
 * 索引由 PC 上的 tools/build_global.js 预先生成（save/__global.txt），
 * App 只负责把它和存档文件写进 localStorage —— 不依赖页面里的 LZString，
 * 避免注入时机早于游戏脚本时静默失败。
 */
(function () {
  'use strict';

  function keyFor(base) {
    var m = base.match(/^file(\d+)$/i);
    if (m) return 'RPG File' + m[1];
    if (/^global$/i.test(base)) return 'RPG Global';
    if (/^config$/i.test(base)) return 'RPG Config';
    return 'RPG ' + base;
  }

  async function run() {
    var report = {
      imported: 0, skipped: 0, indexed: false, indexChanged: false,
      indexBytes: 0, errors: []
    };

    /* 1. 预生成的索引：直接写入（这是 CONTINUE 列表的关键） */
    try {
      var r = await fetch('/save/__global.txt');
      if (r.ok) {
        var text = (await r.text()).trim();
        if (text) {
          report.indexBytes = text.length;
          if (localStorage.getItem('RPG Global') !== text) {
            localStorage.setItem('RPG Global', text);
            report.indexChanged = true;
          }
          report.indexed = true;
        }
      } else {
        report.errors.push('__global.txt: HTTP ' + r.status);
      }
    } catch (e) {
      report.errors.push('__global.txt: ' + e.message);
    }

    /* 2. 存档文件本体 */
    var list = [];
    try {
      var res = await fetch('/__savelist');
      if (res.ok) list = await res.json();
    } catch (e) {
      report.errors.push('savelist: ' + e.message);
    }

    for (var i = 0; i < list.length; i++) {
      var seg = list[i].split('|');
      var dir = seg[0];
      var name = seg[1];
      if (!name) continue;
      if (/^__/.test(name)) continue;          // 跳过我们自己生成的辅助文件
      var base = name.replace(/\.rpgsave$/i, '');
      var key = keyFor(base);
      var existing = localStorage.getItem(key);
      if (existing !== null && existing.length > 16) {
        report.skipped++;
        continue;
      }
      try {
        var fr = await fetch('/' + dir + '/' + encodeURIComponent(name));
        if (!fr.ok) { report.errors.push('HTTP ' + fr.status + ' ' + name); continue; }
        var txt = await fr.text();
        if (!txt) { report.errors.push('empty ' + name); continue; }
        localStorage.setItem(key, txt);
        localStorage.setItem('RPG ' + base, txt);
        report.imported++;
      } catch (e) {
        report.errors.push(name + ': ' + e.message);
      }
    }

    return JSON.stringify(report);
  }

  if (typeof window !== 'undefined') {
    window.__saoImportRun = run;
  }
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = { run: run, keyFor: keyFor };
  }
})();
