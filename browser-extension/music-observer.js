"use strict";

// 仅在用户开启后请求读取；页面关闭后心跳自然停止。
let musicTimer;
function configureMusicObserver(enabled) {
  clearInterval(musicTimer);
  musicTimer = undefined;
  if (!enabled) return;
  const tick = () => chrome.runtime.sendMessage({ type: "music-heartbeat" }).catch(() => {});
  tick();
  musicTimer = setInterval(tick, 5000);
}
chrome.storage.local.get({ musicTrackingEnabled: false }).then(values => configureMusicObserver(values.musicTrackingEnabled));
chrome.storage.onChanged.addListener((changes, area) => {
  if (area === "local" && changes.musicTrackingEnabled) configureMusicObserver(changes.musicTrackingEnabled.newValue);
});
