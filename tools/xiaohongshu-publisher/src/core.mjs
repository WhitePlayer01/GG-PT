import {createHash, randomUUID} from 'node:crypto';
import {mkdir, readFile, writeFile, rename, realpath, stat} from 'node:fs/promises';
import path from 'node:path';

/** 校验文件并冻结内容；上传前后使用同一份摘要，避免素材被悄悄替换。 */
export async function manifest(input) {
  if (!input || typeof input.account !== 'string' || !input.account.trim()) throw Error('必须指定预期账号');
  if (!['draft','immediate','scheduled'].includes(input.mode)) throw Error('发布方式无效');
  if (typeof input.title !== 'string' || typeof input.content !== 'string' || !Array.isArray(input.images)) throw Error('标题、正文或图片列表格式无效');
  if (input.mode === 'scheduled' && !input.scheduleAt) throw Error('定时发布必须指定时间');
  if (input.mode !== 'scheduled' && input.scheduleAt) throw Error('只有定时任务可以带计划时间');
  if (!input.title.trim() || [...input.title].length > 20) throw Error('标题需要1至20个字符');
  if (!input.content.trim() || [...input.content].length > 1000) throw Error('正文需要1至1000个字符');
  if (!input.images.length || input.images.length > 18) throw Error('图片数量需要1至18张');
  if (input.scheduleAt && (!/(Z|[+-]\d\d:\d\d)$/.test(input.scheduleAt) || !Number.isFinite(Date.parse(input.scheduleAt)))) throw Error('时间必须为含时区的ISO8601格式');
  const images = [];
  for (const file of input.images) {
    if (!path.isAbsolute(file)) throw Error('图片必须为本机绝对路径');
    const name = await realpath(file), info = await stat(name);
    if (!info.isFile() || info.size > 32 * 1024 * 1024 || !/\.(png|jpe?g|webp)$/i.test(name)) throw Error('图片格式或大小不支持');
    images.push({path:name, sha256:createHash('sha256').update(await readFile(name)).digest('hex')});
  }
  const data = {...input, images};
  return {...data, digest:createHash('sha256').update(JSON.stringify(data)).digest('hex')};
}

/** 过时任务只存草稿，不能自动转换为立即发布。 */
export function destination(job, now=Date.now()) {
  if (job.mode === 'draft' || (job.scheduleAt && Date.parse(job.scheduleAt) <= now)) return 'draft';
  if (job.mode === 'scheduled' && !job.scheduleAt) throw Error('定时发布必须指定时间');
  return job.mode;
}

/** 每次状态变更原子写盘，进程中断后保留不确定状态，禁止自动再次提交。 */
export class Jobs {
  constructor(dir) { this.dir=dir; }
  async save(job) {
    await mkdir(this.dir,{recursive:true,mode:0o700});
    const temp=path.join(this.dir,`${job.id}.tmp`), final=path.join(this.dir,`${job.id}.json`);
    await writeFile(temp,JSON.stringify(job,null,2),{mode:0o600}); await rename(temp,final); return job;
  }
  async get(id) {
    if (!/^[0-9a-f-]{36}$/.test(id)) throw Error('无效任务编号');
    return JSON.parse(await readFile(path.join(this.dir,`${id}.json`),'utf8'));
  }
  async create(input) { return this.save({id:randomUUID(),state:'created',...await manifest(input)}); }
}

/** 把浏览器副作用包在单次提交状态机内，浏览器适配器可独立测试。 */
export async function commit(jobs, adapter, id, digest) {
  const job=await jobs.get(id);
  if (['draft','published','scheduled'].includes(job.state)) return job;
  if (job.state !== 'prepared') throw Error(`状态${job.state}禁止提交；请检查记录和页面`);
  if (job.digest !== digest) throw Error('内容摘要不匹配，请重新审核');
  const fresh=await manifest({...job,images:job.images.map(x=>x.path),id:undefined,state:undefined,digest:undefined});
  if (fresh.images.some((x,i)=>x.sha256 !== job.images[i].sha256)) throw Error('图片已改变，需新建任务');
  const mode=destination(job);
  await adapter.verify(job); // 真正提交前读回页面内容和账号。
  await adapter.configure(mode,job.scheduleAt);
  await jobs.save({...job,state:'submitting',requestedMode:mode});
  try {
    const evidence=await adapter.submit(mode,job);
    return await jobs.save({...job,state:mode === 'immediate' ? 'published' : mode,evidence});
  } catch(error) {
    await jobs.save({...job,state:'unknown',error:String(error)});
    throw Error('提交结果不确定，已锁定自动重试；请查看小红书页面和任务记录');
  }
}
