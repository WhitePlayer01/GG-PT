"use strict";

let tab;
let snapshot;
const status = document.getElementById("status");
const buttons = Array.from(document.querySelectorAll("[data-action]"));

function setStatus(message, type) {
  status.textContent = message;
  status.className = "status" + (type ? " " + type : "");
}

function routing() {
  return {
    destination: document.getElementById("destination").value,
    tags: document.getElementById("tags").value.trim(),
    capturedAt: new Date().toISOString()
  };
}

function payload(values) {
  return Object.assign({
    source: snapshot.url,
    title: snapshot.title
  }, routing(), values);
}

async function openHandoff(values) {
  await chrome.runtime.sendMessage({ type: "open-handoff", payload: payload(values) });
  window.close();
}

async function addLink() {
  await chrome.runtime.sendMessage({
    type: "add-inbox",
    item: Object.assign({ url: snapshot.url, source: snapshot.url, title: snapshot.title, kind: "link" }, routing())
  });
  await refreshInbox();
  setStatus("已加入待收纳箱", "success");
}

async function refreshInbox() {
  const stored = await chrome.storage.local.get({ inbox: [] });
  document.getElementById("inbox-count").textContent = String(stored.inbox.length);
}

async function run(action) {
  if (!snapshot) return;
  buttons.forEach(function (button) { button.disabled = true; });
  setStatus("正在准备素材");
  try {
    if (action === "image") {
      if (!snapshot.images.length) throw new Error("当前页面没有可收集的大图");
      await openHandoff({ url: snapshot.images[0].url, kind: "image" });
    } else if (action === "images") {
      if (!snapshot.images.length) throw new Error("当前页面没有可收集的大图");
      const items = snapshot.images.slice(0, 30).map(function (image) {
        return { url: image.url, kind: "image", title: image.alt || snapshot.title, source: snapshot.url };
      });
      await openHandoff({ url: snapshot.url, kind: "batch", items: items });
    } else if (action === "markdown") {
      await openHandoff({ url: snapshot.url, kind: "markdown", content: snapshot.markdown });
    } else if (action === "pdf") {
      await chrome.scripting.executeScript({ target: { tabId: tab.id }, func: function () { window.print(); } });
      setStatus("已打开打印面板，请选择“存储为 PDF”", "success");
    } else if (action === "link") {
      await addLink();
    }
  } catch (error) {
    setStatus(error.message || "操作失败，请刷新网页后重试", "error");
  } finally {
    buttons.forEach(function (button) { button.disabled = false; });
  }
}

async function initialize() {
  [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab || !/^https?:/.test(tab.url || "")) throw new Error("此页面不支持网页收纳");
  const results = await chrome.scripting.executeScript({ target: { tabId: tab.id }, files: ["content-script.js"] });
  snapshot = results[0]?.result;
  if (!snapshot) throw new Error("未能读取当前网页");
  document.getElementById("page-title").textContent = snapshot.title;
  document.getElementById("page-domain").textContent = new URL(snapshot.url).hostname;
  document.getElementById("page-meta").textContent = snapshot.markdown.length.toLocaleString("zh-CN") + " 字正文";
  document.getElementById("image-count").textContent = snapshot.images.length ? "发现 " + snapshot.images.length + " 张可用图片，单次最多 30 张" : "没有发现可用大图";
  if (snapshot.images.length) {
    const hero = document.getElementById("hero-image");
    hero.src = snapshot.images[0].url;
    hero.hidden = false;
  }
  setStatus("选择一个动作开始收纳");
}

buttons.forEach(function (button) { button.addEventListener("click", function () { run(button.dataset.action); }); });
document.getElementById("open-inbox").addEventListener("click", function () { chrome.runtime.openOptionsPage(); });
refreshInbox();
initialize().catch(function (error) {
  setStatus(error.message, "error");
  buttons.forEach(function (button) { button.disabled = true; });
});

const musicToggle = document.getElementById("music-tracking");
chrome.storage.local.get({ musicTrackingEnabled: false }).then(values => {
  musicToggle.checked = values.musicTrackingEnabled;
});
musicToggle.addEventListener("change", async () => {
  await chrome.storage.local.set({ musicTrackingEnabled: musicToggle.checked });
  setStatus(musicToggle.checked ? "听歌记录已开启，请同时开启桌宠设置中的自动记录，并刷新音乐页面" : "网页听歌记录已关闭");
});
