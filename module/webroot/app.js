let exec = null;
let toastNative = (msg) => console.log(msg);

const MOD = '/data/adb/modules/Process_Kill';
const CONFIG = `${MOD}/配置文件.txt`;
const LIST = `${MOD}/黑白名单.txt`;
const LOG = `${MOD}/日志.log`;
const STATS = `${MOD}/压制统计.txt`;

let statusTimer = null;
let logTimer = null;
let toastTimer = null;

function initKsu() {
  if (typeof window !== 'undefined' && typeof window.ksu !== 'undefined' && window.ksu.exec) {
    exec = (cmd) =>
      new Promise((resolve, reject) => {
        const cb = 'cb_' + Date.now() + '_' + Math.floor(Math.random() * 9999);
        window[cb] = (errno, stdout, stderr) => {
          resolve({ errno, stdout, stderr });
          delete window[cb];
        };
        try {
          window.ksu.exec(cmd, "{}", cb);
        } catch (e) {
          delete window[cb];
          reject(e);
        }
      });

    toastNative = (msg) => {
      try {
        window.ksu.toast(msg);
      } catch (_) {}
    };
  } else {
    exec = async () => ({ errno: 1, stdout: '', stderr: 'ksu bridge unavailable' });
  }
}

function toast(msg) {
  const el = document.getElementById('toast');
  if (!el) return;

  el.textContent = msg;
  el.classList.add('show');
  toastNative(msg);

  if (toastTimer) clearTimeout(toastTimer);
  toastTimer = setTimeout(() => {
    el.classList.remove('show');
  }, 1800);
}

async function sh(cmd) {
  return await exec(cmd);
}

async function shOut(cmd) {
  const { stdout } = await sh(cmd);
  return stdout || '';
}

function setMemRing(percent) {
  const p = Math.max(0, Math.min(100, Number(percent) || 0));
  const circle = document.getElementById('memRing');
  const label = document.getElementById('memPercent');
  if (!circle || !label) return;

  const radius = 46;
  const circumference = 2 * Math.PI * radius;
  const offset = circumference * (1 - p / 100);

  circle.style.strokeDasharray = `${circumference}`;
  circle.style.strokeDashoffset = `${offset}`;
  label.textContent = `${p}%`;
}

function setRunStatus(running) {
  const dot = document.getElementById('runDot');
  const text = document.getElementById('runText');
  if (!dot || !text) return;

  if (running) {
    dot.className = 'dot ok';
    text.textContent = '运行中';
  } else {
    dot.className = 'dot fail';
    text.textContent = '未运行';
  }
}

function isNearBottom(el, threshold = 48) {
  return (el.scrollHeight - el.scrollTop - el.clientHeight) < threshold;
}

async function readFile(path) {
  const { errno, stdout } = await sh(`cat '${path}' 2>/dev/null`);
  return errno === 0 ? stdout : '';
}

async function writeFile(path, content) {
  const { errno, stderr } = await sh(`cat > '${path}' <<'EOF'
${content}
EOF
chmod 0644 '${path}'`);
  if (errno !== 0) throw new Error(stderr || 'write failed');
}

async function clearFile(path) {
  const { errno, stderr } = await sh(`: > '${path}'`);
  if (errno !== 0) throw new Error(stderr || 'clear failed');
}

function parseConfigText(text) {
  const out = {};
  const lines = String(text || '').split('\n');
  for (const raw of lines) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    const idx = line.indexOf('=');
    if (idx <= 0) continue;
    const k = line.slice(0, idx).trim();
    const v = line.slice(idx + 1).trim();
    out[k] = v;
  }
  return out;
}

async function loadStatus() {
  const runningText = await shOut(
    `ps -A 2>/dev/null | grep processkill | grep -v grep >/dev/null && echo 1 || echo 0`
  );
  const running = String(runningText).trim() === '1';
  setRunStatus(running);

  const cfgText = await readFile(CONFIG);
  const cfg = parseConfigText(cfgText);
  const poll = String(cfg.poll_interval || '-').trim();
  const pollEl = document.getElementById('pollInterval');
  if (pollEl) pollEl.textContent = poll;

  const total = await shOut(`cat '${STATS}' 2>/dev/null || echo 0`);
  const totalEl = document.getElementById('totalKill');
  if (totalEl) totalEl.textContent = String(total).trim() || '0';

  const mem = await shOut(`
MT=$(awk '/MemTotal:/ {print $2}' /proc/meminfo)
MA=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)
if [ -n "$MT" ] && [ -n "$MA" ] && [ "$MT" -gt 0 ]; then
  echo $(( (MT - MA) * 100 / MT ))
else
  echo 0
fi
`);
  setMemRing(parseInt(String(mem).trim() || '0', 10));
}

async function loadConfig() {
  const box = document.getElementById('configBox');
  if (!box) return;
  box.value = await readFile(CONFIG);
}

async function loadList() {
  const box = document.getElementById('listBox');
  if (!box) return;
  box.value = await readFile(LIST);
}

async function loadLog(auto = false) {
  const linesEl = document.getElementById('logLines');
  const box = document.getElementById('logBox');
  if (!box) return;

  const lines = parseInt((linesEl && linesEl.value) || '200', 10);
  const shouldStickBottom = isNearBottom(box);
  const text = await shOut(`tail -n ${isNaN(lines) ? 200 : lines} '${LOG}' 2>/dev/null`);

  box.textContent = text || '';
  if (!auto || shouldStickBottom) {
    box.scrollTop = box.scrollHeight;
  }
}

async function saveConfig() {
  try {
    const box = document.getElementById('configBox');
    const content = (box && box.value) || '';
    await writeFile(CONFIG, content);
    toast('配置已保存');
    await loadStatus();
  } catch (e) {
    console.error(e);
    toast('保存配置失败');
  }
}

async function saveList() {
  try {
    const box = document.getElementById('listBox');
    const content = (box && box.value) || '';
    await writeFile(LIST, content);
    toast('黑白名单已保存');
  } catch (e) {
    console.error(e);
    toast('保存名单失败');
  }
}

async function clearLogAction() {
  try {
    await clearFile(LOG);
    const box = document.getElementById('logBox');
    if (box) box.textContent = '';
    toast('日志已清空');
  } catch (e) {
    console.error(e);
    toast('清空日志失败');
  }
}

async function refreshAll() {
  try {
    await Promise.all([
      loadStatus(),
      loadConfig(),
      loadList(),
      loadLog(false)
    ]);
  } catch (e) {
    console.error(e);
    toast('刷新失败');
  }
}

function startAutoRefresh() {
  stopAutoRefresh();

  statusTimer = setInterval(() => {
    loadStatus().catch(console.error);
  }, 5000);

  logTimer = setInterval(() => {
    loadLog(true).catch(console.error);
  }, 3000);
}

function stopAutoRefresh() {
  if (statusTimer) {
    clearInterval(statusTimer);
    statusTimer = null;
  }
  if (logTimer) {
    clearInterval(logTimer);
    logTimer = null;
  }
}

function bindEvents() {
  const byId = (id) => document.getElementById(id);

  const refreshBtn = byId('refreshAllBtn');
  const saveConfigBtn = byId('saveConfigBtn');
  const saveListBtn = byId('saveListBtn');
  const reloadLogBtn = byId('reloadLogBtn');
  const clearLogBtn = byId('clearLogBtn');

  if (refreshBtn) refreshBtn.addEventListener('click', refreshAll);
  if (saveConfigBtn) saveConfigBtn.addEventListener('click', saveConfig);
  if (saveListBtn) saveListBtn.addEventListener('click', saveList);
  if (reloadLogBtn) reloadLogBtn.addEventListener('click', () => loadLog(false));
  if (clearLogBtn) clearLogBtn.addEventListener('click', clearLogAction);

  document.addEventListener('visibilitychange', () => {
    if (document.hidden) {
      stopAutoRefresh();
    } else {
      loadStatus().catch(console.error);
      loadLog(true).catch(console.error);
      startAutoRefresh();
    }
  });

  window.addEventListener('beforeunload', () => {
    stopAutoRefresh();
    if (toastTimer) {
      clearTimeout(toastTimer);
      toastTimer = null;
    }
  });
}

async function init() {
  initKsu();
  bindEvents();
  await refreshAll();
  startAutoRefresh();
}

init().catch((e) => {
  console.error(e);
  toast('初始化失败');
});
