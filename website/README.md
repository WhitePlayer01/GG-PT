# 云长卫官网

独立静态官网，不依赖 `minitool-dist`。

本地预览：

```bash
cd website
python3 -m http.server 4173
```

打开 `http://localhost:4173`。下载按钮指向 `downloads/云长卫-0.2.0-arm64.dmg`。

页面动画使用 GSAP CDN；断网时内容和下载仍可用，仅滚动动画降级为静态展示。
