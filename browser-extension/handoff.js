"use strict";

const query = new URLSearchParams(window.location.search);
const deepLink = new URL("erye://collect");
["url", "kind", "title"].forEach(function (name) {
  const value = query.get(name);
  if (value) deepLink.searchParams.set(name, value);
});

const openApp = document.getElementById("open-app");
openApp.href = deepLink.toString();
document.getElementById("close-tab").addEventListener("click", function () { window.close(); });
window.location.href = deepLink.toString();
