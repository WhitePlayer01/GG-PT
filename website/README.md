# 云长卫官网：运行、构建与发布

`website` 是云长卫官网的独立 Web 工程，使用 Next.js App Router、React、Vinext 和 Vite 构建，并已接入 OpenAI Sites / Cloudflare Workers 运行环境。

> 当前工程不是纯静态站点。正式构建会同时生成浏览器资源和服务端入口，因此不要只上传 `index.html`，也不要只发布 `dist/client`。

## 一、环境要求

- Node.js `22.13.0` 或更高版本
- npm（随 Node.js 安装）
- 首次安装依赖时需要访问 npm 软件源

检查本机环境：

```bash
node --version
npm --version
```

下面所有命令默认从仓库根目录开始执行。

## 二、首次安装

进入官网目录，并根据锁定文件安装依赖：

```bash
cd website
npm ci
```

日常开发中，如果 `package.json` 和 `package-lock.json` 没有变化，不需要每次重新安装。

## 三、本地开发运行

启动开发服务器：

```bash
cd website
npm run dev
```

默认访问地址：

```text
http://localhost:3000
```

开发服务器支持热更新，修改页面、样式或脚本后，浏览器会自动刷新。

如需使用其他端口，例如 `4173`：

```bash
npm run dev -- -p 4173
```

停止服务器时，在运行命令的终端按 `Ctrl + C`。

## 四、正式构建

执行生产构建：

```bash
cd website
npm run build
```

构建成功后会生成 `website/dist/`，主要内容包括：

- `dist/client/`：浏览器端脚本、样式、图片、视频和下载文件
- `dist/server/index.js`：服务端运行入口
- `dist/.openai/hosting.json`：Sites 发布配置

`dist/` 是自动生成目录，已加入 Git 忽略列表，不应手工修改或提交到仓库。每次发布都应从当前源码重新构建。

## 五、在本机验证生产包

完成构建后，启动生产服务器：

```bash
npm start
```

默认访问 `http://localhost:3000`。

如需指定监听地址和端口：

```bash
npm start -- -H 127.0.0.1 -p 4173
```

建议发布前至少检查：

1. 首页能正常打开，桌面端和移动端布局没有明显错位。
2. 角色图片、产品演示视频和页面动画可以加载。
3. 下载按钮能下载正确版本的 DMG。
4. 页面标题、描述、站点图标和分享预览图正确。
5. 浏览器控制台没有阻断页面功能的错误。

页面动画依赖 GSAP CDN。断网时正文和下载功能仍可使用，但滚动动画会降级。

## 六、发布到 OpenAI Sites（当前项目推荐方式）

工程已经通过 `.openai/hosting.json` 关联现有 Sites 项目，并在 `vite.config.ts` 中启用了 Sites 和 Cloudflare 插件。发布时应保留这两个文件，不要重新创建项目或随意修改其中的项目标识。

推荐发布流程：

1. 确认本地改动已经完成，需要发布的 DMG、图片和视频均已更新。
2. 运行 `npm ci`，确保依赖与 `package-lock.json` 完全一致。
3. 运行 `npm run build`，构建必须成功。
4. 使用 `npm start` 做一次生产包检查。
5. 在 Codex 中提出“将当前 `website` 发布到 Sites”，由 Sites 发布流程保存版本并部署。
6. 部署完成后打开线上地址，复查首页和 DMG 下载。

当前 `package.json` 没有 `deploy` 脚本，因此不要把 `npm run deploy` 当作发布命令。Sites 发布由托管流程完成，它会使用完整的 `dist/`，而不是只上传静态目录。

如果线上站点不是仅自己可见，部署新版本前需要确认当前共享或公开范围，避免误发布。

## 七、发布内容更新说明

### 更新页面内容

主要入口如下：

- `app/page.tsx`：页面入口，读取现有 `index.html` 中的主体内容
- `app/layout.tsx`：全站元信息、分享信息和全局脚本
- `index.html`：首页主体结构
- `styles.css`：页面样式
- `public/site.js`：页面交互和动画逻辑

### 更新图片和视频

源图片和视频位于 `assets/`。构建过程会复制并优化这些资源，例如把角色 PNG 优化为 `dist/client/assets/` 中的 WebP；因此应以构建后的文件作为发布验收对象。替换角色图时建议保留原文件的基础名称，如果修改名称，还要同步修改页面引用并检查构建结果。

### 更新 DMG 下载包

1. 将新的安装包放入 `website/downloads/`。
2. 更新页面下载链接，使文件名与实际 DMG 完全一致。
3. 运行 `npm run build`。
4. 确认新文件出现在 `dist/client/downloads/`。
5. 用生产服务器实际点击一次下载按钮，再执行发布。

`assets/` 和 `downloads/` 在 `website/.gitignore` 中被忽略。发布前要特别确认这些本地文件确实存在；如需让团队或持续集成环境也能构建完整站点，应另行确定这些大文件的版本管理或制品存储方案。

## 八、不要使用旧版静态预览作为发布验收

旧 README 曾使用下面的命令直接打开源码目录：

```bash
cd website
python3 -m http.server 4173
```

这个方式不会执行资源优化和 Vinext/Vite 构建，可能缺少页面实际引用的优化图片，也不能验证 `dist/server/index.js`、Sites 配置或生产运行环境。当前流程不再推荐使用它；日常开发使用 `npm run dev`，发布验收使用 `npm run build` 和 `npm start`。

## 九、常见问题

### `npm ci` 报 Node.js 版本不满足

升级到 Node.js `22.13.0` 或更高版本，然后重新执行 `npm ci`。

### 端口 `3000` 已被占用

开发环境改用其他端口：

```bash
npm run dev -- -p 4173
```

生产预览改用其他端口：

```bash
npm start -- -p 4173
```

### `npm start` 找不到构建结果

先执行：

```bash
npm run build
```

### 线上下载链接返回 404

依次检查：

1. `website/downloads/` 中是否存在目标文件。
2. 页面引用的文件名、中文字符、版本号和架构名是否完全一致。
3. 构建后 `dist/client/downloads/` 中是否包含该文件。
4. 是否部署了最新一次构建生成的完整 `dist/`。

## 十、发布前快速清单

```text
[ ] Node.js 版本满足要求
[ ] npm ci 成功
[ ] 页面内容和版本号已更新
[ ] 新 DMG 已放入 downloads 并更新下载链接
[ ] npm run build 成功
[ ] npm start 生产预览正常
[ ] 图片、视频、动画和下载均正常
[ ] 已确认 Sites 的可见范围
[ ] 部署后线上复查通过
```
