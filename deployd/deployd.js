'use strict';
// deployd — VPS 自動部署引擎。GitHub push webhook → git pull + build + systemctl restart。
// 零依賴純 node。設定 registry.json(repo full_name → {dir,service,branch,build})。
// env: PORT(4099)、DEPLOY_SECRET(GitHub webhook HMAC 密鑰)。
const http = require('http');
const crypto = require('crypto');
const { execFile } = require('child_process');
const fs = require('fs');
const path = require('path');

const PORT = parseInt(process.env.PORT || '4099', 10);
const SECRET = process.env.DEPLOY_SECRET || '';
const REG = path.join(__dirname, 'registry.json');

function loadRegistry() {
  try { return JSON.parse(fs.readFileSync(REG, 'utf8')); } catch { return {}; }
}
function run(cmd, args, cwd) {
  return new Promise((resolve) => {
    execFile(cmd, args, { cwd, timeout: 600000, maxBuffer: 8 * 1024 * 1024 }, (err, so, se) => {
      resolve({ code: err ? (err.code || 1) : 0, out: ((so || '') + (se || '')).trim() });
    });
  });
}
async function deploy(cfg, log) {
  let r = await run('git', ['-C', cfg.dir, 'pull', '--ff-only']);
  log('git pull: ' + r.out.split('\n').pop());
  if (r.code !== 0) { log('PULL FAIL — abort'); return false; }
  if (cfg.build) {
    log('build: ' + cfg.build);
    r = await run('bash', ['-lc', cfg.build], cfg.dir);
    log('build ' + (r.code === 0 ? 'ok' : 'FAIL') + ': ' + r.out.slice(-300));
    if (r.code !== 0) { log('BUILD FAIL — 不重啟(保住舊版)'); return false; }
  }
  r = await run('systemctl', ['restart', cfg.service]);
  log('restart ' + cfg.service + ': ' + (r.code === 0 ? 'OK' : 'FAIL ' + r.out));
  return r.code === 0;
}
const server = http.createServer((req, res) => {
  if (req.method === 'GET' && req.url === '/health') { res.writeHead(200); return res.end('deployd ok'); }
  if (req.method !== 'POST' || req.url !== '/hook') { res.writeHead(404); return res.end('nope'); }
  const chunks = [];
  req.on('data', (c) => chunks.push(c));
  req.on('end', () => {
    const buf = Buffer.concat(chunks);
    const sig = req.headers['x-hub-signature-256'] || '';
    const expected = 'sha256=' + crypto.createHmac('sha256', SECRET).update(buf).digest('hex');
    const ok = sig.length === expected.length && crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(expected));
    if (!SECRET || !ok) { res.writeHead(401); return res.end('bad signature'); }
    let payload;
    try { payload = JSON.parse(buf.toString('utf8')); } catch { res.writeHead(400); return res.end('bad json'); }
    if (payload.zen) { res.writeHead(200); return res.end('ping ok'); }
    const repo = payload.repository && payload.repository.full_name;
    const cfg = loadRegistry()[repo];
    if (!cfg) { res.writeHead(200); return res.end('no config: ' + repo); }
    if (cfg.branch && (payload.ref || '') !== 'refs/heads/' + cfg.branch) { res.writeHead(200); return res.end('skip branch'); }
    res.writeHead(202); res.end('deploying ' + repo);
    const log = (m) => console.log('[' + new Date().toISOString() + '] [' + repo + '] ' + m);
    log('=== deploy start ===');
    deploy(cfg, log).then((o) => log('=== deploy ' + (o ? 'DONE' : 'FAILED') + ' ===')).catch((e) => log('ERROR ' + e.message));
  });
});
server.listen(PORT, () => console.log('deployd listening on :' + PORT));
