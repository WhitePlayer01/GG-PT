"use strict";

// 从扩展中转页地址读取素材 URL、类型和页面标题。
const query = new URLSearchParams(window.location.search);
const retryImage = query.get("kind") === "retry-image";
// 内嵌图片不放进外部协议；未运行时只唤起 App，再由用户重试一次。
const deepLink = new URL(retryImage ? "erye://open" : "erye://collect");
["url", "source", "kind", "title", "pageTitle", "capturedAt", "tags", "destination", "content", "items", "mimeType"].forEach(function (name) {
  const value = query.get(name);
  if (value) deepLink.searchParams.set(name, value);
});

if (retryImage) {
  document.querySelector("h1").textContent = "正在唤醒云长卫";
  document.getElementById("status").textContent = "App 启动后，请回到原网页再点击一次“一键归纳图片到本地”。";
}

// 保留一个可重复点击的入口，以应对浏览器首次拦截外部协议。
const openApp = document.getElementById("open-app");
openApp.href = deepLink.toString();
// 用户确认投递后可以手动关闭中转标签页。
document.getElementById("close-tab").addEventListener("click", function () { window.close(); });
// 页面加载后立即尝试唤起桌面 App。
window.location.href = deepLink.toString();
