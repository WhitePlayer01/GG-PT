(function () {
  "use strict";

  var STORAGE_KEY = "er-ye-shou-zhe-total-v1";
  var mediaInput = document.getElementById("media-input");
  var hero = document.querySelector(".hero");
  var heroMessage = document.getElementById("hero-message");
  var currentCount = document.getElementById("current-count");
  var totalCount = document.getElementById("total-count");
  var emptyState = document.getElementById("empty-state");
  var resultList = document.getElementById("result-list");
  var clearButton = document.getElementById("clear-button");
  var previewUrls = [];

  function readTotal() {
    var value = Number(localStorage.getItem(STORAGE_KEY));
    return Number.isFinite(value) && value > 0 ? Math.floor(value) : 0;
  }

  function writeTotal(value) {
    localStorage.setItem(STORAGE_KEY, String(value));
    totalCount.textContent = String(value);
  }

  function fileKind(file) {
    if (file.type.indexOf("image/") === 0) {
      return { label: "图片", mark: "图" };
    }
    if (file.type.indexOf("video/") === 0) {
      return { label: "视频", mark: "影" };
    }
    return { label: "素材", mark: "件" };
  }

  function readableSize(bytes) {
    if (bytes < 1024) return bytes + " B";
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KB";
    return (bytes / (1024 * 1024)).toFixed(1) + " MB";
  }

  function releasePreviews() {
    previewUrls.forEach(function (url) {
      URL.revokeObjectURL(url);
    });
    previewUrls = [];
  }

  function buildItem(file) {
    var kind = fileKind(file);
    var row = document.createElement("article");
    var thumb = document.createElement("div");
    var copy = document.createElement("div");
    var name = document.createElement("strong");
    var detail = document.createElement("small");
    var tag = document.createElement("span");

    row.className = "result-item";
    thumb.className = "thumb";
    copy.className = "result-copy";
    tag.className = "type-tag";

    if (kind.label === "图片" && previewUrls.length < 6) {
      var image = document.createElement("img");
      var url = URL.createObjectURL(file);
      previewUrls.push(url);
      image.src = url;
      image.alt = "";
      thumb.appendChild(image);
    } else {
      thumb.textContent = kind.mark;
    }

    name.textContent = file.name || "未命名素材";
    detail.textContent = readableSize(file.size);
    tag.textContent = kind.label;
    copy.appendChild(name);
    copy.appendChild(detail);
    row.appendChild(thumb);
    row.appendChild(copy);
    row.appendChild(tag);
    return row;
  }

  function strike(count) {
    hero.classList.remove("is-striking");
    void hero.offsetWidth;
    hero.classList.add("is-striking");
    heroMessage.textContent = "收了 " + count + " 件，妥妥当当";
  }

  function handleSelection(event) {
    var files = Array.prototype.slice.call(event.target.files || []);
    if (!files.length) return;

    releasePreviews();
    resultList.replaceChildren();
    files.forEach(function (file) {
      resultList.appendChild(buildItem(file));
    });

    currentCount.textContent = String(files.length);
    writeTotal(readTotal() + files.length);
    emptyState.hidden = true;
    resultList.hidden = false;
    strike(files.length);
  }

  function clearRecord() {
    releasePreviews();
    resultList.replaceChildren();
    resultList.hidden = true;
    emptyState.hidden = false;
    currentCount.textContent = "0";
    mediaInput.value = "";
    writeTotal(0);
    heroMessage.textContent = "图片视频，尽管交来";
  }

  totalCount.textContent = String(readTotal());
  mediaInput.addEventListener("change", handleSelection);
  clearButton.addEventListener("click", clearRecord);
  window.addEventListener("pagehide", releasePreviews);
}());
