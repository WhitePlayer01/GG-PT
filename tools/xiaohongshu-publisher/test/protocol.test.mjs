import {test} from 'node:test';
import assert from 'node:assert/strict';
import {Client} from '@modelcontextprotocol/sdk/client/index.js';
import {StdioClientTransport} from '@modelcontextprotocol/sdk/client/stdio.js';
import {fileURLToPath} from 'node:url';
/** 从真正的 MCP 客户端握手并发现工具，确保不是只测内部函数。 */
test('标准stdio客户端能发现四个工具',async()=>{
  const client=new Client({name:'acceptance',version:'1.0.0'});
  const transport=new StdioClientTransport({command:process.execPath,args:[fileURLToPath(new URL('../src/server.mjs',import.meta.url))]});
  try {await client.connect(transport);const {tools}=await client.listTools();assert.deepEqual(tools.map(x=>x.name).sort(),['xhs_commit','xhs_job','xhs_prepare','xhs_status']);}
  finally {await client.close();}
});
