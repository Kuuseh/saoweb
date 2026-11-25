/* 存档导入逻辑的单元测试（CI 里用 node 跑，不需要浏览器） */
const assert = require('assert');
const path = require('path');

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

/* 轻量的 localStorage / fetch 桩 */
function makeEnv(files) {
  const store = {};
  global.localStorage = {
    getItem: k => (k in store ? store[k] : null),
    setItem: (k, v) => { store[k] = String(v); },
    removeItem: k => { delete store[k]; },
  };
  global.fetch = async function (url) {
    const key = url.replace(/^\//, '');
    if (key === '__savelist') {
      return { ok: true, json: async () => Object.keys(files).filter(k => k.endsWith('.rpgsave')).map(k => k.replace('/', '|')), status: 200 };
    }
    if (key in files) {
      return { ok: true, text: async () => files[key], status: 200, json: async () => JSON.parse(files[key]) };
    }
    const name = decodeURIComponent(key);
    if (name in files) {
      return { ok: true, text: async () => files[name], status: 200 };
    }
    return { ok: false, status: 404, text: async () => '' };
  };
  return store;
}

(async function main() {
  const mod = require(path.join(__dirname, '..', 'Resources', 'save_import.js'));
  const { keyFor } = mod;

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

  /* 场景 1：全新安装——索引与存档都写入 */
  {
    const store = makeEnv({
      'save/__global.txt': 'GLOBALINDEX',
      'save/file1.rpgsave': 'SAVE1',
      'save/file3.rpgsave': 'SAVE3',
      '__savelist': '',
    });
    const report = JSON.parse(await mod.run());
    check('全新安装：写入索引', () => {
      assert.strictEqual(store['RPG Global'], 'GLOBALINDEX');
      assert.strictEqual(report.indexed, true);
      assert.strictEqual(report.indexChanged, true);
    });
    check('全新安装：写入存档', () => {
      assert.strictEqual(store['RPG File1'], 'SAVE1');
      assert.strictEqual(store['RPG File3'], 'SAVE3');
      assert.strictEqual(report.imported, 2);
    });
  }

  /* 场景 2：索引已在且一致——不重复写 */
  {
    const store = makeEnv({
      'save/__global.txt': 'GLOBALINDEX',
      '__savelist': '',
    });
    store['RPG Global'] = 'GLOBALINDEX';
    const report = JSON.parse(await mod.run());
    check('索引未变化时不标记 changed', () => {
      assert.strictEqual(report.indexChanged, false);
      assert.strictEqual(report.indexed, true);
    });
  }

  /* 场景 3：已有存档不覆盖用户进度 */
  {
    const store = makeEnv({
      'save/__global.txt': 'G2',
      'save/file1.rpgsave': 'OLD',
      '__savelist': '',
    });
    store['RPG File1'] = 'USERPROGRESS-ABCDEFGH';
    const report = JSON.parse(await mod.run());
    check('已有存档不被覆盖', () => {
      assert.strictEqual(store['RPG File1'], 'USERPROGRESS-ABCDEFGH');
      assert.strictEqual(report.imported, 0);
      assert.strictEqual(report.skipped, 1);
    });
  }

  /* 场景 4：索引文件 404——不崩，记错误 */
  {
    makeEnv({ '__savelist': '' });
    const report = JSON.parse(await mod.run());
    check('索引缺失时记录错误', () => {
      assert.strictEqual(report.indexed, false);
      assert.ok(report.errors.some(e => e.indexOf('__global.txt') >= 0));
    });
  }

  if (failures > 0) {
    console.log('RESULT: ' + failures + ' failure(s)');
    process.exit(1);
  }
  console.log('RESULT: all passed');
  process.exit(0);
})();
