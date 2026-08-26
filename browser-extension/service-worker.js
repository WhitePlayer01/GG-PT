"use strict";

// 定义扩展安装后注册到不同右键场景的菜单项。
const menuItems = [
  { id: "erye-page", title: "当前网页交给二爷", contexts: ["page"] },
  { id: "erye-link", title: "这个链接交给二爷", contexts: ["link"] },
  { id: "erye-image", title: "这张图片交给二爷", contexts: ["image"] },
  { id: "erye-media", title: "这段音视频交给二爷", contexts: ["audio", "video"] }
];

/**
 * 清理旧菜单并注册当前版本的全部右键入口。
 * 重新安装或升级扩展时调用，避免重复菜单残留。
 */
chrome.runtime.onInstalled.addListener(function () {
  chrome.contextMenus.removeAll(function () {
    menuItems.forEach(function (item) { chrome.contextMenus.create(item); });
  });
});

/**
 * 把用户右键点击的页面、链接或媒体地址转换为投递参数，
 * 再打开中转页触发 macOS 的 erye:// 自定义协议。
 */
chrome.contextMenus.onClicked.addListener(function (info, tab) {
  // 页面地址是所有场景的安全回退值。
  let target = info.pageUrl || "";
  let kind = "page";

  // 为不同上下文选择真正需要收藏或下载的 URL。
  if (info.menuItemId === "erye-link") {
    target = info.linkUrl || target;
    kind = "link";
  } else if (info.menuItemId === "erye-image") {
    target = info.srcUrl || target;
    kind = "image";
  } else if (info.menuItemId === "erye-media") {
    target = info.srcUrl || target;
    kind = "media";
  }

  // URLSearchParams 负责完整转义中文标题和带查询参数的远程地址。
  const params = new URLSearchParams({
    url: target,
    kind: kind,
    title: (tab && tab.title) || "网页收藏"
  });
  chrome.tabs.create({ url: chrome.runtime.getURL("handoff.html") + "?" + params.toString() });
});
