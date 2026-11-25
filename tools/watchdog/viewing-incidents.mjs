// Owner-facing incident policy. Provider metadata, guides, missing catalog rows,
// workflow failures and version drift are diagnostics, never playback proof.
const SCOPES = ['sports', 'cricket'];
const FRESH = 35 * 60_000;
const qualifying = e => e.source === 'fixtures-service' && e.stage === 'integrity'
  && SCOPES.includes(e.scope) && /^http-5\d\d$/.test(e.failureClass);
export function validateViewingState(value = {}) {
  if (!value || typeof value !== 'object' || Array.isArray(value)
    || Object.keys(value).some(k => !SCOPES.includes(k))) throw new Error('Invalid viewing incident state');
  for (const item of Object.values(value)) {
    if (!item || Object.keys(item).some(k => !['open', 'generation', 'members'].includes(k))
      || typeof item.open !== 'boolean' || !Number.isSafeInteger(item.generation) || item.generation < 1
      || !Array.isArray(item.members) || item.members.length > 513
      || new Set(item.members).size !== item.members.length
      || !item.members.every(k => /^[a-f0-9]{64}$/.test(k))) throw new Error('Invalid viewing incident');
  }
  return value;
}
// Input notices have already passed the strict cloud wire/version validation.
// Only a fresh confirmed server response from an app-consumed fixture endpoint
// establishes discovery impact. This never says existing playback has stopped.
export function advanceViewingIncidents(previous = {}, notices, now) {
  const state = structuredClone(validateViewingState(previous)), events = [];
  const latest = new Map();
  for (const e of notices) if (qualifying(e)) latest.set(e.incidentId, e);
  for (const scope of SCOPES) {
    const rows = [...latest.values()].filter(e => e.scope === scope);
    const failed = rows.filter(e => e.type === 'confirmed' && now - Date.parse(e.time) <= FRESH);
    let item = state[scope];
    let type, at;
    if (failed.length) {
      if (!item?.open) {
        item = { open: true, generation: (item?.generation || 0) + 1, members: [] };
        type = 'confirmed'; at = Math.max(...failed.map(e => Date.parse(e.time)));
      }
      item.members = [...new Set([...item.members, ...failed.map(e => e.incidentId)])];
      state[scope] = item;
    } else if (item?.open && item.members.length && item.members.every(id => latest.get(id)?.type === 'resolved')) {
      // Missing/expired/unknown evidence cannot manufacture a recovery.
      const times = item.members.map(id => Date.parse(latest.get(id).time));
      if (now - Math.max(...times) <= FRESH) { item.open = false; type = 'resolved'; at = Math.max(...times); }
    }
    if (type) events.push({ type, source: 'viewing', stage: 'discovery', failureClass: 'fixture-refresh-unavailable',
      scope, generation: item.generation, time: new Date(at).toISOString() });
  }
  return { state: validateViewingState(state), events };
}
