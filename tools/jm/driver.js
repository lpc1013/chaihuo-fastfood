// 即梦（jimeng.jianying.com）产图驱动 —— 由 tools/jmkit.py 注入 JOB/STAGE 后经 tabbit-cli 执行。
// 约束：全程只用任务已有的那一张标签页，绝不 newPage。
const fs = require('fs');
const JOB = __JOB__;

const norm = (s) => (s || '').replace(/\s+/g, '');
const objId = (src) => { const m = /cfz\/([0-9a-f]{32})/.exec(src || ''); return m ? m[1] : null; };
const GEN_URL = 'https://jimeng.jianying.com/ai-tool/generate?type=image';

function loadManifest() {
  const f = JOB.out + '/manifest.json';
  let m = {};
  try { m = JSON.parse(fs.readFileSync(f, 'utf8')); } catch (e) { m = {}; }
  return m;
}
function saveManifest(m) {
  fs.mkdirSync(JOB.out, {recursive: true});
  fs.writeFileSync(JOB.out + '/manifest.json', JSON.stringify(m, null, 1));
}

async function ensureComposer(p) {
  for (let attempt = 0; attempt < 2; attempt++) {
    if (await p.evaluate(() => !!document.querySelector('.tiptap.ProseMirror'))) return true;
    await p.goto('about:blank');
    await p.waitForTimeout(1200);
    await p.goto(GEN_URL, {waitUntil: 'domcontentloaded'});
    for (let i = 0; i < 10; i++) {
      await p.waitForTimeout(1500);
      if (await p.evaluate(() => !!document.querySelector('.tiptap.ProseMirror'))) return true;
    }
  }
  return false;
}

async function dismissModals(p) {
  await p.keyboard.press('Escape');
  await p.mouse.click(6, 6);
  await p.waitForTimeout(350);
  await p.keyboard.press('Escape');
  return p.evaluate(() => document.querySelectorAll("[class*='lv-popover'],[class*='lv-select-popup']").length);
}

async function readBar(p) {
  return p.evaluate(() => {
    const btn = [...document.querySelectorAll('[class*="toolbar-button"]')]
      .find(e => /\d+[Kk]|智能比例/.test(e.innerText));
    const model = [...document.querySelectorAll('div.lv-select')]
      .map(e => e.innerText.trim()).find(t => /Seedream/i.test(t)) || null;
    return {bar: btn ? btn.innerText.replace(/\s+/g, ' ').trim() : null, model};
  });
}

async function clickLeaf(p, want) {
  const pt = await p.evaluate((w) => {
    const hosts = [...document.querySelectorAll("[class*='lv-popover-content-inner'],[class*='lv-select-popup'],[class*='popup']")];
    let best = null;
    for (const h of hosts) {
      for (const e of h.querySelectorAll('*')) {
        if (e.children.length !== 0) continue;
        if ((e.innerText || '').trim() !== w) continue;
        const r = e.getBoundingClientRect();
        if (r.width > 0 && r.height > 0) best = {x: r.x + r.width / 2, y: r.y + r.height / 2};
      }
    }
    return best;
  }, want);
  if (!pt) return false;
  await p.mouse.click(pt.x, pt.y);
  await p.waitForTimeout(650);
  return true;
}

async function setBar(p, ratio, count) {
  const want = [ratio, count == null ? null : String(count)].filter(Boolean);
  for (let i = 0; i < 3; i++) {
    const cur = await readBar(p);
    if (cur.bar && want.every(w => cur.bar.includes(w))) return {ok: true, bar: cur.bar};
    const btn = await p.evaluate(() => {
      const e = [...document.querySelectorAll('[class*="toolbar-button"]')]
        .find(x => /\d+[Kk]|智能比例/.test(x.innerText));
      if (!e) return null;
      const r = e.getBoundingClientRect();
      return {x: r.x + r.width / 2, y: r.y + r.height / 2};
    });
    if (!btn) return {ok: false, err: 'bar button missing', bar: cur.bar};
    await p.mouse.click(btn.x, btn.y);
    await p.waitForTimeout(900);
    for (const w of want) await clickLeaf(p, w);
    await p.keyboard.press('Escape');
    await p.waitForTimeout(350);
  }
  const fin = await readBar(p);
  return {ok: !!(fin.bar && want.every(w => fin.bar.includes(w))), bar: fin.bar};
}

async function setModel(p, label) {
  for (let i = 0; i < 3; i++) {
    const cur = await readBar(p);
    if (cur.model && cur.model.includes(label)) return {ok: true, model: cur.model};
    const box = await p.evaluate(() => {
      const e = [...document.querySelectorAll('div.lv-select')].find(x => /Seedream/i.test(x.innerText));
      if (!e) return null;
      const r = e.getBoundingClientRect();
      return {x: r.x + r.width / 2, y: r.y + r.height / 2};
    });
    if (!box) return {ok: false, err: 'model select missing'};
    await p.mouse.click(box.x, box.y);
    await p.waitForTimeout(900);
    if (!(await clickLeaf(p, label))) { await p.keyboard.press('Escape'); continue; }
  }
  const fin = await readBar(p);
  return {ok: !!(fin.model && fin.model.includes(label)), model: fin.model};
}

async function typePrompt(p, text) {
  await p.evaluate(() => {
    const e = document.querySelector('.tiptap.ProseMirror');
    e.innerHTML = '<p><br></p>';
    e.dispatchEvent(new InputEvent('input', {bubbles: true}));
  });
  await p.waitForTimeout(200);
  const ed = await p.locator('.tiptap.ProseMirror').first();
  await ed.click({force: true});
  await p.waitForTimeout(150);
  await p.keyboard.insertText(text);
  await p.waitForTimeout(250);
  return p.evaluate(() => document.querySelector('.tiptap.ProseMirror').innerText);
}

async function submitCurrent(p) {
  return p.evaluate(() => {
    const btns = [...document.querySelectorAll('button[class*="submit-button"]')]
      .filter(b => b.getBoundingClientRect().width > 0);
    if (!btns.length) return {ok: false, err: 'no submit button'};
    const b = btns.find(x => !x.disabled) || btns[0];
    if (b.disabled) return {ok: false, err: 'submit disabled'};
    b.click();
    return {ok: true};
  });
}

async function scrollResults(p, where) {
  await p.evaluate((w) => {
    const cands = [...document.querySelectorAll('div')].filter(d => {
      const s = getComputedStyle(d);
      return /(auto|scroll)/.test(s.overflowY) && d.scrollHeight > d.clientHeight + 200;
    }).sort((a, b) => b.scrollHeight - a.scrollHeight)[0];
    if (!cands) return;
    cands.scrollTop = w === 'top' ? 0 : (w === 'mid' ? cands.scrollHeight / 2 : cands.scrollHeight);
  }, where);
  await p.waitForTimeout(700);
}

async function scanBatch(p, prompt) {
  return p.evaluate((pr) => {
    const want = pr.replace(/\s+/g, '');
    const isResult = (i) => {
      const s = i.currentSrc || i.src || '';
      return /cfz\/[0-9a-f]{32}/.test(s) && i.naturalWidth >= 200;
    };
    let holder = null, bestLen = Infinity;
    for (const e of document.querySelectorAll('div,section,article,p,span,h1,h2,h3')) {
      const t = (e.innerText || '').replace(/\s+/g, '');
      if (t.length >= bestLen || !t.includes(want)) continue;
      bestLen = t.length; holder = e;
    }
    if (!holder) return [];
    let n = holder, imgs = [];
    for (let hop = 0; hop < 12; hop++) {
      if (!n) break;
      imgs = [...n.querySelectorAll('img')].filter(isResult);
      if (imgs.length) break;
      n = n.parentElement;
    }
    const seen = new Set();
    return imgs.map((i) => {
      const s = i.currentSrc || i.src;
      const b = i.getBoundingClientRect();
      return {id: /cfz\/([0-9a-f]{32})/.exec(s)[1], src: s, w: i.naturalWidth, h: i.naturalHeight, top: Math.round(b.top)};
    }).filter(o => seen.has(o.id) ? false : (seen.add(o.id), true));
  }, prompt);
}

async function grab(p, url, file) {
  const resp = await context.request.get(url);
  if (!resp.ok()) return {ok: false, status: resp.status()};
  const buf = await resp.body();
  fs.mkdirSync(require('path').dirname(file), {recursive: true});
  fs.writeFileSync(file, buf);
  return {ok: true, bytes: buf.length};
}

async function stagePing(p) {
  const ready = await ensureComposer(p);
  const bar = await readBar(p);
  const login = await p.evaluate(() => document.body.innerText.includes('请先登录'));
  return {ready, login, ...bar, pageCount: context.pages().length, url: p.url()};
}

function wsUrl(id) { return 'https://jimeng.jianying.com/ai-tool/generate?workspace=' + id; }

function readWorkspace(p) {
  try { return new URL(p.url()).searchParams.get('workspace'); } catch (e) { return null; }
}

async function openThread(p, id) {
  if (!id) return;
  if (readWorkspace(p) === id) return;
  await p.goto(wsUrl(id), {waitUntil: 'domcontentloaded'});
  for (let i = 0; i < 10; i++) {
    await p.waitForTimeout(1500);
    const n = await p.evaluate(() => [...document.querySelectorAll('img')]
      .filter(e => /cfz\/[0-9a-f]{32}/.test(e.currentSrc || e.src) && e.naturalWidth >= 200).length);
    if (n > 0) return;
  }
}

async function tryType(p, text) {
  for (let i = 0; i < 2; i++) {
    await dismissModals(p);
    const got = await typePrompt(p, text);
    if (norm(got) === norm(text)) return true;
    await p.waitForTimeout(1200);
  }
  await p.goto(GEN_URL, {waitUntil: 'domcontentloaded'});
  for (let i = 0; i < 10; i++) {
    await p.waitForTimeout(1500);
    const b = await readBar(p);
    if (b.bar) break;
  }
  await setBar(p, JOB.ratio || '16:9', JOB.count == null ? 4 : JOB.count);
  const got = await typePrompt(p, text);
  return norm(got) === norm(text);
}

async function gotoLanding(p) {
  await p.goto(GEN_URL, {waitUntil: 'domcontentloaded'});
  for (let i = 0; i < 12; i++) {
    await p.waitForTimeout(1500);
    const b = await readBar(p);
    const ed = await p.evaluate(() => !!document.querySelector('.tiptap.ProseMirror'));
    if (b.bar && ed) return true;
  }
  return false;
}

async function attachRef(p, file) {
	const slot = await p.evaluate(() => {
		const cands = [...document.querySelectorAll('[class*="reference-upload"],[class*="upload"]')]
			.map(e => { const r = e.getBoundingClientRect(); return {x: r.x + r.width / 2, y: r.y + r.height / 2, w: r.width, t: (e.innerText || '').slice(0, 20)}; })
			.filter(o => o.w > 20 && o.y > 0);
		return cands.length ? cands[0] : null;
	});
	if (!slot) return {ok: false, err: 'no reference slot'};
	let fc;
	try {
		const [f] = await Promise.all([
			p.waitForEvent('filechooser', {timeout: 8000}),
			p.mouse.click(slot.x, slot.y),
		]);
		fc = f;
	} catch (e) { return {ok: false, err: 'no filechooser'}; }
	await fc.setFiles(file);
	for (let i = 0; i < 12; i++) {
		await p.waitForTimeout(1200);
		const got = await p.evaluate(() => {
			const img = [...document.querySelectorAll('[data-content-generator-references] img, img[src^="blob:"]')]
				.find(e => (e.src || '').startsWith('blob:') && e.naturalWidth > 20);
			return img ? {w: img.naturalWidth, h: img.naturalHeight} : null;
		});
		if (got) return {ok: true, ...got};
	}
	return {ok: false, err: 'blob preview never appeared'};
}

async function stageSubmit(p) {
  const log = [];
  const man = loadManifest();
  const sent = [];
  for (const b of JOB.batches) {
    if (!(await gotoLanding(p))) return {err: 'landing composer not ready'};
    log.push({popovers: await dismissModals(p)});
    log.push(await setModel(p, b.model || JOB.model || 'Seedream 5.0 Lite'));
    log.push(await setBar(p, b.ratio || JOB.ratio || '16:9', JOB.count == null ? 4 : JOB.count));
    if (b.ref) {
      const r = await attachRef(p, b.ref);
      sent.push({tag: b.tag, ref: r});
      if (!r.ok) return {err: 'reference upload failed: ' + r.err, sent};
    }
    if (!(await tryType(p, b.prompt))) {
      sent.push({tag: b.tag, ok: false, err: 'prompt mismatch', wantLen: norm(b.prompt).length});
      continue;
    }
    const s = await submitCurrent(p);
    await p.waitForTimeout(3500);
    const ws = readWorkspace(p);
    sent.push({tag: b.tag, ...s, ws, at: Date.now()});
    if (ws) { man[b.tag] = Object.assign(man[b.tag] || {}, {workspace: ws, prompt: b.prompt, out: JOB.out}); }
    await dismissModals(p);
  }
  saveManifest(man);
  return {sent, log, pageCount: context.pages().length};
}

// 按「文档顺序」归属：线程里每条提示词气泡都排在它那组结果图之前，
// 所以每张图归属于文档流中排在它前面的最后一条提示词。祖先文本匹配会串台（多图共享容器时命中同一 tag）。
async function attribByOrder(p, prompts) {
  return p.evaluate((ps) => {
    const nodes = [...document.querySelectorAll('*')];
    const pos = new Map();
    nodes.forEach((n, i) => pos.set(n, i));
    const marks = [];
    for (const q of ps) {
      const want = q.prompt.replace(/\s+/g, '');
      let last = -1;
      for (const n of nodes) {
        const t = (n.innerText || '').replace(/\s+/g, '');
        if (!t.length || t.length > want.length + 500) continue;
        if (t.includes(want)) last = pos.get(n);
      }
      if (last >= 0) marks.push({at: last, tag: q.tag});
    }
    marks.sort((a, b) => a.at - b.at);
    const buckets = {};
    for (const q of ps) if (!buckets[q.tag]) buckets[q.tag] = [];
    for (const img of document.querySelectorAll('img')) {
      const s = img.currentSrc || img.src || '';
      const m = /cfz\/([0-9a-f]{32})/.exec(s);
      if (!m || img.naturalWidth < 200) continue;
      const i = pos.get(img);
      let tag = null;
      for (const mk of marks) { if (mk.at >= i) break; tag = mk.tag; }
      if (!tag) continue;
      if (!buckets[tag].some(o => o.id === m[1])) {
        buckets[tag].push({id: m[1], src: s, w: img.naturalWidth, h: img.naturalHeight});
      }
    }
    return {buckets, marks: marks.length};
  }, prompts);
}

async function stageCollect(p) {
  const man = loadManifest();
  const res = [];
  const need = JOB.count == null ? 4 : JOB.count;
  for (const b of JOB.batches) {
    const rec = man[b.tag] || {};
    await openThread(p, rec.workspace);
    let found = [];
    for (let round = 0; round < 5 && found.length < need; round++) {
      for (const w of ['bottom', 'mid', 'top']) {
        await scrollResults(p, w);
        const one = await attribByOrder(p, [{tag: b.tag, prompt: b.prompt}]);
        for (const g of (one.buckets[b.tag] || [])) if (!found.some(f => f.id === g.id)) found.push(g);
        if (found.length >= need) break;
      }
      if (found.length < need) await p.waitForTimeout(8000);
    }
    if (!found.length) {
      // 带参考图的消息里图片可能排在提示词之前，单批线程直接取全部结果图
      for (const w of ['bottom', 'mid', 'top']) {
        await scrollResults(p, w);
        const all = await p.evaluate(() => [...document.querySelectorAll('img')].filter(i => {
          const s2 = i.currentSrc || i.src || '';
          return /cfz\/([0-9a-f]{32})/.test(s2) && i.naturalWidth >= 200;
        }).map(i => {
          const s2 = i.currentSrc || i.src;
          return {id: /cfz\/([0-9a-f]{32})/.exec(s2)[1], src: s2, w: i.naturalWidth, h: i.naturalHeight};
        }));
        for (const g of all) if (!found.some(f => f.id === g.id)) found.push(g);
        if (found.length >= need) break;
      }
    }
    found = found.slice(0, need);
    const files = [], ids = [];
    for (let i = 0; i < found.length; i++) {
      const f = `${JOB.out}/${b.tag}_${i + 1}.png`;
      const g = await grab(p, found[i].src, f);
      if (g.ok) { files.push({n: i + 1, path: f, bytes: g.bytes, w: found[i].w, h: found[i].h}); ids.push(found[i].id); }
    }
    man[b.tag] = Object.assign({}, rec, {prompt: b.prompt, out: JOB.out, ids, files, hd: rec.hd || {}, ts: Date.now()});
    res.push({tag: b.tag, got: files.length, ws: rec.workspace || null, dims: files.length ? [`${files[0].w}x${files[0].h}`] : []});
  }
  saveManifest(man);
  return {res, pageCount: context.pages().length};
}

async function stageHd(p) {
  const man = loadManifest();
  const res = [];
  for (const b of JOB.batches) {
    const rec = man[b.tag];
    if (!rec || !rec.ids || !rec.ids.length) { res.push({tag: b.tag, got: 0, err: 'no manifest ids'}); continue; }
    const hd = rec.hd || {};
    await openThread(p, rec.workspace);
    const pick = b.hd && b.hd.length ? b.hd.map(n => n - 1) : rec.ids.map((_, n) => n);
    for (const i of pick) {
      if (i < 0 || i >= rec.ids.length) continue;
      const id = rec.ids[i];
      if (hd[id] && fs.existsSync(hd[id].path)) continue;
      const want = rec.prompt;
      let hit = null;
      for (let round = 0; round < 3 && !hit; round++) {
        for (const w of ['bottom', 'mid', 'top']) {
          await scrollResults(p, w);
          const cand = await attribByOrder(p, [{tag: 'x', prompt: want}])
            .then(r => (r.buckets.x || []).find(x => x.id === id));
          if (!cand) continue;
          const box = await p.evaluate((arg) => {
            const imgs = [...document.querySelectorAll('img')];
            const img = imgs.find(e => /cfz\/([0-9a-f]{32})/.test(e.currentSrc || e.src) &&
              RegExp('cfz\\/' + arg.id).test(e.currentSrc || e.src));
            if (!img) return null;
            img.scrollIntoView({block: 'center'});
            const r = img.getBoundingClientRect();
            return {x: r.x + r.width / 2, y: r.y + r.height / 2};
          }, {id});
          if (!box) continue;
          await p.waitForTimeout(500);
          await p.mouse.click(box.x, box.y);
          await p.waitForTimeout(2200);
          for (let k = 0; k < 8; k++) {
            hit = await p.evaluate((arg) => {
              for (const img of document.querySelectorAll('img')) {
                const s = img.currentSrc || img.src || '';
                if (!s.includes('cfz/' + arg.id)) continue;
                if (img.naturalWidth >= 700) return {src: s, w: img.naturalWidth, h: img.naturalHeight};
              }
              return null;
            }, {id});
            if (hit) break;
            await p.waitForTimeout(1200);
          }
          await p.keyboard.press('Escape');
          await p.waitForTimeout(600);
          if (hit) break;
        }
      }
      if (!hit) { res.push({tag: b.tag, n: i + 1, err: 'hd not found'}); continue; }
      const f = `${JOB.out}/hd/${b.tag}_${i + 1}.png`;
      const g = await grab(p, hit.src, f);
      if (g.ok) { hd[id] = {path: f, w: hit.w, h: hit.h, bytes: g.bytes}; res.push({tag: b.tag, n: i + 1, ok: true, w: hit.w, h: hit.h, bytes: g.bytes}); }
      else res.push({tag: b.tag, n: i + 1, err: 'download failed ' + g.status});
    }
    rec.hd = hd;
    man[b.tag] = rec;
    saveManifest(man);
  }
  return {res, pageCount: context.pages().length};
}

async function stageQuit() {
  // 每轮生图跑完必须整进程退出：只关标签页不会清 scoped_dir 沙盒缓存
  const n = context.pages().length;
  let browserClosed = false;
  try { await context.close(); } catch (e) {}
  try {
    if (typeof browser !== 'undefined' && browser && typeof browser.close === 'function') {
      await browser.close(); browserClosed = true;
    }
  } catch (e) {}
  return {closedPages: n, browserClosed, remaining: (typeof context.pages === 'function' ? context.pages().length : -1)};
}

async function run() {
  if (JOB.stage === 'quit') return stageQuit();
  const pages = context.pages();
  let p = pages.find(x => (x.url() || '').includes('jimeng')) || pages[0];
  if (!p) return {err: 'no page'};
  if (typeof usePage === 'function') { try { await usePage(p); } catch (e) {} }
  const stage = JOB.stage;
  if (stage === 'ping') return stagePing(p);
  if (stage === 'submit') return stageSubmit(p);
  if (stage === 'collect') return stageCollect(p);
  if (stage === 'hd') return stageHd(p);
  return {err: 'unknown stage ' + stage};
}

return await run();
