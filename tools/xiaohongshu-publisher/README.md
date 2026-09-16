# 小红书图文 Skill + MCP

独立的本地 MCP 服务，适合支持 stdio MCP 的 AI 客户端。与云长卫 App 无运行依赖。Skill 负责文案与授权判断，MCP 负责上传、读回、保存和单次提交状态机。

## 当前验证范围

已测试：过期自动存草稿、内容摘要、图片变更阻断、提交失败状态锁定、重复请求不重发、标准 MCP 客户端握手及工具发现。真实小红书网页适配尚待独立浏览器登录后验收；不承诺无人工干预或永久稳定。之前 Codex 原生桌面流程保存草稿成功，不等于此独立适配器已通过实机验证。

## 安装

需要 Node.js 22+ 和已安装的 Google Chrome。解压后在本目录执行 `npm ci`。启动命令为 `node /绝对路径/xiaohongshu-publisher/src/server.mjs`，服务通过标准输入输出通信，不开放网络监听。

若没有 Chrome，可执行 `npx playwright install chromium`，并设置环境变量 `XHS_BROWSER_CHANNEL=chromium`；默认直接使用本机 Chrome。

把 examples/mcp.json 中路径换成本机实际路径，导入支持 MCP 的客户端。stdio 需要客户端能启动本地进程，纯云端客户端不能直接读取本机素材。不要假定所有客户端配置入口和键名一致；examples 给出通用 mcpServers 结构。

首次调用 xhs_status 打开独立浏览器，请在该窗口登录小红书。默认数据目录为用户目录下 `.xiaohongshu-publisher`，可通过 XHS_DATA_DIR 指定。浏览器登录、草稿和任务状态随此目录保留，不与日常 Chrome 或手机草稿自动同步。

将 skill 文件夹复制到支持 SKILL.md 的 AI 工具技能目录；不支持 skill 的客户端可把其中流程作为项目指令使用。不要将账号登录目录复制给别人。

## 不经过 AI 的脚本入口

执行前先检查当前浏览器的小红书页面与登录账号，优先复用已有创作中心。CLI 使用独立 profile，不能接管日常 Chrome；已有登录页面时用能复用页面的工具或 CUA。选择独立脚本后，首次运行 `node src/cli.mjs login`，在弹出的独立 Chrome 登录后按回车。准备一个与 `examples/job.json` 同结构的任务文件，正文使用 JSON 换行，images 明确按封面、内页顺序排列。不要把内部说明或缩略图加入列表。

```sh
node src/cli.mjs check /绝对路径/发布任务.json
node src/cli.mjs run /绝对路径/发布任务.json
# immediate 或 scheduled 任务已有用户授权时：
node src/cli.mjs run /绝对路径/发布任务.json --publish-authorized
```

check 不联网；run 一次执行上传、填写、读回、设置与提交，无模型调用。默认 draft；过期定时自动存草稿。任务旁的 `.receipt.json` 绑定素材摘要和服务任务编号：同一成功任务重跑直接返回记录，失败或未知状态停止，不能通过删除回执或更换任务文件绕过重复检查。恢复需先核对页面与记录。提交成功不等于审核通过。

已安装 skill 的 `scripts/publish.sh` 是同一入口，可通过 `XHS_PUBLISHER_DIR` 指定服务位置。CLI 和 MCP 共用目录锁，不能同时运行。登录命令需交互终端；其他命令遇到账号不符、页面变化、验证码或超时会结束并保留记录。状态机、重复执行和失败路径有测试覆盖；独立浏览器实机流程仍待验收，不以原生 CUA 的发布结果代替脚本验收。

## 工具

| 工具 | 用途 |
| --- | --- |
| xhs_status | 打开登录窗口，读取当前可见页面 |
| xhs_prepare | 上传有序图片，填写标题与多行正文，读回检查，返回摘要与截图 |
| xhs_commit | 使用任务ID与摘要提交；默认存草稿，过时也存草稿 |
| xhs_job | 读取保存结果、错误及证据位置 |

prepare 参数例子见 examples/job.json。话题放 content 末尾，当前不自动选中平台话题标签。标题暂限20字符、正文1000字符、图片1–18张且单张不超过32MB；这些是当前适配器边界，不替代平台最新规则。

定时参数必须带时区，例如 2026-09-07T18:00:00+08:00。日期控件写入北京时间；适配器要求未来1小时至14天，写入后读回并只点击“定时发布”。无法唯一定位或读回不一致时停止，不降级点击“发布”。最终成功文本必须能匹配，否则返回unknown，不能声称已排期。

## 恢复与验收

任务状态保存在 data/jobs。submitting或unknown不自动重试；先在小红书笔记管理检查结果，避免重复发布。进程持有 server.lock，同一目录只运行一个客户端。正常退出释放锁；崩溃后确认没有服务或浏览器继续使用该目录，才手动删除空的server.lock目录。不同客户端可以轮流使用同一目录，不支持同时控制。

新环境先测试草稿：xhs_status登录 → xhs_prepare(mode=draft) → 检查截图 → xhs_commit → 看到草稿箱标题。然后在用户明确授权的一篇真实笔记上验证定时提交和笔记管理中的时间。不要为测试公开发布无意义内容。

页面适配集中在 src/browser.mjs。页面文案、日期控件或上传进度变化时修这里，不让模型猜坐标。新增版本应先跑 `npm test`，再验收草稿；首次定时发布需要用户确认平台显示的时间。工具返回错误会保留本地记录。截图可能包含账号或正文，按个人素材管理。

## 技术来源

使用官方 [MCP TypeScript SDK](https://ts.sdk.modelcontextprotocol.io/) 与 [Playwright](https://playwright.dev/docs/api/class-browsercontext)。没有复制第三方小红书 MCP 源码，不依赖私有签名接口或反检测功能。
