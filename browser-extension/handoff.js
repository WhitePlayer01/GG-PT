"use strict";

// 从扩展中转页地址读取素材 URL、类型和页面标题。
const query = new URLSearchParams(window.location.search);
// 使用 URL API 构建自定义协议，避免手工字符串拼接遗漏转义。
const deepLink = new URL("erye://collect");
["url", "kind", "title"].forEach(function (name) {
  const value = query.get(name);
  if (value) deepLink.searchParams.set(name, value);
});

// 保留一个可重复点击的入口，以应对浏览器首次拦截外部协议。
const openApp = document.getElementById("open-app");
openApp.href = deepLink.toString();
// 用户确认投递后可以手动关闭中转标签页。
document.getElementById("close-tab").addEventListener("click", function () { window.close(); });
// 页面加载后立即尝试唤起桌面 App。
window.location.href = deepLink.toString();
