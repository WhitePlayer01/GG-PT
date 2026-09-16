import {chromium} from 'playwright';
import {mkdir} from 'node:fs/promises';
import path from 'node:path';

const HOME='https://creator.xiaohongshu.com/new/home';
const normalize=s=>s.replace(/\s+/gu,'');
/** 独立浏览器目录保存登录和本地草稿，不读取用户日常浏览器的凭证。 */
export class PublisherBrowser {
  constructor(root) { this.root=root; }
  async open() {
    if (this.context) return;
    await mkdir(this.root,{recursive:true,mode:0o700});
    const channel=process.env.XHS_BROWSER_CHANNEL || 'chrome';
    this.context=await chromium.launchPersistentContext(path.join(this.root,'profile'),{headless:false,...(channel === 'chromium' ? {} : {channel})});
    this.page=this.context.pages()[0] || await this.context.newPage();
    this.page.setDefaultTimeout(12000);
    this.page.setDefaultNavigationTimeout(30000);
    await this.page.goto(HOME);
  }
  async status() {
    await this.open();
    return {url:this.page.url(),text:(await this.page.locator('body').innerText()).slice(0,7000)};
  }
  async account(name) {
    if (!name.trim()) throw Error('必须指定预期账号');
    await this.page.getByText(name,{exact:true}).first().waitFor({state:'visible'});
  }
  async prepare(job) {
    await this.open(); await this.account(job.account);
    // 新任务不覆盖编辑器内的旧草稿；调用方应先处理旧任务。
    if (await this.page.getByPlaceholder('填写标题会有更多赞哦').count()) throw Error('当前已有编辑内容，请先保存或人工处理');
    const [picker]=await Promise.all([this.page.waitForEvent('filechooser'),this.page.getByText('发布图文笔记',{exact:false}).click()]);
    await picker.setFiles(job.images.map(x=>x.path));
    this.title=this.page.getByPlaceholder('填写标题会有更多赞哦');
    await this.title.waitFor({state:'visible',timeout:90000});
    // 选择器集中在适配层；页面变化时停止而非猜测按钮。
    this.editor=this.page.locator('[contenteditable="true"]').filter({visible:true});
    if (await this.editor.count() !== 1) throw Error('正文编辑器数量异常，请检查页面适配');
    await this.title.fill(job.title); await this.editor.fill(job.content); await this.title.click();
    await this.page.getByText(`${job.images.length}/18`,{exact:true}).waitFor({state:'visible',timeout:90000});
    await this.verify(job);
    return this.capture(job.id,'prepared');
  }
  async verify(job) {
    await this.account(job.account);
    this.title=this.page.getByPlaceholder('填写标题会有更多赞哦');
    this.editor=this.page.locator('[contenteditable="true"]').filter({visible:true});
    if (await this.title.inputValue() !== job.title || normalize(await this.editor.innerText()) !== normalize(job.content)) throw Error('页面内容与任务不一致');
    const actual=await this.editor.innerText();
    if (job.content.includes('\n') && !actual.includes('\n')) throw Error('正文换行丢失');
    await this.page.getByText(`${job.images.length}/18`,{exact:true}).waitFor({state:'visible'});
  }
  async configure(mode,time) {
    const scheduledButton=this.page.getByRole('button',{name:'定时发布',exact:true});
    const enabled=await scheduledButton.count() > 0;
    if (enabled !== (mode === 'scheduled')) {
      const labels=await this.page.getByText('定时发布',{exact:true}).all();
      const candidates=[];
      for(const label of labels) if(await label.evaluate(el=>el.tagName !== 'BUTTON') && await label.isVisible()) candidates.push(label);
      if(candidates.length !== 1) throw Error('定时开关定位不唯一，停止操作');
      await candidates[0].click();
    }
    if(mode !== 'scheduled') {
      await this.page.getByRole('button',{name:'发布',exact:true}).waitFor({state:'visible'}); return;
    }
    const lead=Date.parse(time)-Date.now();
    if(lead < 3600000 || lead > 14*86400000) throw Error('当前适配器只接受1小时至14天内的计划时间');
    const parts=new Intl.DateTimeFormat('sv-SE',{timeZone:'Asia/Shanghai',year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hourCycle:'h23'}).format(new Date(time));
    const inputs=await this.page.locator('input').all(), dates=[];
    for(const input of inputs) if(await input.isVisible() && /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$/.test(await input.inputValue())) dates.push(input);
    if(dates.length !== 1) throw Error('定时日期输入框无法唯一识别');
    await dates[0].fill(parts); await dates[0].press('Tab');
    if(await dates[0].inputValue() !== parts) throw Error('计划时间写入失败，不会点击立即发布');
    await scheduledButton.waitFor({state:'visible'});
    this.scheduledInput=dates[0]; this.scheduledValue=parts;
  }
  async submit(mode,job) {
    if (mode === 'draft') {
      await this.page.getByRole('button',{name:'暂存离开',exact:true}).click();
      await this.page.getByText(/草稿箱\(/).waitFor({state:'visible',timeout:30000});
      if (!(await this.page.getByText(job.title,{exact:true}).count())) await this.page.getByText(/草稿箱\(/).click();
      await this.page.getByText(job.title,{exact:true}).waitFor({state:'visible'});
    } else {
      if(mode === 'scheduled' && await this.scheduledInput.inputValue() !== this.scheduledValue) throw Error('提交前计划时间发生变化');
      await this.page.getByRole('button',{name:mode === 'scheduled' ? '定时发布' : '发布',exact:true}).click();
      await this.page.getByText(mode === 'scheduled' ? /定时发布成功|预约成功/ : /发布成功/).waitFor({state:'visible',timeout:45000});
    }
    const evidence = await this.capture(job.id,mode);
    if (mode === 'immediate') {
      // 成功页可能自动跳转；后台核对失败不抹掉已取得的提交成功证据。
      try {
        await this.page.getByText('笔记管理',{exact:true}).click();
        await this.page.getByText(job.title,{exact:false}).first().waitFor({state:'visible'});
        evidence.management = await this.capture(job.id,'management');
        evidence.management.titleFound = true;
      } catch (error) { evidence.managementError = String(error); }
    }
    return evidence;
  }
  async capture(id,stage) {
    const file=path.join(this.root,`${id}-${stage}.png`);
    await this.page.screenshot({path:file});
    return {screenshot:file,url:this.page.url(),checkedAt:new Date().toISOString()};
  }
  async close() { await this.context?.close(); }
}
