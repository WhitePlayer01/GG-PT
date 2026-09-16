import {readFile, mkdir, rm} from 'node:fs/promises';
import {homedir} from 'node:os';
import path from 'node:path';
import {createInterface} from 'node:readline/promises';
import {Jobs, manifest, destination} from './core.mjs';
import {PublisherBrowser} from './browser.mjs';
import {execute} from './workflow.mjs';

/** 命令行入口不调用模型；素材检查不联网，run 串行执行网页动作。 */
const [command, file, ...flags] = process.argv.slice(2);
const root = path.resolve(process.env.XHS_DATA_DIR || path.join(homedir(), '.xiaohongshu-publisher'));
let browser, locked = false;
async function cleanup() {
  await browser?.close();
  if (locked) { await rm(path.join(root, 'server.lock'), {recursive:true}); locked = false; }
}
process.on('SIGINT', () => { void cleanup().finally(() => process.exit(130)); });
process.on('SIGTERM', () => { void cleanup().finally(() => process.exit(143)); });
try {
  if (!['check', 'run', 'login'].includes(command) || (command !== 'login' && !file) || flags.some(x => x !== '--publish-authorized')) {
    throw Error('用法：node src/cli.mjs check|run 任务.json [--publish-authorized]，或 node src/cli.mjs login');
  }
  let input;
  if (command !== 'login') {
    input = JSON.parse(await readFile(path.resolve(file), 'utf8'));
    input.mode ??= 'draft';
    const checked = await manifest(input);
    if (command === 'check') {
      console.log(JSON.stringify({...checked, effectiveMode:destination(input)}, null, 2));
    } else if (destination(input) !== 'draft' && !flags.includes('--publish-authorized')) {
      throw Error('此任务会公开发布；已有用户授权时加 --publish-authorized，未授权时改为 draft');
    }
  }
  if (command !== 'check') {
    await mkdir(root, {recursive:true, mode:0o700});
    await mkdir(path.join(root, 'server.lock')); locked = true;
    browser = new PublisherBrowser(root);
    if (command === 'login') {
      if (!process.stdin.isTTY) throw Error('请在交互式终端执行 login');
      console.log(await browser.status());
      const rl = createInterface({input:process.stdin, output:process.stdout});
      try { await rl.question('在独立浏览器完成登录后按回车保存并退出：'); }
      finally { rl.close(); }
      console.log(await browser.status());
    } else {
      const result = await execute(input, {jobs:new Jobs(path.join(root, 'jobs')), browser,
        receipt:path.resolve(file) + '.receipt.json'});
      // 返回真实证据；published 仅代表平台接收，不代表审核通过。
      console.log(JSON.stringify(result, null, 2));
    }
  }
} catch (error) {
  console.error(String(error)); process.exitCode = 1;
} finally { await cleanup(); }
