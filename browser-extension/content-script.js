"use strict";

function absoluteURL(value) {
  try { return new URL(value, document.baseURI).href; } catch (_) { return ""; }
}

function pageSnapshot() {
  const images = Array.from(document.images)
    .map(function (img) {
      return {
        url: absoluteURL(img.currentSrc || img.src),
        alt: img.alt || "",
        width: img.naturalWidth || img.width || 0,
        height: img.naturalHeight || img.height || 0
      };
    })
    .filter(function (image) {
      return /^https?:/.test(image.url) && image.width >= 180 && image.height >= 120;
    })
    .filter(function (image, index, all) {
      return all.findIndex(function (candidate) { return candidate.url === image.url; }) === index;
    })
    .sort(function (a, b) { return (b.width * b.height) - (a.width * a.height); });

  const root = document.querySelector("article, main, [role='main']") || document.body;
  const clone = root.cloneNode(true);
  clone.querySelectorAll("script, style, nav, footer, aside, form, button, svg, canvas, iframe, noscript").forEach(function (node) { node.remove(); });
  const lines = [];
  clone.querySelectorAll("h1, h2, h3, h4, p, blockquote, pre, li, img").forEach(function (node) {
    if (node.tagName === "IMG") {
      const src = absoluteURL(node.currentSrc || node.src);
      if (src) lines.push("![" + (node.alt || "网页图片").replace(/[\[\]]/g, "") + "](" + src + ")");
      return;
    }
    const text = (node.innerText || node.textContent || "").replace(/\s+/g, " ").trim();
    if (!text) return;
    if (/^H[1-4]$/.test(node.tagName)) lines.push("#".repeat(Number(node.tagName[1])) + " " + text);
    else if (node.tagName === "BLOCKQUOTE") lines.push("> " + text);
    else if (node.tagName === "LI") lines.push("- " + text);
    else if (node.tagName === "PRE") lines.push("```\n" + text + "\n```");
    else lines.push(text);
  });

  return {
    title: document.title || location.hostname,
    url: location.href,
    description: document.querySelector("meta[name='description']")?.content || "",
    images: images.slice(0, 60),
    markdown: lines.join("\n\n").slice(0, 60000)
  };
}

pageSnapshot();
