import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {Jobs,destination,commit} from '../src/core.mjs';
/** 用替身验证会影响真实发布的状态边界，不向小红书发送测试笔记。 */
async function setup(){const dir=await mkdtemp(path.join(tmpdir(),'xhs-test-'));const img=path.join(dir,'1.png');await writeFile(img,'test');const jobs=new Jobs(dir);const job=await jobs.create({account:'test',title:'标题',content:'第一段\n第二段',images:[img],mode:'immediate'});await jobs.save({...job,state:'prepared'});return {jobs,job,img};}
test('过期定时必须存草稿',()=>assert.equal(destination({mode:'scheduled',scheduleAt:'2026-01-01T18:00:00+08:00'},Date.parse('2026-01-02T00:00:00Z')),'draft'));
test('成功调用重复请求只提交一次',async()=>{const {jobs,job}=await setup();let count=0;const a={verify:async()=>{},configure:async()=>{},submit:async()=>{count++;return {ok:true}}};await commit(jobs,a,job.id,job.digest);await commit(jobs,a,job.id,job.digest);assert.equal(count,1);});
test('提交超时锁定为unknown，不自动重发',async()=>{const {jobs,job}=await setup();let count=0;const a={verify:async()=>{},configure:async()=>{},submit:async()=>{count++;throw Error('timeout')}};await assert.rejects(commit(jobs,a,job.id,job.digest));assert.equal((await jobs.get(job.id)).state,'unknown');await assert.rejects(commit(jobs,a,job.id,job.digest));assert.equal(count,1);});
test('素材被修改时不提交',async()=>{const {jobs,job,img}=await setup();await writeFile(img,'changed');await assert.rejects(commit(jobs,{},job.id,job.digest),/图片已改变/);});
test('页面核对失败不进入提交状态',async()=>{const {jobs,job}=await setup();await assert.rejects(commit(jobs,{verify:async()=>{throw Error('不一致')}},job.id,job.digest));assert.equal((await jobs.get(job.id)).state,'prepared');});
test('过期定时的实际提交模式为draft',async()=>{const {jobs,job}=await setup();await jobs.save({...job,state:'prepared',mode:'scheduled',scheduleAt:'2020-01-01T18:00:00+08:00'});let seen;await commit(jobs,{verify:async()=>{},configure:async m=>{seen=m},submit:async()=>({})},job.id,job.digest);assert.equal(seen,'draft');});
// 崩溃后即使浏览器没有返回，也不能冒险点击第二次。
test('重新加载submitting任务仍拒绝提交',async()=>{const {jobs,job}=await setup();await jobs.save({...job,state:'submitting'});const restored=new Jobs(jobs.dir);await assert.rejects(commit(restored,{},job.id,job.digest),/submitting/);});
test('日期配置失败时没有提交副作用',async()=>{const {jobs,job}=await setup();let submitted=false;await assert.rejects(commit(jobs,{verify:async()=>{},configure:async()=>{throw Error('日期不匹配')},submit:async()=>{submitted=true}},job.id,job.digest));assert.equal(submitted,false);assert.equal((await jobs.get(job.id)).state,'prepared');});
test('摘要不一致时不触碰浏览器',async()=>{const {jobs,job}=await setup();await assert.rejects(commit(jobs,{},job.id,'wrong'),/摘要不匹配/);});
