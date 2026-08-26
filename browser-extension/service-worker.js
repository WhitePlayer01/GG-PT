"use strict";

const menuItems = [
  { id: "erye-page", title: "当前网页交给二爷", contexts: ["page"] },
  { id: "erye-link", title: "这个链接交给二爷", contexts: ["link"] },
  { id: "erye-image", title: "这张图片交给二爷", contexts: ["image"] },
  { id: "erye-media", title: "这段音视频交给二爷", contexts: ["audio", "video"] }
];

chrome.runtime.onInstalled.addListener(function () {
  chrome.contextMenus.removeAll(function () {
    menuItems.forEach(function (item) { chrome.contextMenus.create(item); });
  });
});

chrome.contextMenus.onClicked.addListener(function (info, tab) {
  let target = info.pageUrl || "";
  let kind = "page";

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

  const params = new URLSearchParams({
    url: target,
    kind: kind,
    title: (tab && tab.title) || "网页收藏"
  });
  chrome.tabs.create({ url: chrome.runtime.getURL("handoff.html") + "?" + params.toString() });
});
