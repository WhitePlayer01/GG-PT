"use strict";
const container = document.getElementById("items");
const empty = document.getElementById("empty");
async function render() {
  const stored = await chrome.storage.local.get({ inbox: [] });
  container.replaceChildren();
  stored.inbox.forEach(function (item) {
    const article = document.createElement("article");
    article.className = "item";
    const copy = document.createElement("div");
    const title = document.createElement("h2");
    title.textContent = item.title || item.url;
    const link = document.createElement("a");
    link.href = item.url;
    link.target = "_blank";
    link.rel = "noreferrer";
    link.textContent = item.url;
    const time = document.createElement("small");
    time.textContent = new Date(item.capturedAt).toLocaleString("zh-CN");
    copy.append(title, link, time);
    const actions = document.createElement("div");
    actions.className = "item-actions";
    const collect = document.createElement("button");
    collect.className = "collect";
    collect.dataset.collect = item.id;
    collect.textContent = "交给二爷";
    const deletion = document.createElement("button");
    deletion.dataset.delete = item.id;
    deletion.textContent = "移除";
    actions.append(collect, deletion);
    article.append(copy, actions);
    container.append(article);
  });
  empty.hidden = stored.inbox.length !== 0;
  document.getElementById("clear").disabled = stored.inbox.length === 0;
}
async function remove(id) { const stored = await chrome.storage.local.get({ inbox: [] }); await chrome.storage.local.set({ inbox: stored.inbox.filter(function (item) { return item.id !== id; }) }); await chrome.runtime.sendMessage({ type: "sync-badge" }); render(); }
container.addEventListener("click", async function (event) {
  const collect = event.target.closest("[data-collect]"); const deletion = event.target.closest("[data-delete]");
  if (deletion) return remove(deletion.dataset.delete);
  if (collect) { const stored = await chrome.storage.local.get({ inbox: [] }); const item = stored.inbox.find(function (value) { return value.id === collect.dataset.collect; }); if (item) { await chrome.runtime.sendMessage({ type: "open-handoff", payload: item }); await remove(item.id); } }
});
document.getElementById("clear").addEventListener("click", async function () { await chrome.storage.local.set({ inbox: [] }); await chrome.runtime.sendMessage({ type: "sync-badge" }); render(); });
render();
