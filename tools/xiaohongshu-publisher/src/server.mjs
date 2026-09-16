import {McpServer} from '@modelcontextprotocol/sdk/server/mcp.js';
import {StdioServerTransport} from '@modelcontextprotocol/sdk/server/stdio.js';
import {z} from 'zod';
import {homedir} from 'node:os';
import path from 'node:path';
import {mkdir,rm} from 'node:fs/promises';
import {Jobs,commit} from './core.mjs';
import {PublisherBrowser} from './browser.mjs';

const root=path.resolve(process.env.XHS_DATA_DIR || path.join(homedir(),'.xiaohongshu-publisher'));
const jobs=new Jobs(path.join(root,'jobs')), browser=new PublisherBrowser(root);
const server=new McpServer({name:'xiaohongshu-publisher',version:'0.1.0'});
let busy=false,locked=false;
/** 串行工具调用与跨客户端目录锁，避免两个 AI 同时操作一个登录目录。 */
async function run(fn) {
  if(busy) return {isError:true,content:[{type:'text',text:'另一个操作仍在进行，请稍后检查状态'}]};
  busy=true;
  try {
    if(!locked) {
      await mkdir(root,{recursive:true,mode:0o700});
      await mkdir(path.join(root,'server.lock')); locked=true;
    }
    return {content:[{type:'text',text:JSON.stringify(await fn(),null,2)}]};
  } catch(e) {return {isError:true,content:[{type:'text',text:String(e)}]};}
  finally {busy=false;}
}
server.registerTool('xhs_status',{description:'检查独立浏览器页面；未登录时请用户在窗口扫码。不会自动发布。',inputSchema:{}},()=>run(()=>browser.status()));
server.registerTool('xhs_prepare',{description:'上传明确授权的本地图片并填写正文；返回任务ID、内容摘要和截图，不提交。',inputSchema:{account:z.string().min(1),title:z.string(),content:z.string(),images:z.array(z.string()).min(1),mode:z.enum(['draft','immediate','scheduled']).default('draft'),scheduleAt:z.string().optional()}},input=>run(async()=>{
  const job=await jobs.create(input);
  try {const evidence=await browser.prepare(job); return jobs.save({...job,state:'prepared',evidence});}
  catch(e) {await jobs.save({...job,state:'prepare_failed',error:String(e)}); throw e;}
}));
server.registerTool('xhs_commit',{description:'仅在用户已授权对应操作且内容审核通过后提交；传入准备结果的摘要。过期时间自动存草稿，未知结果不重试。',inputSchema:{jobId:z.string(),digest:z.string()}},({jobId,digest})=>run(()=>commit(jobs,browser,jobId,digest)));
server.registerTool('xhs_job',{description:'读取本地任务状态与证据，不触发发布。',inputSchema:{jobId:z.string()}},({jobId})=>run(()=>jobs.get(jobId)));
/** 正常退出释放目录锁；异常退出留下锁供人工检查，不能自动抢占仍在使用的浏览器。 */
async function close(){await browser.close();if(locked) await rm(path.join(root,'server.lock'),{recursive:true});process.exit(0);}
process.on('SIGINT',close);process.on('SIGTERM',close);
await server.connect(new StdioServerTransport());
