const { readFileSync } = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const listeners = [];
let enabled = true;
let injected = 0;
const sent = [];
const fixture = { metadata: { title: '测试歌名', artist: '测试歌手', album: '测试专辑' }, playbackState: 'playing' };
const context = {
  URL, Set, AbortSignal,
  navigator: { mediaSession: fixture },
  document: { querySelectorAll: () => [] },
  chrome: {
    runtime: { onInstalled: { addListener() {} }, onStartup: { addListener() {} }, onMessage: { addListener(fn) { listeners.push(fn); } } },
    contextMenus: { onClicked: { addListener() {} } },
    storage: { local: { async get() { return { musicTrackingEnabled: enabled }; } } },
    scripting: { async executeScript(options) { injected++; return [{ result: options.func() }]; } }
  },
  async fetch(url, options) { sent.push({ url, body: JSON.parse(options.body) }); return { ok: true }; }
};
vm.runInNewContext(readFileSync(__dirname + '/service-worker.js', 'utf8'), context);
const receive = listeners.at(-1);
async function tick(url = 'https://music.163.com/', frameId = 0) {
  const result = receive({ type: 'music-heartbeat' }, { url, frameId, tab: { id: 7 } }, () => {});
  await new Promise(resolve => setImmediate(resolve));
  return result;
}
(async () => {
  await tick();
  assert.equal(sent.length, 1);
  assert.equal(sent[0].body.title, '测试歌名');
  assert.equal(sent[0].body.host, 'music.163.com');
  assert.equal(sent[0].body.playing, 'true');
  fixture.playbackState = 'paused';
  await tick();
  assert.equal(sent[1].body.playing, 'false');
  fixture.metadata = null;
  await tick();
  assert.equal(sent.length, 2);
  enabled = false;
  const before = injected;
  await tick();
  assert.equal(injected, before);
  enabled = true;
  await tick('https://example.com/');
  await tick('https://music.163.com/', 1);
  assert.equal(injected, before);
  console.log('通过：网页歌曲读取、暂停、缺失信息、关闭开关、非音乐站点和子框架过滤');
})().catch(error => { console.error(error); process.exitCode = 1; });
