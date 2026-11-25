/* 存档导入逻辑的单元测试（CI 里用 node 跑，不需要浏览器）
 *
 * 重要约束：run() 不允许自行写入/覆盖 RPG Global —— 索引由 App 的 Swift 侧
 * 用随包资源写入。历史上这里 fetch 过镜像里的旧索引，导致：
 *   1) 覆盖正确索引，CONTINUE 又空
 *   2) indexChanged 恒为 true → 页面反复 reload → 玩到一半被打回标题
 */
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

function makeEnv(files) {
  const store = {};
  global.localStorage = {
    getItem: k => (k in store ? store[k] : null),
    setItem: (k, v) => { store[k] = String(v); },
    removeItem: k => { delete store[k]; },
  };
  global.sessionStorage = {
    _d: {},
    getItem(k) { return k in this._d ? this._d[k] : null; },
    setItem(k, v) { this._d[k] = String(v); },
  };
  global.fetch = async function (url) {
    const key = String(url).replace(/^\//, '');
    if (key === '__savelist') {
      const names = Object.keys(files)
        .filter(k => k.endsWith('.rpgsave'))
        .map(k => k.replace('/', '|'));
      return { ok: true, status: 200, json: async () => names, text: async () => JSON.stringify(names) };
    }
    if (key in files) {
      return { ok: true, status: 200, text: async () => files[key] };
    }
    const dec = decodeURIComponent(key);
    if (dec in files) {
      return { ok: true, status: 200, text: async () => files[dec] };
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

  /* 场景 1：全新安装——存档文件写入，但不碰索引 */
  {
    const store = makeEnv({
      'save/__global.txt': 'SHOULD-NOT-BE-USED',
      'save/file1.rpgsave': 'SAVE1',
      'save/file3.rpgsave': 'SAVE3',
    });
    store['RPG Global'] = 'BUNDLED-INDEX';
    const report = JSON.parse(await mod.run());
    check('不覆盖索引（即使镜像里有 __global.txt）', () => {
      assert.strictEqual(store['RPG Global'], 'BUNDLED-INDEX');
      assert.strictEqual(report.indexChanged, false);
    });
    check('写入存档文件', () => {
      assert.strictEqual(store['RPG File1'], 'SAVE1');
      assert.strictEqual(store['RPG File3'], 'SAVE3');
      assert.strictEqual(report.imported, 2);
    });
  }

  /* 场景 2：已有存档不覆盖用户进度 */
  {
    const store = makeEnv({ 'save/file1.rpgsave': 'OLD' });
    store['RPG File1'] = 'USERPROGRESS-ABCDEFGH';
    const report = JSON.parse(await mod.run());
    check('已有存档不被覆盖', () => {
      assert.strictEqual(store['RPG File1'], 'USERPROGRESS-ABCDEFGH');
      assert.strictEqual(report.imported, 0);
      assert.strictEqual(report.skipped, 1);
    });
  }

  /* 场景 3：同会话第二次调用直接返回，不重复扫 */
  {
    makeEnv({ 'save/file1.rpgsave': 'X' });
    global.sessionStorage.setItem('sao_import_session', '1');
    const report = JSON.parse(await mod.run());
    check('同会话内跳过', () => {
      assert.strictEqual(report.skipped, -1);
      assert.strictEqual(report.imported, 0);
    });
    global.sessionStorage._d = {};
  }

  /* 场景 4：savelist 不可用时记录错误但不崩 */
  {
    const store = {};
    global.localStorage = {
      getItem: k => (k in store ? store[k] : null),
      setItem: (k, v) => { store[k] = String(v); },
      removeItem: k => { delete store[k]; },
    };
    global.sessionStorage = { _d: {}, getItem() { return null; }, setItem() {} };
    global.fetch = async () => { throw new Error('network down'); };
    const report = JSON.parse(await mod.run());
    check('网络异常时记录错误', () => {
      assert.ok(report.errors.length >= 1);
      assert.strictEqual(report.imported, 0);
    });
  }

  if (failures > 0) {
    console.log('RESULT: ' + failures + ' failure(s)');
    process.exit(1);
  }
  console.log('RESULT: all passed');
  process.exit(0);
})();
