/* =========================================================
   FitLog 玻璃版 — Apple Liquid Glass 前端重构
   数据模型对齐原 Android 版：动作 / 训练日 / 组(重量·次数·单双边·RPE)
   ========================================================= */
'use strict';

const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];

/* ---------- 肌群 ---------- */
const MUSCLES = {
  chest:    { label: '胸',   emoji: '🦾' },
  back:     { label: '背',   emoji: '🔙' },
  legs:     { label: '腿',   emoji: '🦵' },
  shoulder: { label: '肩',   emoji: '🤷' },
  arms:     { label: '手臂', emoji: '💪' },
  core:     { label: '核心', emoji: '🔥' },
};
const SIDE_LABEL = { BOTH: '双手', LEFT: '左手', RIGHT: '右手' };

/* ---------- 内置动作（与 Android 版一致） ---------- */
const BUILTIN = [
  ['卧推', 'chest'], ['哑铃飞鸟', 'chest'], ['上斜卧推', 'chest'],
  ['引体向上', 'back'], ['杠铃划船', 'back'], ['高位下拉', 'back'],
  ['深蹲', 'legs'], ['硬拉', 'legs'], ['腿举', 'legs'],
  ['坐姿推举', 'shoulder'], ['侧平举', 'shoulder'],
  ['哑铃弯举', 'arms'], ['三头下压', 'arms'],
  ['卷腹', 'core'], ['平板支撑', 'core'],
];

/* ---------- 状态 ---------- */
const STORE_KEY = 'fitlog_glass_v1';
let state = load();

function defaultState() {
  const exercises = BUILTIN.map(([name, mg], i) => ({
    id: 'ex_' + (i + 1), name, muscle: mg, isBuiltIn: true, createdAt: Date.now(),
  }));
  return {
    exercises,
    sessions: seedSessions(exercises),
    settings: { threshold: 72, reminder: true, unit: 'kg', apiKey: '' },
  };
}
function load() {
  try {
    const raw = localStorage.getItem(STORE_KEY);
    if (raw) return JSON.parse(raw);
  } catch (e) {}
  return defaultState();
}
function save() { try { localStorage.setItem(STORE_KEY, JSON.stringify(state)); } catch (e) {} }

/* 生成示例历史，让首屏就有数据 */
function seedSessions(exercises) {
  const ex = (n) => exercises.find(e => e.name === n);
  const days = 24;
  const out = {};
  const pick = (arr) => arr[Math.floor(Math.random() * arr.length)];
  const now = new Date();
  for (let d = days; d >= 0; d--) {
    if (Math.random() < 0.35) continue; // 有些天没练
    const dt = new Date(now); dt.setDate(now.getDate() - d);
    const key = dateKey(dt);
    const exs = [];
    const chosen = [ex('深蹲'), ex('卧推'), ex('硬拉'), ex('引体向上'), ex('哑铃弯举'), ex('坐姿推举')]
      .filter(Boolean).sort(() => Math.random() - 0.5).slice(0, 2 + Math.floor(Math.random() * 2));
    for (const c of chosen) {
      const setN = 3 + Math.floor(Math.random() * 2);
      const base = 40 + Math.floor(Math.random() * 40);
      const sets = [];
      for (let s = 0; s < setN; s++) {
        sets.push({
          weight: Math.max(20, base + s * 2.5 + (Math.random() * 5 - 2.5)),
          reps: pick([6, 8, 8, 10, 12]),
          side: 'BOTH',
          rpe: +(7 + Math.random() * 2.5).toFixed(1),
        });
      }
      exs.push({ exerciseId: c.id, sets });
    }
    out[key] = { note: '', exercises: exs };
  }
  return out;
}

/* ---------- 日期工具 ---------- */
function dateKey(d) { return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`; }
function parseKey(k) { const [y,m,dd] = k.split('-').map(Number); return new Date(y, m-1, dd); }
function weekday(d) { return ['周日','周一','周二','周三','周四','周五','周六'][d.getDay()]; }
function todayKey() { return dateKey(new Date()); }

/* =========================================================
   液态玻璃引擎：为每个 .glass-liquid 元素生成边缘倒角位移贴图
   ========================================================= */
function makeGlassMap(w, h, radius, bevel, amp) {
  w = Math.max(8, w | 0); h = Math.max(8, h | 0);
  const c = document.createElement('canvas'); c.width = w; c.height = h;
  const ctx = c.getContext('2d'); const img = ctx.createImageData(w, h);
  const hw = w/2, hh = h/2; const clamp = v => v<0?0:v>255?255:v|0;
  const sdf = (x,y) => {
    const qx = Math.abs(x-hw)-(hw-radius), qy = Math.abs(y-hh)-(hh-radius);
    const ax = Math.max(qx,0), ay = Math.max(qy,0);
    return Math.hypot(ax,ay) + Math.min(Math.max(qx,qy),0) - radius;
  };
  for (let y=0;y<h;y++) for (let x=0;x<w;x++) {
    const e=1, sx=sdf(x+e,y)-sdf(x-e,y), sy=sdf(x,y+e)-sdf(x,y-e);
    const len=Math.hypot(sx,sy)||1, nx=sx/len, ny=sy/len, d=sdf(x,y);
    let mag=0; if (d>-bevel && d<=0) mag=(d+bevel)/bevel;
    const i=(y*w+x)*4;
    img.data[i]=clamp(128+nx*mag*amp); img.data[i+1]=clamp(128+ny*mag*amp);
    img.data[i+2]=128; img.data[i+3]=255;
  }
  ctx.putImageData(img,0,0); return c.toDataURL('image/png');
}
const _filterCache = {};
function applyLiquidGlass() {
  const svgNS = 'http://www.w3.org/2000/svg';
  let defs = $('#liquidDefs');
  if (!defs) { defs = document.createElementNS(svgNS,'defs'); defs.id='liquidDefs'; $('#glassSvg').appendChild(defs); }
  $$('.glass-liquid').forEach(el => {
    const w = el.offsetWidth, h = el.offsetHeight;
    if (!w || !h) return;
    const id = 'lg_' + Math.round(w) + 'x' + Math.round(h);
    if (!_filterCache[id]) {
      const f = document.createElementNS(svgNS,'filter');
      f.setAttribute('id', id); f.setAttribute('x','-20%'); f.setAttribute('y','-20%');
      f.setAttribute('width','140%'); f.setAttribute('height','140%');
      f.setAttribute('color-interpolation-filters','sRGB');
      const fi = document.createElementNS(svgNS,'feImage');
      fi.setAttribute('width','100%'); fi.setAttribute('height','100%'); fi.setAttribute('preserveAspectRatio','none'); fi.setAttribute('result','map');
      const map = makeGlassMap(w, h, Math.min(w,h)*0.32, Math.min(w,h)*0.12, 80);
      fi.setAttribute('href', map); fi.setAttributeNS('http://www.w3.org/1999/xlink','xlink:href', map);
      const gb = document.createElementNS(svgNS,'feGaussianBlur'); gb.setAttribute('in','SourceGraphic'); gb.setAttribute('stdDeviation','3'); gb.setAttribute('result','blur');
      const dm = document.createElementNS(svgNS,'feDisplacementMap'); dm.setAttribute('in','blur'); dm.setAttribute('in2','map');
      dm.setAttribute('scale','34'); dm.setAttribute('xChannelSelector','R'); dm.setAttribute('yChannelSelector','G');
      f.append(fi, gb, dm); defs.appendChild(f); _filterCache[id] = true;
    }
    el.style.backdropFilter = `blur(3px) saturate(170%) url(#${id})`;
    el.style.webkitBackdropFilter = `blur(3px) saturate(170%) url(#${id})`;
  });
}
window.addEventListener('resize', () => { if (!document.body.classList.contains('no-refract')) applyLiquidGlass(); });

/* =========================================================
   Tab 切换
   ========================================================= */
let currentTab = 'train';
function switchTab(tab) {
  currentTab = tab;
  $$('.tab-panel').forEach(p => p.classList.toggle('active', p.dataset.tab === tab));
  $$('.nav-item').forEach(n => n.classList.toggle('active', n.dataset.go === tab));
  if (tab === 'stats') renderStats();
  if (tab === 'library') renderLibrary();
  if (tab === 'settings') renderSettings();
}
$$('.nav-item').forEach(n => n.addEventListener('click', () => switchTab(n.dataset.go)));

/* =========================================================
   训练页
   ========================================================= */
let viewDate = todayKey();
function renderTrain() {
  const dt = parseKey(viewDate);
  $('#dayLabel').textContent = viewDate === todayKey() ? '今天' : (viewDate > todayKey() ? '未来' : '历史');
  $('#dayWeek').textContent = `${viewDate} ${weekday(dt)}`;
  const sess = state.sessions[viewDate];
  const exCards = sess ? sess.exercises : [];
  let totalVol = 0, totalSets = 0;
  const list = $('#trainList');
  if (!exCards.length) {
    list.innerHTML = `<div class="empty">今天还没记录，点下面「＋ 添加动作」开始训练 💪</div>`;
  } else {
    list.innerHTML = exCards.map((ex, ei) => {
      const meta = state.exercises.find(e => e.id === ex.exerciseId);
      if (!meta) return '';
      const m = MUSCLES[meta.muscle];
      const rows = ex.sets.map((s, si) => {
        totalVol += (s.weight || 0) * (s.reps || 0); totalSets++;
        return `<div class="set-row" data-ei="${ei}" data-si="${si}">
          <div class="set-idx">${si+1}</div>
          <div class="set-cell"><b>${fmt(s.weight)}</b></div>
          <div class="set-cell">${s.reps} 次</div>
          <div class="set-cell set-side">${SIDE_LABEL[s.side]}</div>
          <div class="set-cell set-rpe">${s.rpe ? 'RPE '+s.rpe : '—'}</div>
          <div class="set-del" data-del="${ei}:${si}">🗑</div>
        </div>`;
      }).join('');
      return `<div class="ex-card glass">
        <div class="ex-head">
          <div class="ex-muscle">${m.emoji}</div>
          <div class="ex-name">${meta.name}</div>
          <div class="ex-del" data-rmex="${ei}">移除</div>
        </div>
        ${rows}
        <button class="add-set" data-addset="${ei}">＋ 添加一组</button>
      </div>`;
    }).join('');
  }
  $('#volTotal').textContent = fmt(totalVol);
  $('#volSets').textContent = totalSets;
  $('#volEx').textContent = exCards.length;
  // 绑定
  $$('.set-row').forEach(r => r.addEventListener('click', e => {
    if (e.target.dataset.del) return;
    openSetSheet(+r.dataset.ei, +r.dataset.si);
  }));
  $$('.set-del').forEach(b => b.addEventListener('click', e => {
    e.stopPropagation(); const [ei,si]=b.dataset.del.split(':').map(Number); delSet(ei,si);
  }));
  $$('[data-addset]').forEach(b => b.addEventListener('click', () => addSet(+b.dataset.addset)));
  $$('[data-rmex]').forEach(b => b.addEventListener('click', () => removeExercise(+b.dataset.rmex)));
}
function fmt(n) { return (Math.round(n*10)/10).toString(); }
function ensureSession() { if (!state.sessions[viewDate]) state.sessions[viewDate] = { note:'', exercises:[] }; return state.sessions[viewDate]; }
function addExerciseToDay(id) {
  const s = ensureSession();
  if (s.exercises.some(e => e.exerciseId === id)) { toast('该动作已在今日训练里'); return; }
  s.exercises.push({ exerciseId: id, sets: [{ weight: 20, reps: 8, side: 'BOTH', rpe: 8 }] });
  save(); renderTrain();
}
function removeExercise(ei) { ensureSession().exercises.splice(ei,1); save(); renderTrain(); }
function addSet(ei) {
  const ex = ensureSession().exercises[ei];
  const last = ex.sets[ex.sets.length-1] || { weight:20, reps:8, side:'BOTH', rpe:8 };
  ex.sets.push({ ...last }); save(); renderTrain();
}
function delSet(ei, si) { ensureSession().exercises[ei].sets.splice(si,1); save(); renderTrain(); }

$('#dayPrev').addEventListener('click', () => { viewDate = shift(viewDate,-1); renderTrain(); });
$('#dayNext').addEventListener('click', () => { viewDate = shift(viewDate, 1); renderTrain(); });
$('#dayToday').addEventListener('click', () => { viewDate = todayKey(); renderTrain(); });
function shift(k, n) { const d=parseKey(k); d.setDate(d.getDate()+n); return dateKey(d); }

/* ---------- 添加动作弹层 ---------- */
let pickerFilter = 'all';
function openPicker() {
  pickerFilter = 'all';
  renderPicker();
  $('#pickerMask').hidden = false;
}
function renderPicker() {
  const chips = $('#pickerChips');
  chips.innerHTML = `<div class="chip ${pickerFilter==='all'?'active':''}" data-f="all">全部</div>` +
    Object.entries(MUSCLES).map(([k,v]) => `<div class="chip ${pickerFilter===k?'active':''}" data-f="${k}">${v.emoji} ${v.label}</div>`).join('');
  $$('#pickerChips .chip').forEach(c => c.addEventListener('click', () => { pickerFilter=c.dataset.f; renderPicker(); }));
  const ps = $('#pickerSearch'); if (ps && !ps._bound) { ps._bound = true; ps.addEventListener('input', renderPicker); }
  const q = ($('#pickerSearch').value || '').toLowerCase();
  const list = state.exercises.filter(e => (pickerFilter==='all'||e.muscle===pickerFilter) && (!q || e.name.toLowerCase().includes(q)));
  $('#pickerList').innerHTML = list.map(e => {
    const m=MUSCLES[e.muscle];
    return `<div class="picker-item" data-id="${e.id}">
      <div class="picker-ic">${m.emoji}</div>
      <div class="picker-name">${e.name}</div>
      <div class="picker-sub">${m.label}${e.isBuiltIn?' · 内置':' · 自定义'}</div>
    </div>`;
  }).join('') || `<div class="empty">没有匹配的动作</div>`;
  $$('#pickerList .picker-item').forEach(it => it.addEventListener('click', () => {
    addExerciseToDay(it.dataset.id); $('#pickerMask').hidden = true; toast('已添加到训练');
  }));
}
$('#openPicker').addEventListener('click', openPicker);
$('#pickerClose').addEventListener('click', () => $('#pickerMask').hidden = true);
$('#pickerMask').addEventListener('click', e => { if (e.target.id==='pickerMask') $('#pickerMask').hidden = true; });

/* ---------- 组编辑弹层 ---------- */
let editRef = null;
function openSetSheet(ei, si) {
  const ex = ensureSession().exercises[ei]; const s = ex.sets[si];
  editRef = { ei, si };
  const meta = state.exercises.find(e=>e.id===ex.exerciseId);
  $('#setSheetTitle').textContent = `${meta?meta.name:'动作'} · 第 ${si+1} 组`;
  $('#setWeight').value = s.weight ?? '';
  $('#setReps').value = s.reps ?? '';
  $('#setSide').value = s.side || 'BOTH';
  $('#setRpe').value = s.rpe ?? '';
  $('#setMask').hidden = false;
}
$('#setClose').addEventListener('click', () => $('#setMask').hidden = true);
$('#setMask').addEventListener('click', e => { if (e.target.id==='setMask') $('#setMask').hidden = true; });
$('#setSave').addEventListener('click', () => {
  const { ei, si } = editRef; const s = ensureSession().exercises[ei].sets[si];
  s.weight = parseFloat($('#setWeight').value) || 0;
  s.reps = parseInt($('#setReps').value) || 0;
  s.side = $('#setSide').value;
  s.rpe = parseFloat($('#setRpe').value) || null;
  save(); $('#setMask').hidden = true; renderTrain(); toast('已保存');
});
$('#setDelete').addEventListener('click', () => {
  const { ei, si } = editRef; delSet(ei, si); $('#setMask').hidden = true;
});

/* =========================================================
   动作库
   ========================================================= */
let libFilter = 'all';
function renderLibrary() {
  const chips = $('#libChips');
  chips.innerHTML = `<div class="chip ${libFilter==='all'?'active':''}" data-f="all">全部</div>` +
    Object.entries(MUSCLES).map(([k,v]) => `<div class="chip ${libFilter===k?'active':''}" data-f="${k}">${v.emoji} ${v.label}</div>`).join('');
  $$('#libChips .chip').forEach(c => c.addEventListener('click', () => { libFilter=c.dataset.f; renderLibrary(); }));
  const q = ($('#libSearch').value || '').toLowerCase();
  const list = state.exercises.filter(e => (libFilter==='all'||e.muscle===libFilter) && (!q || e.name.toLowerCase().includes(q)));
  $('#libList').innerHTML = list.map(e => {
    const m=MUSCLES[e.muscle];
    const inToday = state.sessions[todayKey()]?.exercises.some(x=>x.exerciseId===e.id);
    return `<div class="lib-card glass">
      <div class="lib-ic">${m.emoji}</div>
      <div class="lib-meta"><div class="lib-name">${e.name}</div><div class="lib-sub">${m.label} · ${e.isBuiltIn?'内置动作':'自定义'}</div></div>
      ${e.isBuiltIn ? `<div class="lib-tag">${inToday?'今日已练':'未练'}</div>`
                    : `<button class="lib-add" data-delcustom="${e.id}">删除</button>`}
      <button class="lib-add" data-addtoday="${e.id}">＋今天</button>
    </div>`;
  }).join('') + customAddCard();
  $$('[data-addtoday]').forEach(b => b.addEventListener('click', () => { addExerciseToDay(b.dataset.addtoday); toast('已加入今日训练'); }));
  $$('[data-delcustom]').forEach(b => b.addEventListener('click', () => {
    state.exercises = state.exercises.filter(e=>e.id!==b.dataset.delcustom); save(); renderLibrary(); toast('已删除自定义动作');
  }));
  const ca = $('#customAdd');
  if (ca) ca.addEventListener('click', addCustomExercise);
}
function customAddCard() {
  return `<div class="lib-card glass" id="customAdd" style="cursor:pointer;border-style:dashed">
    <div class="lib-ic">➕</div>
    <div class="lib-meta"><div class="lib-name">新增自定义动作</div><div class="lib-sub">名称 + 肌群</div></div>
  </div>`;
}
function addCustomExercise() {
  const name = prompt('动作名称：');
  if (!name) return;
  const mg = prompt('肌群（chest/back/legs/shoulder/arms/core）：', 'chest');
  const muscle = MUSCLES[mg] ? mg : 'arms';
  state.exercises.push({ id:'cx_'+Date.now(), name:name.trim(), muscle, isBuiltIn:false, createdAt:Date.now() });
  save(); renderLibrary(); toast('已添加自定义动作');
}
$('#libSearch').addEventListener('input', () => { if (currentTab==='library') renderLibrary(); else if (!$('#pickerMask').hidden) renderPicker(); });

/* =========================================================
   统计
   ========================================================= */
function buildSeries(exerciseId, rangeDays) {
  const keys = Object.keys(state.sessions).filter(k => {
    if (rangeDays>0) { const d=parseKey(k); const now=new Date(); const diff=(now-d)/86400000; if (diff<0||diff>rangeDays) return false; }
    return state.sessions[k].exercises.some(e=>e.exerciseId===exerciseId);
  }).sort();
  const dates=[], maxW=[], maxR=[], vol=[], rpe=[];
  for (const k of keys) {
    const ex = state.sessions[k].exercises.find(e=>e.exerciseId===exerciseId);
    if (!ex) continue;
    const mw = Math.max(...ex.sets.map(s=>s.weight||0));
    const mr = Math.max(...ex.sets.map(s=>s.reps||0));
    const v = ex.sets.reduce((a,s)=>a+(s.weight||0)*(s.reps||0),0);
    const r = ex.sets.filter(s=>s.rpe).reduce((a,s)=>a+s.rpe,0)/(ex.sets.filter(s=>s.rpe).length||1);
    dates.push(k.slice(5)); maxW.push(+mw.toFixed(1)); maxR.push(mr); vol.push(Math.round(v)); rpe.push(r?+r.toFixed(1):null);
  }
  return { dates, maxW, maxR, vol, rpe };
}
function computePR(exerciseId) {
  let maxW=0, maxWReps=0, maxR=0, maxRWeight=0, volTotal=0, est1RM=0;
  for (const k in state.sessions) {
    const ex = state.sessions[k].exercises.find(e=>e.exerciseId===exerciseId); if (!ex) continue;
    for (const s of ex.sets) {
      const w=s.weight||0, r=s.reps||0; volTotal += w*r;
      if (w>maxW) { maxW=w; maxWReps=r; }
      if (r>maxR) { maxR=r; maxRWeight=w; }
      const e1 = w*(1+r/30); if (e1>est1RM) est1RM=e1;
    }
  }
  return { maxW, maxWReps, maxR, maxRWeight, volTotal:Math.round(volTotal), est1RM:+est1RM.toFixed(1) };
}
function renderStats() {
  const sel = $('#statExercise');
  sel.innerHTML = state.exercises.map(e=>`<option value="${e.id}">${e.name}</option>`).join('');
  if (!sel.value && state.exercises[0]) sel.value = state.exercises[0].id;
  drawAllStats();
}
$('#statExercise').addEventListener('change', drawAllStats);
$('#statRange').addEventListener('change', drawAllStats);
function drawAllStats() {
  const id = $('#statExercise').value; if (!id) return;
  const range = parseInt($('#statRange').value);
  const pr = computePR(id);
  $('#prGrid').innerHTML = `
    <div class="pr-card glass"><div class="pr-num">${fmt(pr.maxW)}<small> kg</small></div><div class="pr-lbl">最大重量 (${pr.maxWReps}次)</div></div>
    <div class="pr-card glass"><div class="pr-num">${pr.maxR}<small> 次</small></div><div class="pr-lbl">最大次数 (${fmt(pr.maxRWeight)}kg)</div></div>
    <div class="pr-card glass"><div class="pr-num">${fmt(pr.est1RM)}<small> kg</small></div><div class="pr-lbl">估算 1RM (Epley)</div></div>
    <div class="pr-card glass"><div class="pr-num">${fmt(pr.volTotal)}<small> kg</small></div><div class="pr-lbl">累计训练容量</div></div>`;
  const s = buildSeries(id, range);
  if (!s.dates.length) {
    $('#prGrid').innerHTML = `<div class="pr-card glass" style="grid-column:1/-1;text-align:center">该动作暂无足够历史数据</div>`;
    ['chartTrend','chartVol','chartRpe'].forEach(c => { const cv=$('#'+c); const ctx=cv.getContext('2d'); ctx.clearRect(0,0,cv.width,cv.height); });
    return;
  }
  drawLine($('#chartTrend'), s.dates, [
    { data: s.maxW, color:'#7aa2ff', label:'最大重量' },
    { data: s.maxR, color:'#ff7bc8', label:'最大次数' },
  ], '');
  drawBar($('#chartVol'), s.dates, s.vol, '#28ffa8');
  drawLine($('#chartRpe'), s.dates, [{ data: s.rpe, color:'#ffb86c', label:'RPE' }], '');
}

/* Canvas 绘图 */
function setupCanvas(cv) {
  const dpr = window.devicePixelRatio || 1;
  const w = cv.clientWidth || 320, h = cv.clientHeight || 200;
  cv.width = w*dpr; cv.height = h*dpr;
  const ctx = cv.getContext('2d'); ctx.scale(dpr,dpr);
  ctx.clearRect(0,0,w,h);
  return { ctx, w, h };
}
function drawLine(cv, labels, series, _u) {
  const { ctx, w, h } = setupCanvas(cv);
  const padL=38, padR=10, padT=14, padB=22;
  const all = series.flatMap(s=>s.data).filter(v=>v!=null);
  const max = Math.max(1, ...all), min = Math.min(0, ...all);
  const X = i => padL + (w-padL-padR) * (i/(Math.max(1,labels.length-1)));
  const Y = v => padT + (h-padT-padB) * (1-(v-min)/(max-min||1));
  // 网格
  ctx.strokeStyle='rgba(255,255,255,.08)'; ctx.lineWidth=1; ctx.font='10px sans-serif'; ctx.fillStyle='rgba(255,255,255,.4)';
  for (let g=0;g<=3;g++){ const y=padT+(h-padT-padB)*g/3; ctx.beginPath(); ctx.moveTo(padL,y); ctx.lineTo(w-padR,y); ctx.stroke();
    ctx.fillText(Math.round(max-(max-min)*g/3), 4, y+3); }
  // 标签
  labels.forEach((l,i)=>{ if(i%Math.ceil(labels.length/6)===0){ ctx.fillText(l, X(i)-8, h-6); } });
  series.forEach(s=>{
    // 面积
    ctx.beginPath(); let started=false;
    s.data.forEach((v,i)=>{ if(v==null){started=false;return;} const x=X(i),y=Y(v); if(!started){ctx.moveTo(x,y);started=true;} else ctx.lineTo(x,y); });
    const grad=ctx.createLinearGradient(0,padT,0,h-padB); grad.addColorStop(0,s.color+'55'); grad.addColorStop(1,s.color+'00');
    ctx.lineTo(X(s.data.length-1),h-padB); ctx.lineTo(X(0),h-padB); ctx.closePath(); ctx.fillStyle=grad; ctx.fill();
    // 线
    ctx.beginPath(); started=false;
    s.data.forEach((v,i)=>{ if(v==null){started=false;return;} const x=X(i),y=Y(v); if(!started){ctx.moveTo(x,y);started=true;} else ctx.lineTo(x,y); });
    ctx.strokeStyle=s.color; ctx.lineWidth=2.2; ctx.lineJoin='round'; ctx.stroke();
    // 点
    s.data.forEach((v,i)=>{ if(v==null)return; ctx.beginPath(); ctx.arc(X(i),Y(v),2.6,0,7); ctx.fillStyle=s.color; ctx.fill(); });
  });
}
function drawBar(cv, labels, data, color) {
  const { ctx, w, h } = setupCanvas(cv);
  const padL=38, padR=10, padT=14, padB=22;
  const max=Math.max(1,...data);
  const bw=Math.max(4,(w-padL-padR)/data.length*0.6);
  ctx.strokeStyle='rgba(255,255,255,.08)'; ctx.lineWidth=1; ctx.font='10px sans-serif'; ctx.fillStyle='rgba(255,255,255,.4)';
  for (let g=0;g<=3;g++){ const y=padT+(h-padT-padB)*g/3; ctx.beginPath(); ctx.moveTo(padL,y); ctx.lineTo(w-padR,y); ctx.stroke();
    ctx.fillText(Math.round(max-(max)*g/3),4,y+3); }
  data.forEach((v,i)=>{ const x=padL+(w-padL-padR)*(i/(Math.max(1,data.length-1)))-(data.length===1?bw/2:0);
    const bh=(h-padT-padB)*(v/max); const y=h-padB-bh;
    ctx.fillStyle=color+'cc'; const r=Math.min(4,bw/2);
    ctx.beginPath(); ctx.roundRect(x-bw/2,y,bw,bh,[r,r,0,0]); ctx.fill(); });
  labels.forEach((l,i)=>{ if(i%Math.ceil(labels.length/6)===0){ ctx.fillText(l, padL+(w-padL-padR)*i/Math.max(1,labels.length-1)-8, h-6); } });
}

/* =========================================================
   设置
   ========================================================= */
function renderSettings() {
  const s = state.settings;
  $('#settingsList').innerHTML = `
    <div class="set-row-card glass">
      <div><div class="lbl">间隔提醒总开关</div><div class="desc">某动作超过阈值未练时提醒</div></div>
      <div class="switch ${s.reminder?'on':''}" data-toggle="reminder"></div>
    </div>
    <div class="set-row-card glass">
      <div><div class="lbl">默认提醒阈值</div><div class="desc">小时（默认 72）</div></div>
      <input type="number" id="setThreshold" value="${s.threshold}" min="1" style="width:80px;padding:10px;border-radius:12px;border:1px solid rgba(255,255,255,.2);background:rgba(255,255,255,.1);color:var(--text);text-align:center;"/>
    </div>
    <div class="set-row-card glass">
      <div><div class="lbl">重量单位</div><div class="desc">当前 ${s.unit==='kg'?'千克 (kg)':'磅 (lb)'}</div></div>
      <div class="switch ${s.unit==='lb'?'on':''}" data-toggle="unit"></div>
    </div>
    <div class="set-row-card glass" style="flex-direction:column;align-items:stretch;gap:8px">
      <div class="lbl">硅基流动 API Key</div>
      <input type="text" id="setApi" value="${s.apiKey||''}" placeholder="留空使用默认 Key" style="padding:11px 13px;border-radius:12px;border:1px solid rgba(255,255,255,.2);background:rgba(255,255,255,.1);color:var(--text);font-size:14px;outline:none;"/>
      <div class="desc">用于语音录入的 ASR / LLM（SenseVoiceSmall + Qwen）</div>
    </div>`;
  $$('[data-toggle]').forEach(t => t.addEventListener('click', () => {
    const k=t.dataset.toggle;
    if (k==='reminder') state.settings.reminder=!state.settings.reminder;
    if (k==='unit') state.settings.unit = state.settings.unit==='kg'?'lb':'kg';
    save(); renderSettings();
  }));
  $('#setThreshold').addEventListener('change', e => { state.settings.threshold=parseInt(e.target.value)||72; save(); toast('已保存阈值'); });
  $('#setApi').addEventListener('change', e => { state.settings.apiKey=e.target.value.trim(); save(); toast('已保存 Key'); });
}
$('#exportBtn').addEventListener('click', () => {
  const blob = new Blob([JSON.stringify(state, null, 2)], { type:'application/json' });
  const a=document.createElement('a'); a.href=URL.createObjectURL(blob);
  a.download=`fitlog-backup-${todayKey()}.json`; a.click(); toast('已导出 JSON');
});
$('#importBtn').addEventListener('click', () => $('#importFile').click());
$('#importFile').addEventListener('change', e => {
  const f=e.target.files[0]; if(!f) return;
  const rd=new FileReader();
  rd.onload=()=>{ try {
    const data=JSON.parse(rd.result);
    if (confirm('导入方式：确定=覆盖，取消=合并')) state=data;
    else { state.exercises=[...state.exercises, ...(data.exercises||[]).filter(x=>!state.exercises.some(y=>y.id===x.id))];
           state.sessions={...state.sessions, ...(data.sessions||{})}; if(data.settings) state.settings={...state.settings,...data.settings}; }
    save(); toast('导入完成'); renderTrain();
  } catch(err){ toast('导入失败：JSON 解析错误'); } };
  rd.readAsText(f);
});

/* =========================================================
   语音录入 FAB（演示：模拟按住说话 → 写入示例组）
   ========================================================= */
const fab=$('#voiceFab');
let recTimer=null;
fab.addEventListener('pointerdown', e=>{ e.preventDefault(); fab.classList.add('recording'); toast('🎙️ 录音中…（演示）'); });
function stopRec(){ if(!fab.classList.contains('recording'))return; fab.classList.remove('recording');
  const s=ensureSession(); if(!s.exercises.length){ s.exercises.push({exerciseId:state.exercises[0].id,sets:[{weight:30,reps:10,side:'BOTH',rpe:8}]}); }
  else { const ex=s.exercises[s.exercises.length-1]; ex.sets.push({weight:30,reps:10,side:'BOTH',rpe:8}); }
  save(); renderTrain(); if(currentTab!=='train') switchTab('train'); toast('语音已解析：+1 组示例数据'); }
fab.addEventListener('pointerup', stopRec);
fab.addEventListener('pointercancel', stopRec);
fab.addEventListener('pointerleave', stopRec);

/* =========================================================
   主题 / 折射 开关 + Toast
   ========================================================= */
$('#themeToggle').addEventListener('click', () => document.body.classList.toggle('light'));
$('#refractToggle').addEventListener('click', () => {
  const off = document.body.classList.toggle('no-refract');
  $('#refractToggle').classList.toggle('on', !off);
  if (!off) applyLiquidGlass();
});
function toast(msg){ const t=$('#toast'); t.textContent=msg; t.hidden=false; clearTimeout(t._t); t._t=setTimeout(()=>t.hidden=true,1800); }

/* =========================================================
   初始化
   ========================================================= */
function init() {
  // 修正 #glassSvg 引用
  let svg=$('#glassSvg'); if(!svg){ svg=document.createElementNS('http://www.w3.org/2000/svg','svg'); svg.id='glassSvg'; svg.setAttribute('width','0'); svg.setAttribute('height','0'); svg.style.position='absolute'; document.body.appendChild(svg); }
  renderTrain();
  // 折射默认开启
  $('#refractToggle').classList.add('on');
  requestAnimationFrame(applyLiquidGlass);
  setTimeout(applyLiquidGlass, 300);
}
init();
