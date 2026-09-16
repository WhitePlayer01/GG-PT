import {readFile, writeFile} from 'node:fs/promises';
import {manifest, commit} from './core.mjs';

/** 一次完成固定动作，使用持久化回执阻止同一任务再次上传或发布。 */
export async function execute(input, {jobs, browser, receipt}) {
  const frozen = await manifest(input);
  let previous;
  try { previous = JSON.parse(await readFile(receipt, 'utf8')); }
  catch (error) { if (error.code !== 'ENOENT') throw error; }
  if (previous) {
    if (previous.digest !== frozen.digest) throw Error('此回执对应的素材已变化；请检查旧任务，不覆盖回执');
    const old = await jobs.get(previous.jobId);
    if (['draft', 'published', 'scheduled'].includes(old.state)) return old;
    throw Error(`已有任务 ${old.id}，状态 ${old.state}；先核对页面与记录，不自动重试`);
  }
  const job = await jobs.create(input);
  // 上传前落盘，即使进程在页面操作中断，下次也不会新建一篇。
  await writeFile(receipt, JSON.stringify({jobId: job.id, digest: frozen.digest}, null, 2), {flag:'wx', mode:0o600});
  try {
    const evidence = await browser.prepare(job);
    await jobs.save({...job, state:'prepared', evidence});
  } catch (error) {
    await jobs.save({...job, state:'prepare_failed', error:String(error)});
    throw error;
  }
  return commit(jobs, browser, job.id, job.digest);
}
