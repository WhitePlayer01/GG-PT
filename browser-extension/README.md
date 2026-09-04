# 云长卫 · 浏览器扩展

V0.7.2 网页协同版，适用于 Chrome、Edge 以及其他 Chromium 浏览器。代码使用 WebExtension 标准 API，可通过 Xcode 的 Safari Web Extension Converter 转成 Safari App Extension，与同一个 macOS App 配合。

## 本地安装

1. 先运行构建后的“云长卫.app”，让 macOS 注册 `erye://` 投递链接。
2. 浏览器打开扩展管理页，并开启“开发者模式”。
3. 选择“加载已解压的扩展程序”，选中本目录。
4. 点击工具栏中的“云长卫”打开收纳面板，或在网页、链接、图片和音视频上点击右键。

在网页图片上点击右键，选择“一键归纳图片到本地”，图片会交给云长卫下载，并按当前本地收纳规则分类。App 已运行时会直接收纳，不打开唤起页；App 未运行时才使用中转页唤起。

每次直接收纳完成后，浏览器会显示“收纳成功”或“收纳失败”系统通知，桌宠也会同步显示结果。

右键收纳图片时，扩展优先使用当前浏览器会话读取图片内容，因此可处理需要登录的图片、图片搜索缩略图、`data:` 和 `blob:` 图片。单张图片上限为 18 MB。

网页和普通链接会保存为 `.webloc` 书签；正文会保存为带来源头的 Markdown；图片、音频和视频会由 Mac App 下载，并按现有规则或指定分类归档。首次投递时，浏览器可能询问是否允许打开桌面 App。

## 弹出菜单

- 当前图片交给二爷
- 当前页面通过系统打印面板保存为 PDF
- 提取正文并保存为 Markdown
- 当前链接加入本机待收纳箱
- 页面全部图片批量收集，单次最多 30 张
- 收纳前选择目标分类，并添加以逗号分隔的标签

桌面端会在导入文件的 `com.yunchangwei.web-source` 扩展属性中保存文件名、来源 URL、采集时间和标签。Markdown 文件还会把这些字段写进文首的 YAML 元数据。

## Safari 转换

在装有 Xcode 的 Mac 上运行：

```bash
xcrun safari-web-extension-converter browser-extension --project-location safari-extension
```

转换后在 Xcode 中选择开发团队并运行容器 App。Safari 版本复用同一套弹出面板、待收纳箱和 `erye://collect` 桌面投递协议，不需要改写业务逻辑。

## 右键菜单

- 当前网页交给二爷：保存当前页面 `.webloc` 书签
- 这个链接交给二爷：保存链接 `.webloc` 书签
- 一键归纳图片到本地：下载图片并按云长卫现有规则自动分类
- 这段音视频交给二爷：下载媒体并自动分类

## 文件说明

- `manifest.json`：Manifest V3 清单，声明右键菜单和标签页权限
- `service-worker.js`：注册菜单并生成中转页参数
- `popup.html` / `popup.js`：工具栏收纳面板
- `content-script.js`：在当前页面提取正文和高质量图片
- `inbox.html` / `inbox.js`：保存在浏览器本机的待收纳箱
- `handoff.html`：向用户解释外部协议提示的中转页面
- `handoff.js`：构建并触发 `erye://collect` 深链
- `handoff.css`：中转页品牌样式

`manifest.json` 必须保持标准 JSON，JSON 语法不允许添加注释；各字段用途因此集中记录在本说明中。

## 听歌记录

重新加载扩展后，在面板开启“听歌记录”，刷新音乐网页，并在桌宠设置 → 听歌记录中开启自动记录。仅访问网易云音乐、QQ 音乐、Spotify、Apple Music、YouTube Music 音乐站点的媒体元数据。网页必须提供歌名、歌手和播放状态；不采集页面正文或声音。桌宠未运行时静默停止投递，不弹出网页唤起提示。关闭扩展开关后停止采样，桌宠最迟约 15 秒清除已失联的网页播放状态。

可用 `node browser-extension/music-observer.test.cjs` 在项目根目录验证媒体信息读取与开关、站点过滤。实际站点支持程度仍需对应播放器播放验证。
