(function () {
  "use strict";

  // localStorage 键用于保存当前浏览器累计选择的素材数量。
  var STORAGE_KEY = "er-ye-shou-zhe-total-v1";
  // 缓存页面节点，避免每次选择文件时重复查询 DOM。
  var mediaInput = document.getElementById("media-input");
  var hero = document.querySelector(".hero");
  var heroMessage = document.getElementById("hero-message");
  var currentCount = document.getElementById("current-count");
  var totalCount = document.getElementById("total-count");
  var emptyState = document.getElementById("empty-state");
  var resultList = document.getElementById("result-list");
  var clearButton = document.getElementById("clear-button");
  var previewUrls = [];

  /** 读取累计数量，并把非法或负值归零。 */
  function readTotal() {
    var value = Number(localStorage.getItem(STORAGE_KEY));
    return Number.isFinite(value) && value > 0 ? Math.floor(value) : 0;
  }

  /** 保存累计数量并同步更新页面数字。 */
  function writeTotal(value) {
    localStorage.setItem(STORAGE_KEY, String(value));
    totalCount.textContent = String(value);
  }

  /** 根据浏览器提供的 MIME 类型返回素材分类和文字标记。 */
  function fileKind(file) {
    if (file.type.indexOf("image/") === 0) {
      return { label: "图片", mark: "图" };
    }
    if (file.type.indexOf("video/") === 0) {
      return { label: "视频", mark: "影" };
    }
    return { label: "素材", mark: "件" };
  }

  /** 将字节数转换为适合素材列表展示的容量文本。 */
  function readableSize(bytes) {
    if (bytes < 1024) return bytes + " B";
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KB";
    return (bytes / (1024 * 1024)).toFixed(1) + " MB";
  }

  /** 释放图片预览创建的 Object URL，避免长时间使用产生内存泄漏。 */
  function releasePreviews() {
    previewUrls.forEach(function (url) {
      URL.revokeObjectURL(url);
    });
    previewUrls = [];
  }

  /** 为单个文件创建缩略图、文件名、容量和类型标签。 */
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

    // 最多生成六张真实图片预览，其余素材使用轻量文字标记。
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

  /** 重新触发挥刀动效并更新桌宠本次收纳台词。 */
  function strike(count) {
    hero.classList.remove("is-striking");
    void hero.offsetWidth;
    hero.classList.add("is-striking");
    heroMessage.textContent = "收了 " + count + " 件，妥妥当当";
  }

  /** 处理文件选择，重建本次列表并累计素材数量。 */
  function handleSelection(event) {
    var files = Array.prototype.slice.call(event.target.files || []);
    if (!files.length) return;

    // 每次选择都代表一个新批次，先清理上批预览和列表节点。
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

  /** 清空本次记录、累计数量和文件输入控件。 */
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

  // 初始化累计值并绑定用户交互与页面销毁清理事件。
  totalCount.textContent = String(readTotal());
  mediaInput.addEventListener("change", handleSelection);
  clearButton.addEventListener("click", clearRecord);
  window.addEventListener("pagehide", releasePreviews);
}());
