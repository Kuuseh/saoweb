// 局域网静态服务器：给手机/平板上的浏览器直接打开游戏用
// 用法：node devserver.js <游戏目录> [端口]
const http = require('http');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(process.argv[2] || '.');
const PORT = Number(process.argv[3] || 8123);

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.htm': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.webp': 'image/webp',
  '.svg': 'image/svg+xml',
  '.ogg': 'audio/ogg',
  '.m4a': 'audio/mp4',
  '.mp3': 'audio/mpeg',
  '.wav': 'audio/wav',
  '.mp4': 'video/mp4',
  '.webm': 'video/webm',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.wasm': 'application/wasm',
  '.txt': 'text/plain; charset=utf-8',
};

const server = http.createServer((req, res) => {
  let urlPath;
  try {
    urlPath = decodeURIComponent(req.url.split('?')[0]);
  } catch (e) {
    res.writeHead(400);
    return res.end('bad url');
  }
  if (urlPath === '/') urlPath = '/index.html';
  let file = path.join(ROOT, urlPath);
  if (!file.startsWith(ROOT)) {
    res.writeHead(403);
    return res.end('forbidden');
  }
  fs.stat(file, (err, st) => {
    if (!err && st.isDirectory()) {
      file = path.join(file, 'index.html');
      try { st = fs.statSync(file); } catch (e) { st = null; }
    }
    if (err || !st || !st.isFile()) {
      res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
      return res.end('404 ' + urlPath);
    }
    const type = MIME[path.extname(file).toLowerCase()] || 'application/octet-stream';
    const headers = {
      'Content-Type': type,
      'Accept-Ranges': 'bytes',
      'Cache-Control': 'no-cache',
    };

    // iOS Safari 的 <audio>/<video> 会发 Range 请求，必须支持，否则没声音/不能播视频
    const range = req.headers.range;
    if (range && /^bytes=\d*-\d*$/.test(range.trim())) {
      const [s, e] = range.replace('bytes=', '').split('-');
      let start = s === '' ? st.size - Number(e) : Number(s);
      let end = s !== '' && e !== '' ? Number(e) : st.size - 1;
      if (e === '' || Number(e) >= st.size) end = st.size - 1;
      if (start < 0) start = 0;
      if (start > end) {
        res.writeHead(416, { 'Content-Range': `bytes */${st.size}` });
        return res.end();
      }
      headers['Content-Range'] = `bytes ${start}-${end}/${st.size}`;
      headers['Content-Length'] = end - start + 1;
      res.writeHead(206, headers);
      if (req.method === 'HEAD') return res.end();
      fs.createReadStream(file, { start, end }).pipe(res);
      return;
    }

    headers['Content-Length'] = st.size;
    res.writeHead(200, headers);
    if (req.method === 'HEAD') return res.end();
    fs.createReadStream(file).pipe(res);
  });
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`serving ${ROOT} at http://0.0.0.0:${PORT}/`);
});
