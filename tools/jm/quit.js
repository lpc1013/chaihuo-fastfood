// 正常退出 Tabbit：先记页面清单，再关 context、再关 browser。
// 目的只有一个——让 Chromium 在进程真正退出时自己清掉 E:\Temp\scoped_dir*。
// 绝不 taskkill（强杀会跳过退出清理，沙盒照样留在盘上）。
const fs = require('fs');
const LOG = 'E:/restauran/tools/_scratch/quit_log.json';
const out = {at: Date.now(), steps: []};
function save() { try { fs.writeFileSync(LOG, JSON.stringify(out, null, 1)); } catch (e) {} }

try {
  const pages = context.pages();
  out.pageCount = pages.length;
  out.urls = pages.map(p => p.url());
  out.hasBrowserGlobal = (typeof browser !== 'undefined');
  out.steps.push('listed');
  save();
} catch (e) { out.steps.push('list-failed: ' + String(e)); }

try { await context.close(); out.steps.push('context-closed'); }
catch (e) { out.steps.push('context-close-err: ' + String(e)); }
save();

try {
  if (typeof browser !== 'undefined') { await browser.close(); out.steps.push('browser-closed'); }
  else out.steps.push('no-browser-global');
} catch (e) { out.steps.push('browser-close-err: ' + String(e)); }
save();
return out;
