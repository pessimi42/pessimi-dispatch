'use strict';

const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'pessimi42_dispatch';
const post = (name, data = {}) =>
  fetch(`https://${RES}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data),
  }).catch(() => {});

const $ = (sel) => document.querySelector(sel);

const S = {
  dict: {},
  lang: 'en',
  languages: [],
  services: [],
  priorities: [],
  statuses: [],
  hud: true,
  role: { dispatcher: false, service: null },
  calls: new Map(),
  units: new Map(),
  selected: null,
  filter: 'all',
  showClosed: false,
  myCall: null,
  myStatus: null,
  callerService: null,
  closeArmed: null,
  sms: false,
  quickReplies: [],
  aiServices: [],
  aiOnlyWhenNoneOnDuty: true,
  aiCalls: false,
  canToggleAiCalls: false,
  fallbackService: 'police',
};

/* ---------- i18n ---------- */
const t = (key, vars) => {
  let s = S.dict[key] ?? key;
  if (vars) s = s.replace(/\{(\w+)\}/g, (m, k) => (vars[k] ?? m));
  return s;
};
const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

function applyStaticText() {
  document.querySelectorAll('[data-i18n]').forEach((el) => { el.textContent = t(el.dataset.i18n); });
  $('#callerMsg').placeholder = t('caller.describe');
}

/* ---------- lookups ---------- */
const svc = (id) => S.services.find((s) => s.id === id);
const svcColor = (id) => svc(id)?.color || '#8b95a3';
const svcName = (id) => (id ? t(`service.${id}`) : t('ui.unspecified'));
const prio = (id) => S.priorities.find((p) => p.id === id);
const prioIndex = (id) => { const i = S.priorities.findIndex((p) => p.id === id); return i < 0 ? 99 : i; };
const status = (id) => S.statuses.find((s) => s.id === id);
const unitLabel = (u) => u.callsign || u.name || `#${u.src}`;

function ago(epoch) {
  const s = Math.max(0, Math.floor(Date.now() / 1000 - epoch));
  if (s < 60) return t('ui.ago_now');
  if (s < 3600) return t('ui.ago_m', { n: Math.floor(s / 60) });
  return t('ui.ago_h', { n: Math.floor(s / 3600) });
}
const clock = (epoch) => new Date(epoch * 1000).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });

function typesFor(serviceId) {
  if (serviceId) return svc(serviceId)?.callTypes || ['general'];
  const all = new Set(['general']);
  S.services.forEach((s) => s.callTypes.forEach((x) => all.add(x)));
  return [...all];
}

const options = (items, selected) =>
  items.map(([v, label]) => `<option value="${esc(v)}" ${v === selected ? 'selected' : ''}>${esc(label)}</option>`).join('');

/* ---------- actions ---------- */
const action = (type, payload) => post('action', { type, payload });

/* ---------- rendering: filters ---------- */
function renderFilters() {
  const btn = (id, label, color) =>
    `<button class="chip ${S.filter === id ? 'on' : ''}" data-filter="${esc(id)}" style="${color ? `--svc:${color}` : ''}">${esc(label)}</button>`;
  $('#serviceFilters').innerHTML =
    btn('all', t('ui.all')) +
    S.services.map((s) => btn(s.id, svcName(s.id), s.color)).join('') +
    btn('none', t('ui.unspecified'));
  $('#historyToggle').classList.toggle('on', S.showClosed);

  const ai = $('#aiCallsBtn');
  ai.classList.toggle('hidden', !S.canToggleAiCalls);
  ai.classList.toggle('on', S.aiCalls);
  ai.textContent = `${t('ui.ai_calls')}: ${t(S.aiCalls ? 'ui.on' : 'ui.off')}`;

  const sel = $('#langSelect');
  sel.classList.toggle('hidden', S.languages.length < 2);
  sel.innerHTML = options(S.languages.map((l) => [l.code, l.name]), S.lang);
}

/* ---------- rendering: call list ---------- */
function visibleCalls() {
  return [...S.calls.values()]
    .filter((c) => (S.showClosed ? c.status === 'closed' : c.status !== 'closed'))
    .filter((c) => S.filter === 'all' || (S.filter === 'none' ? !c.service : c.service === S.filter))
    .sort((a, b) => S.showClosed
      ? b.closedAt - a.closedAt
      : prioIndex(a.priority) - prioIndex(b.priority) || b.createdAt - a.createdAt);
}

function renderCalls() {
  const list = visibleCalls();
  if (!list.length) {
    $('#callList').innerHTML = `<div class="empty">${esc(t('ui.no_calls'))}</div>`;
    return;
  }
  $('#callList').innerHTML = list.map((c) => `
    <div class="call ${c.id === S.selected ? 'sel' : ''} ${c.status === 'closed' ? 'closed' : ''}"
         data-call="${c.id}" style="--svc:${svcColor(c.service)}">
      <div class="prio" style="--p:${prio(c.priority)?.color || '#888'}">${esc(c.priority)}</div>
      <div>
        <div class="top">
          <span class="title">#${c.id} ${esc(t(`calltype.${c.type}`))}</span>
          <span class="tag">${c.aiCall ? `${esc(t('ui.ai_badge'))} · ` : ''}${esc(t(`call_status.${c.status}`))}</span>
        </div>
        <div class="sub">${esc(c.street || t('ui.unknown_location'))}</div>
        <div class="sub">${esc(svcName(c.service))} · ${esc(ago(c.createdAt))}${c.units.length ? ' · ' + esc(t('ui.units_count', { n: c.units.length })) : ''}</div>
      </div>
    </div>`).join('');
}

/* ---------- rendering: detail ---------- */
function renderDetail() {
  const el = $('#callDetail');
  const c = S.calls.get(S.selected);
  if (!c) { el.innerHTML = `<div class="empty">${esc(t('ui.select_call'))}</div>`; return; }
  const closed = c.status === 'closed';
  const dis = closed ? 'disabled' : '';

  const aiFor = c.service || (S.aiServices.includes(S.fallbackService) ? S.fallbackService : null);
  const aiBusy = (c.ai || []).some((a) => a.status === 'enroute' || a.status === 'onscene');
  const playersOnDuty = [...S.units.values()].some((u) => u.service === aiFor);
  const canAi = !closed && c.coords && aiFor && S.aiServices.includes(aiFor) && !aiBusy
    && !(S.aiOnlyWhenNoneOnDuty && playersOnDuty);
  const aiUnits = (c.ai || []).map((a) =>
    `<span class="u ai">${esc(t('ui.ai_unit'))} · ${esc(svcName(a.service))} · ${esc(t(`ai_status.${a.status}`))}</span>`).join('');

  const units = c.units.map((src) => {
    const u = S.units.get(src);
    return `<span class="u">${esc(u ? unitLabel(u) : `#${src}`)}
      ${closed ? '' : `<button data-unassign="${src}">${esc(t('ui.unassign'))}</button>`}</span>`;
  }).join('');

  const notes = (c.notes || []).map((n) => {
    const label = n.kind === 'sms_out' ? `${t('ui.sms_out')} · ` : n.kind === 'sms_in' ? `${t('ui.sms_in')} · ` : '';
    const text = (n.kind === 'ai' || n.kind === 'sys') ? t(n.text) : n.text;
    const author = n.kind === 'ai' ? t('ui.ai_unit') : n.kind === 'sys' ? t('ui.system') : (n.author || '');
    return `<div class="note ${esc(n.kind || '')}">${esc(text)}<small>${esc(label)}${esc(author)} · ${clock(n.at)}</small></div>`;
  }).join('');

  const sms = c.canSms ? `
    <label>${esc(t('ui.sms'))} · ${esc(c.caller.phone)}</label>
    <div class="sms-quick">${S.quickReplies.map((k) =>
      `<button class="chip" data-sms-key="${esc(k)}" title="${esc(t(`sms.quick.${k}`, { id: c.id }))}">${esc(t(`sms.label.${k}`))}</button>`).join('')}</div>
    <div class="note-add">
      <input id="smsInput" maxlength="250" placeholder="${esc(t('ui.sms_placeholder'))}">
      <button id="smsSend">${esc(t('ui.send'))}</button></div>` : '';

  el.innerHTML = `
    <div class="d-head">
      <div class="prio" style="--p:${prio(c.priority)?.color || '#888'}">${esc(c.priority)}</div>
      <h1>#${c.id} ${esc(t(`calltype.${c.type}`))}</h1>
      <span class="tag">${esc(t(`call_status.${c.status}`))}</span>
      ${c.code ? `<span class="tag">${esc(c.code)}</span>` : ''}
    </div>

    <div class="d-grid">
      <div><label>${esc(t('ui.service'))}</label>
        <select data-patch="service" ${dis}>${options([['', t('ui.unspecified')], ...S.services.map((s) => [s.id, svcName(s.id)])], c.service || '')}</select></div>
      <div><label>${esc(t('ui.type'))}</label>
        <select data-patch="type" ${dis}>${options(typesFor(c.service).map((x) => [x, t(`calltype.${x}`)]), c.type)}</select></div>
      <div><label>${esc(t('ui.priority'))}</label>
        <select data-patch="priority" ${dis}>${options(S.priorities.map((p) => [p.id, t(`priority.${p.id}`)]), c.priority)}</select></div>
    </div>

    <label>${esc(t('ui.message'))}</label>
    <div class="d-msg">${esc(c.message || '—')}</div>

    <dl class="d-meta">
      <dt>${esc(t('ui.location'))}</dt><dd>${esc(c.street || t('ui.unknown_location'))}${
        c.tracking ? ` <span class="tag live">${esc(t('ui.tracking'))}</span>` : ''}${
        c.locatedAt ? ` <span class="hint">· ${esc(t('ui.located', { ago: ago(c.locatedAt) }))}</span>` : ''}</dd>
      <dt>${esc(t('ui.caller'))}</dt><dd>${esc(c.caller?.name || t('ui.unknown'))}${c.caller?.phone ? ' · ' + esc(c.caller.phone) : ''}</dd>
      <dt>${esc(t('ui.origin'))}</dt><dd>${esc(t(`origin.${c.origin}`) === `origin.${c.origin}` ? c.origin : t(`origin.${c.origin}`))}</dd>
      <dt>${esc(t('ui.received'))}</dt><dd>${clock(c.createdAt)} (${esc(ago(c.createdAt))})</dd>
      ${c.information ? `<dt>${esc(t('ui.information'))}</dt><dd>${esc(c.information)}</dd>` : ''}
    </dl>

    <label>${esc(t('ui.assigned_units'))}</label>
    <div class="assigned">${units + aiUnits || `<span class="hint">${esc(t('ui.no_assigned'))}</span>`}</div>

    ${sms}

    <label>${esc(t('ui.notes'))}</label>
    <div class="notes">${notes}</div>
    ${closed ? '' : `<div class="note-add">
      <input id="noteInput" maxlength="300" placeholder="${esc(t('ui.add_note'))}">
      <button id="noteAdd">${esc(t('ui.add'))}</button></div>`}

    <div class="d-actions">
      ${c.coords ? `<button data-act="waypoint">${esc(t('ui.waypoint'))}</button>` : ''}
      ${c.canLocate ? `<button data-act="locate">${esc(t('ui.locate'))}</button>` : ''}
      ${canAi ? `<button data-act="sendAi">${esc(t('ui.send_ai'))}</button>` : ''}
      ${closed ? '' : `<button data-act="broadcast">${esc(t('ui.broadcast'))}</button>
      <button data-act="close" class="${S.closeArmed === c.id ? 'danger' : 'warn'}">
        ${esc(S.closeArmed === c.id ? t('ui.confirm_close') : t('ui.close_call'))}</button>`}
    </div>`;
}

/* ---------- rendering: units ---------- */
function renderUnits() {
  const el = $('#unitList');
  if (!S.units.size) { el.innerHTML = `<div class="empty">${esc(t('ui.no_units'))}</div>`; return; }
  const sel = S.calls.get(S.selected);
  const canAssign = sel && sel.status !== 'closed';
  const statusOrder = (id) => S.statuses.findIndex((s) => s.id === id);

  el.innerHTML = S.services.map((s) => {
    const units = [...S.units.values()].filter((u) => u.service === s.id)
      .sort((a, b) => statusOrder(a.status) - statusOrder(b.status) || unitLabel(a).localeCompare(unitLabel(b)));
    if (!units.length) return '';
    return `<div class="svc-group" style="--svc:${s.color}">
      <h3><span>${esc(svcName(s.id))}</span><span>${units.length}</span></h3>
      ${units.map((u) => `
        <div class="unit" style="--st:${status(u.status)?.color || '#555'}">
          <div><div class="cs">${esc(u.callsign || t('ui.callsign_missing'))}</div><div class="nm">${esc(u.name)}${u.gradeLabel ? ' · ' + esc(u.gradeLabel) : ''}</div></div>
          <select data-unit-status="${u.src}">${options(S.statuses.map((x) => [x.id, t(`unit_status.${x.id}`)]), u.status)}</select>
          <div class="bottom">
            <span class="oncall">${u.call ? '#' + u.call : ''}</span>
            ${canAssign && !sel.units.includes(u.src) ? `<button class="chip" data-assign="${u.src}">${esc(t('ui.assign'))}</button>` : ''}
          </div>
        </div>`).join('')}
    </div>`;
  }).join('');
}

function renderPanel() { renderFilters(); renderCalls(); renderDetail(); renderUnits(); }

/* ---------- caller form ---------- */
function openCaller() {
  S.callerService = null;
  $('#callerMsg').value = '';
  const btn = (id, label, color) =>
    `<button data-svc="${esc(id)}" class="${S.callerService === id ? 'on' : ''}" style="${color ? `--svc:${color}` : ''}">${esc(label)}</button>`;
  $('#callerServices').innerHTML =
    S.services.map((s) => btn(s.id, svcName(s.id), s.color)).join('') + btn('', t('caller.not_sure'));
  $('#callerServices').querySelector('[data-svc=""]').classList.add('on');
  $('#caller').classList.remove('hidden');
  setTimeout(() => $('#callerMsg').focus(), 50);
}

/* ---------- new call modal ---------- */
function openNewCall() {
  const svcSel = $('#ncService');
  svcSel.innerHTML = options([['', t('ui.unspecified')], ...S.services.map((s) => [s.id, svcName(s.id)])], S.filter !== 'all' && S.filter !== 'none' ? S.filter : '');
  $('#ncPriority').innerHTML = options(S.priorities.map((p) => [p.id, t(`priority.${p.id}`)]), S.priorities[2]?.id);
  fillNcTypes();
  $('#ncMessage').value = '';
  $('#newCall').classList.remove('hidden');
}
function fillNcTypes() {
  $('#ncType').innerHTML = options(typesFor($('#ncService').value).map((x) => [x, t(`calltype.${x}`)]), 'general');
}

/* ---------- toasts ---------- */
function toast({ kind, call, respondCmd }) {
  const title = { newCall: 'toast.new_call', assigned: 'toast.assigned', broadcast: 'toast.broadcast' }[kind];
  if (!title || !call) return;
  const el = document.createElement('div');
  el.className = 'toast';
  el.style.setProperty('--p', prio(call.priority)?.color || '#f2c14e');
  el.innerHTML = `
    <b>${esc(t(title, { id: call.id }))} · ${esc(call.priority)}</b>
    <div>${esc(t(`calltype.${call.type}`))} – ${esc(svcName(call.service))}</div>
    <div class="sub">${esc(call.street || t('ui.unknown_location'))}</div>
    ${call.message ? `<div class="sub">${esc(call.message.slice(0, 120))}</div>` : ''}
    ${kind === 'broadcast' ? `<div class="hint">${esc(t('toast.respond_hint', { cmd: respondCmd, id: call.id }))}</div>` : ''}`;
  $('#toasts').prepend(el);
  while ($('#toasts').children.length > 4) $('#toasts').lastChild.remove();
  setTimeout(() => { el.classList.add('out'); setTimeout(() => el.remove(), 300); }, kind === 'newCall' ? 8000 : 12000);
}

/* ---------- unit HUD ---------- */
function renderHud() {
  const hud = $('#hud');
  if (!S.hud || !S.role.service || !S.myStatus) { hud.classList.add('hidden'); return; }
  const st = status(S.myStatus);
  hud.style.setProperty('--st', st?.color || '#555');
  const c = S.myCall;
  hud.innerHTML = `
    <div><span class="st">${esc(t(`unit_status.${S.myStatus}`))}</span>${st?.code ? ` <span class="tag">${esc(st.code)}</span>` : ''}
      ${S.myCallsign ? ` · ${esc(S.myCallsign)}` : ''}</div>
    ${c ? `<div class="call" style="--svc:${svcColor(c.service)}">
      <b>#${c.id} ${esc(t(`calltype.${c.type}`))} · ${esc(c.priority)}</b>
      <div class="sub">${esc(c.street || t('ui.unknown_location'))}</div>
      ${c.message ? `<div class="sub">${esc(c.message.slice(0, 90))}</div>` : ''}</div>` : ''}`;
  hud.classList.remove('hidden');
}

/* ---------- UI events ---------- */
function closeAll() {
  $('#panel').classList.add('hidden');
  $('#caller').classList.add('hidden');
  $('#newCall').classList.add('hidden');
  post('close');
}

document.addEventListener('click', (e) => {
  const el = e.target.closest('button, .call[data-call]');
  if (!el) return;
  const c = S.calls.get(S.selected);

  if (el.dataset.call) { S.selected = Number(el.dataset.call); S.closeArmed = null; renderCalls(); renderDetail(); renderUnits(); return; }
  if (el.dataset.filter) { S.filter = el.dataset.filter; renderFilters(); renderCalls(); return; }
  if (el.dataset.assign && c) return action('assign', { callId: c.id, unit: Number(el.dataset.assign) });
  if (el.dataset.unassign && c) return action('unassign', { callId: c.id, unit: Number(el.dataset.unassign) });
  if (el.dataset.smsKey && c) return action('sms', { callId: c.id, key: el.dataset.smsKey });
  if (el.dataset.svc !== undefined) {
    S.callerService = el.dataset.svc || null;
    $('#callerServices').querySelectorAll('button').forEach((b) => b.classList.toggle('on', b === el));
    return;
  }
  if (el.hasAttribute('data-close')) return closeAll();

  switch (el.dataset.act || el.id) {
    case 'closeBtn': return closeAll();
    case 'aiCallsBtn': return post('toggleAiCalls', { state: !S.aiCalls });
    case 'historyToggle': S.showClosed = !S.showClosed; renderFilters(); renderCalls(); return;
    case 'newCallBtn': return openNewCall();
    case 'waypoint': return c && action('waypoint', c.coords);
    case 'broadcast': return c && action('broadcast', { callId: c.id });
    case 'sendAi': return c && action('sendAi', { callId: c.id });
    case 'locate': return c && action('locate', { callId: c.id });
    case 'close':
      if (!c) return;
      if (S.closeArmed === c.id) { S.closeArmed = null; action('close', { callId: c.id }); }
      else { S.closeArmed = c.id; renderDetail(); setTimeout(() => { if (S.closeArmed === c.id) { S.closeArmed = null; renderDetail(); } }, 3000); }
      return;
    case 'smsSend': {
      const v = $('#smsInput').value.trim();
      if (v && c) { action('sms', { callId: c.id, text: v }); $('#smsInput').value = ''; }
      return;
    }
    case 'noteAdd': {
      const v = $('#noteInput').value.trim();
      if (v && c) { action('note', { callId: c.id, text: v }); $('#noteInput').value = ''; }
      return;
    }
    case 'callerSend': {
      const msg = $('#callerMsg').value.trim();
      if (!msg) return $('#callerMsg').focus();
      $('#caller').classList.add('hidden');
      return post('emergencyCall', { service: S.callerService, message: msg });
    }
    case 'ncCreate':
      $('#newCall').classList.add('hidden');
      return action('createCall', {
        service: $('#ncService').value || null,
        type: $('#ncType').value,
        priority: $('#ncPriority').value,
        message: $('#ncMessage').value.trim(),
      });
  }
});

document.addEventListener('change', (e) => {
  const el = e.target;
  const c = S.calls.get(S.selected);
  if (el.dataset.patch && c) return action('update', { callId: c.id, patch: { [el.dataset.patch]: el.value || false } });
  if (el.dataset.unitStatus) return action('unitStatus', { unit: Number(el.dataset.unitStatus), status: el.value });
  if (el.id === 'ncService') return fillNcTypes();
  if (el.id === 'langSelect') return post('setLanguage', { lang: el.value });
});

document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') {
    if (!$('#newCall').classList.contains('hidden')) { $('#newCall').classList.add('hidden'); return; }
    closeAll();
  }
  if (e.key === 'Enter' && e.target.id === 'noteInput') $('#noteAdd').click();
  if (e.key === 'Enter' && e.target.id === 'smsInput') $('#smsSend').click();
  if (e.key === 'Enter' && e.target.id === 'callerMsg' && !e.shiftKey) { e.preventDefault(); $('#callerSend').click(); }
});

/* ---------- messages from Lua ---------- */
const handlers = {
  init(d) {
    S.dict = d.locale; S.lang = d.lang; S.languages = d.languages || [];
    S.services = d.services; S.priorities = d.priorities; S.statuses = d.statuses;
    S.hud = d.hud; S.role = d.role || S.role; S.quickReplies = d.quickReplies || [];
    S.aiServices = d.aiServices || []; S.fallbackService = d.fallbackService || S.fallbackService;
    S.aiOnlyWhenNoneOnDuty = d.aiOnlyWhenNoneOnDuty !== false;
    applyStaticText(); renderPanel(); renderHud();
  },
  locale(d) { S.dict = d.locale; S.lang = d.lang; applyStaticText(); renderPanel(); renderHud(); },
  role(r) {
    S.role = r;
    if (!r.dispatcher) { S.calls.clear(); S.units.clear(); S.selected = null; }
    if (!r.service) { S.myCall = null; S.myStatus = null; }
    renderHud();
  },
  openPanel() { $('#panel').classList.remove('hidden'); renderPanel(); },
  closePanel() { $('#panel').classList.add('hidden'); $('#newCall').classList.add('hidden'); },
  openCaller,
  state(st) {
    S.calls = new Map(st.calls.map((c) => [c.id, c]));
    S.units = new Map(st.units.map((u) => [u.src, u]));
    S.sms = !!st.sms;
    S.aiCalls = !!st.aiCalls; S.canToggleAiCalls = !!st.canToggleAiCalls;
    if (!S.calls.has(S.selected)) S.selected = null;
    renderPanel();
  },
  callChanged({ call }) { S.calls.set(call.id, call); renderCalls(); renderUnits(); if (call.id === S.selected) renderDetail(); },
  unitChanged(u) { S.units.set(u.src, u); renderUnits(); if (S.selected) renderDetail(); },
  unitRemoved(src) { S.units.delete(src); renderUnits(); },
  aiCallsState(state) { S.aiCalls = !!state; renderFilters(); },
  myCall(c) { S.myCall = c; renderHud(); },
  myStatus(d) { S.myStatus = d.status; S.myCallsign = d.callsign; renderHud(); },
  toast,
};

window.addEventListener('message', (e) => {
  const { action: name, data } = e.data || {};
  if (handlers[name]) handlers[name](data);
});

// Refresh "x min ago" labels
setInterval(() => { if (!$('#panel').classList.contains('hidden')) renderCalls(); }, 20000);

post('uiReady');
