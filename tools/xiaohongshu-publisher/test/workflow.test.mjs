import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, writeFile, readFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {Jobs, manifest} from '../src/core.mjs';
import {execute} from '../src/workflow.mjs';

/** 使用浏览器替身检验一键流程，测试不会上传或公开发布。 */
async function setup() {
  const dir = await mkdtemp(path.join(tmpdir(),'xhs-workflow-'));
  const image = path.join(dir,'01.png'); await writeFile(image,'test');
  const input = {account:'测试',title:'标题',content:'第一段\n\n第二段',images:[image],mode:'immediate'};
  const calls = [];
  const options = {jobs:new Jobs(path.join(dir,'jobs')), receipt:path.join(dir,'receipt.json'),
    browser:{prepare:async()=>{calls.push('prepare');return {};},verify:async()=>{},configure:async()=>{},submit:async()=>{calls.push('submit');return {};}}};
  return {input, options, calls};
}
test('重复运行同一任务只上传并提交一次',async()=>{
  const {input,options,calls}=await setup();
  assert.equal((await execute(input,options)).state,'published');
  assert.equal((await execute(input,options)).state,'published');
  assert.deepEqual(calls,['prepare','submit']);
});
test('提交结果未知时，下次运行不重新上传',async()=>{
  const {input,options,calls}=await setup();
  options.browser.submit=async()=>{calls.push('submit');throw Error('断线');};
  await assert.rejects(execute(input,options),/不确定/);
  await assert.rejects(execute(input,options),/unknown/);
  assert.deepEqual(calls,['prepare','submit']);
});
test('上传中断也保留任务并阻止重跑',async()=>{
  const {input,options}=await setup();
  options.browser.prepare=async()=>{throw Error('登录失效');};
  await assert.rejects(execute(input,options),/登录失效/);
  const receipt=JSON.parse(await readFile(options.receipt,'utf8'));
  assert.equal((await options.jobs.get(receipt.jobId)).state,'prepare_failed');
  await assert.rejects(execute(input,options),/prepare_failed/);
});
test('回执对应的内容改变时停止，不覆盖旧任务',async()=>{
  const {input,options,calls}=await setup(); await execute(input,options);
  await assert.rejects(execute({...input,title:'新标题'},options),/素材已变化/);
  assert.deepEqual(calls,['prepare','submit']);
});
// 不允许拼错发布方式后落入默认的公开发布按钮。
test('拒绝非法模式、缺少账号或定时时间',async()=>{
  const {input}=await setup();
  await assert.rejects(manifest({...input,mode:'typo'}),/方式无效/);
  await assert.rejects(manifest({...input,account:''}),/预期账号/);
  await assert.rejects(manifest({...input,mode:'scheduled'}),/指定时间/);
});
