"use strict";

// 定义扩展安装后注册到不同右键场景的菜单项。
const menuItems = [
  { id: "erye-page", title: "当前页面交给二爷", contexts: ["page"] },
  { id: "erye-link", title: "当前链接加入待收纳箱", contexts: ["link"] },
  { id: "erye-image", title: "一键归纳图片到本地", contexts: ["image"] },
  { id: "erye-media", title: "下载音视频并自动分类", contexts: ["audio", "video"] }
];

/**
 * 清理旧菜单并注册当前版本的全部右键入口。
 * 重新安装或升级扩展时调用，避免重复菜单残留。
 */
chrome.runtime.onInstalled.addListener(function () {
  chrome.contextMenus.removeAll(function () {
    menuItems.forEach(function (item) { chrome.contextMenus.create(item); });
  });
  syncBadge();
});

/**
 * 把用户右键点击的页面、链接或媒体地址转换为投递参数，
 * 再打开中转页触发 macOS 的 erye:// 自定义协议。
 */
chrome.contextMenus.onClicked.addListener(async function (info, tab) {
  // 页面地址是所有场景的安全回退值。
  let target = info.pageUrl || "";
  let kind = "page";

  // 为不同上下文选择真正需要收藏或下载的 URL。
  if (info.menuItemId === "erye-link") {
    addToInbox({
      url: info.linkUrl || target,
      source: info.pageUrl || target,
      title: (tab && tab.title) || "网页链接",
      kind: "link"
    });
    return;
  } else if (info.menuItemId === "erye-image") {
    target = info.srcUrl || target;
    kind = "image";
  } else if (info.menuItemId === "erye-media") {
    target = info.srcUrl || target;
    kind = "media";
  }

  const payload = {
    url: target,
    source: info.pageUrl || target,
    kind: kind,
    title: kind === "image" ? imageTitle(target, tab) : ((tab && tab.title) || "网页收藏"),
    pageTitle: (tab && tab.title) || "",
    capturedAt: new Date().toISOString()
  };

  // 优先由浏览器读取图片字节，兼容需要会话、data: 和 blob: 的网页图片。
  if (kind === "image") {
    const captured = await captureImage(target, tab && tab.id);
    if (captured) {
      payload.kind = "image-data";
      payload.content = captured.dataURL;
      payload.mimeType = captured.mimeType;
      if (!/^https?:/i.test(target)) payload.url = "";
    }
  }
  await deliver(payload);
});

/**
 * 优先用图片 URL 中的文件名作为收纳名称，无法解析时再回退到页面标题。
 */
function imageTitle(target, tab) {
  try {
    const parsed = new URL(target);
    if (!/^https?:$/.test(parsed.protocol)) return (tab && tab.title) || "网页图片";
    const name = decodeURIComponent(parsed.pathname.split("/").pop() || "").trim();
    if (name) return name;
  } catch (_) {}
  return (tab && tab.title) || "网页图片";
}

/** 使用扩展的网页权限读取图片，失败时回退到页面上下文。 */
async function captureImage(target, tabId) {
  const direct = await readImageAsDataURL(target);
  if (direct) return direct;
  if (!tabId) return null;
  try {
    const results = await chrome.scripting.executeScript({
      target: { tabId: tabId },
      world: "MAIN",
      args: [target],
      func: async function (source) {
        const image = Array.from(document.images).find(function (item) {
          return item.currentSrc === source || item.src === source;
        });
        const candidates = [
          image && image.currentSrc,
          image && image.src,
          image && image.dataset && image.dataset.src,
          image && image.dataset && image.dataset.original,
          image && image.dataset && image.dataset.iurl,
          source
        ].filter(Boolean);
        for (const candidate of Array.from(new Set(candidates))) {
          try {
            const response = await fetch(candidate, { credentials: "include" });
            if (!response.ok) continue;
            const blob = await response.blob();
            if (!blob.type.startsWith("image/") || blob.size > 18 * 1024 * 1024) continue;
            const bytes = new Uint8Array(await blob.arrayBuffer());
            let binary = "";
            for (let offset = 0; offset < bytes.length; offset += 32768) {
              binary += String.fromCharCode.apply(null, bytes.subarray(offset, offset + 32768));
            }
            return { dataURL: "data:" + blob.type + ";base64," + btoa(binary), mimeType: blob.type };
          } catch (_) {}
        }
        return null;
      }
    });
    return (results[0] && results[0].result) || null;
  } catch (_) {
    return null;
  }
}

/** 将最多 18 MB 的图片转换为可交给本地 App 的 Data URL。 */
async function readImageAsDataURL(target) {
  try {
    const response = await fetch(target, { credentials: "include", cache: "force-cache" });
    if (!response.ok) return null;
    const blob = await response.blob();
    if (!blob.type.startsWith("image/") || blob.size > 18 * 1024 * 1024) return null;
    const bytes = new Uint8Array(await blob.arrayBuffer());
    let binary = "";
    for (let offset = 0; offset < bytes.length; offset += 32768) {
      binary += String.fromCharCode.apply(null, bytes.subarray(offset, offset + 32768));
    }
    return { dataURL: "data:" + blob.type + ";base64," + btoa(binary), mimeType: blob.type };
  } catch (_) {
    return null;
  }
}

/**
 * App 已运行时通过本机回环通道直接收纳；连接不上时才打开唤起页。
 */
async function deliver(payload) {
  try {
    const response = await fetch("http://127.0.0.1:48726/collect", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Yunchangwei-Request": "browser-extension-v1"
      },
      body: JSON.stringify(payload)
    });
    const result = await response.json();
    showCollectionResult(result);
    return result;
  } catch (_) {
    const fallback = payload.kind === "image-data"
      ? { kind: "retry-image", source: payload.source, title: payload.title, pageTitle: payload.pageTitle }
      : payload;
    await openHandoff(fallback);
    return { success: false, message: "正在唤起云长卫" };
  }
}

/** 用系统通知和扩展徽标同时呈现收纳结果。 */
function showCollectionResult(result) {
  const succeeded = Boolean(result && result.success);
  try {
    chrome.notifications.create({
      type: "basic",
      iconUrl: chrome.runtime.getURL("icons/icon-128.png"),
      title: succeeded ? "收纳成功" : "收纳失败",
      message: (result && result.message) || (succeeded ? "图片已归纳到本地" : "请稍后重试"),
      priority: succeeded ? 0 : 2
    }, function () {
      // 读取 lastError 可防止系统关闭通知权限时出现未处理异常。
      void chrome.runtime.lastError;
    });
  } catch (_) {
    // 通知不可用时仍保留徽标和桌宠气泡反馈。
  }
  chrome.action.setBadgeBackgroundColor({ color: succeeded ? "#2E6A4F" : "#B84335" });
  chrome.action.setBadgeText({ text: succeeded ? "✓" : "!" });
  setTimeout(syncBadge, 4500);
}

function openHandoff(payload) {
  const params = new URLSearchParams();
  Object.entries(payload).forEach(function ([key, value]) {
    if (value !== undefined && value !== null && value !== "") {
      params.set(key, typeof value === "string" ? value : JSON.stringify(value));
    }
  });
  return chrome.tabs.create({ url: chrome.runtime.getURL("handoff.html") + "?" + params.toString() });
}

async function addToInbox(item) {
  const stored = await chrome.storage.local.get({ inbox: [] });
  const normalized = Object.assign({ id: crypto.randomUUID(), capturedAt: new Date().toISOString() }, item);
  const inbox = [normalized].concat(stored.inbox.filter(function (old) { return old.url !== normalized.url; })).slice(0, 200);
  await chrome.storage.local.set({ inbox: inbox });
  await chrome.action.setBadgeBackgroundColor({ color: "#B84335" });
  await chrome.action.setBadgeText({ text: inbox.length > 99 ? "99+" : String(inbox.length) });
}

async function syncBadge() {
  const stored = await chrome.storage.local.get({ inbox: [] });
  await chrome.action.setBadgeBackgroundColor({ color: "#B84335" });
  await chrome.action.setBadgeText({ text: stored.inbox.length ? String(Math.min(stored.inbox.length, 99)) : "" });
}

chrome.runtime.onStartup.addListener(syncBadge);

chrome.runtime.onMessage.addListener(function (message, sender, sendResponse) {
  if (message.type === "open-handoff") {
    deliver(message.payload).then(function (result) { sendResponse({ ok: true, result: result }); });
    return true;
  }
  if (message.type === "add-inbox") {
    addToInbox(message.item).then(function () { sendResponse({ ok: true }); });
    return true;
  }
  if (message.type === "sync-badge") {
    syncBadge().then(function () { sendResponse({ ok: true }); });
    return true;
  }
});
