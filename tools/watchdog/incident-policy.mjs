// Portable, deterministic policy only: no network, filesystem, secrets or actions.
// This module may be tested offline or hosted in transactional Durable Object storage.
const OUTCOMES = new Set(['failure', 'success', 'unknown', 'inactive']);
const STATES = new Set(['suspect', 'confirmed', 'repairing', 'recovering', 'resolved']);
const REVISION_FIELDS = ['observerRevision', 'configurationRevision', 'deploymentRevision'];
const FACT_KEYS = new Set(['status', 'code', 'scope', 'competition', 'fixtureHash', 'factHash',
  'phase', 'expected', 'actual', 'kind', 'coverage', 'condition', 'dimension', 'publisher',
  'identityHash', 'reason', 'referenceHash']);
const bytes = value => new TextEncoder().encode(JSON.stringify(value)).length;
const copy = value => JSON.parse(JSON.stringify(value));
const iso = value => new Date(value).toISOString();
const RECORD_FIELDS = new Set(['key', 'environment', 'source', 'stage', 'failureClass', 'facts', 'state',
  'generation', 'firstFailureAt', 'lastFailureAt', 'failureCount', 'successCount', 'expected',
  'firstEvidenceHash', 'lastEvidenceHash', 'lastWindow', 'lastOutcome', 'confirmedAt', 'quarantined',
  'lastSuccessAt', 'resolvedAt']);
function onlyFields(value, fields, label) {
  if (!value || typeof value !== 'object' || Array.isArray(value) || Object.keys(value).some(key => !fields.has(key))) throw new Error(`Invalid ${label} fields`);
}
function timestamp(value, name) {
  if (typeof value !== 'number' && (typeof value !== 'string' || value.length > 40
      || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?(?:Z|[+-]\d{2}:\d{2})$/.test(value))) throw new Error(`Invalid ${name}`);
  const result = typeof value === 'number' ? value : Date.parse(value);
  if (!Number.isSafeInteger(result) || result < 0) throw new Error(`Invalid ${name}`);
  return result;
}
function identifier(value, name, maximum = 64) {
  if (typeof value !== 'string' || value.length > maximum || !/^[A-Za-z0-9][A-Za-z0-9_.:-]*$/.test(value)
      || /(?:bearer|password|cookie|authorization|token=)/i.test(value)) throw new Error(`Invalid ${name}`);
  return value;
}
function revisions(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Missing revisions');
  onlyFields(value, new Set(REVISION_FIELDS), 'revision');
  return Object.fromEntries(REVISION_FIELDS.map(name => [name, identifier(value[name], name)]));
}
export function sameRevisions(left, right) {
  return REVISION_FIELDS.every(name => left?.[name] === right?.[name]);
}
export function normalizeFacts(value = {}) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Invalid facts');
  const normalized = {};
  for (const name of Object.keys(value).sort()) {
    if (!FACT_KEYS.has(name)) throw new Error('Unreviewed fact field; use a reviewed scalar or injected fact hash');
    const item = value[name];
    if (typeof item === 'string') normalized[name] = identifier(item, 'fact value', 96).toLowerCase();
    else if (item === null || typeof item === 'boolean') normalized[name] = item;
    else if (Number.isSafeInteger(item)) normalized[name] = item;
    else throw new Error('Invalid fact scalar');
  }
  if (bytes(normalized) > 384) throw new Error('Facts exceed budget');
  return normalized;
}
export function incidentKey(receipt) {
  // Version, changing observation time and attempt/build IDs deliberately are NOT in this key.
  return JSON.stringify([identifier(receipt.environment, 'environment'), identifier(receipt.source, 'source'),
    identifier(receipt.stage, 'stage'), identifier(receipt.failureClass, 'failure class'), normalizeFacts(receipt.facts)]);
}
export function createPolicy(options) {
  const environment = identifier(options.environment, 'environment');
  const limits = { active: 128, resolved: 256, outbox: 512, recordBytes: 2048, ledgerBytes: 1048576,
    resolvedAgeMs: 30 * 86400000, ...(options.limits || {}) };
  for (const [key, value] of Object.entries(limits)) {
    if (!Number.isSafeInteger(value) || value < 1) throw new Error(`Invalid limit ${key}`);
  }
  // Caller may lower ceilings for qualification but cannot silently expand them.
  if (limits.active > 128 || limits.resolved > 256 || limits.outbox > 512 || limits.recordBytes > 2048
      || limits.ledgerBytes > 1048576 || limits.resolvedAgeMs > 30 * 86400000) throw new Error('Limit expansion requires review');
  const sources = {};
  if (!Array.isArray(options.admittedSources) || options.admittedSources.length > 64) throw new Error('Invalid source admission');
  for (const entry of options.admittedSources) {
    const source = identifier(entry.source, 'source');
    if (sources[source] || !Array.isArray(entry.stages) || !entry.stages.length || entry.stages.length > 16) throw new Error('Duplicate/invalid source admission');
    const stages = entry.stages.map(stage => identifier(stage, 'stage'));
    if (new Set(stages).size !== stages.length) throw new Error('Duplicate stage');
    if (!['active', 'inactive', 'deferred', 'off-season'].includes(entry.activation)) throw new Error('Invalid activation');
    sources[source] = { stages, activation: entry.activation, expected: revisions(entry.expected) };
  }
  const policy = { environment, sources, limits, windowMs: options.windowMs ?? 300000,
    failureWindows: options.failureWindows ?? 3, recoveryWindows: options.recoveryWindows ?? 2,
    maxReceiptAgeMs: options.maxReceiptAgeMs ?? 600000, futureGraceMs: options.futureGraceMs ?? 30000,
    maxLeaseMs: options.maxLeaseMs ?? 300000 };
  for (const key of ['windowMs', 'failureWindows', 'recoveryWindows', 'maxReceiptAgeMs', 'futureGraceMs', 'maxLeaseMs']) {
    if (!Number.isSafeInteger(policy[key]) || policy[key] < 1) throw new Error(`Invalid policy ${key}`);
  }
  if (policy.maxLeaseMs > 300000) throw new Error('Lease expansion requires review');
  return policy;
}
export function emptyLedger(policy) {
  return { schema: 1, environment: policy.environment, revision: 0, repairFence: 0,
    notificationSequence: 0, outbox: [], lease: null, incidents: {}, coverage: {}, overflow: null };
}
export function validateLedger(state, policy, previous) {
  onlyFields(state, new Set(['schema', 'environment', 'revision', 'repairFence', 'notificationSequence', 'outbox', 'lease', 'incidents', 'coverage', 'overflow']), 'ledger');
  if (state?.schema !== 1 || state.environment !== policy.environment || !Number.isSafeInteger(state.revision)
      || state.revision < 0 || !Number.isSafeInteger(state.repairFence) || state.repairFence < 0
      || !Number.isSafeInteger(state.notificationSequence) || state.notificationSequence < 0
      || !Array.isArray(state.outbox) || state.outbox.length > policy.limits.outbox
      || !state.incidents || !state.coverage || typeof state.incidents !== 'object' || typeof state.coverage !== 'object'
      || Array.isArray(state.incidents) || Array.isArray(state.coverage)
      || (state.lease !== null && (typeof state.lease !== 'object' || Array.isArray(state.lease)))
      || (state.overflow !== null && (typeof state.overflow !== 'object' || Array.isArray(state.overflow)))) throw new Error('Invalid ledger');
  let active = 0, resolved = 0;
  for (const [key, record] of Object.entries(state.incidents)) {
    onlyFields(record, RECORD_FIELDS, 'incident');
    if (!STATES.has(record.state) || record.key !== key || incidentKey(record) !== key || bytes(record) > policy.limits.recordBytes) throw new Error('Invalid/oversize incident');
    if (record.environment !== policy.environment || !policy.sources[record.source]?.stages.includes(record.stage)) throw new Error('Unadmitted persisted incident');
    if (JSON.stringify(record.facts) !== JSON.stringify(normalizeFacts(record.facts))) throw new Error('Unnormalized persisted facts');
    revisions(record.expected);
    if (record.state === 'resolved') resolved++; else active++;
    for (const field of ['failureCount', 'successCount', 'generation']) {
      if (!Number.isSafeInteger(record[field]) || record[field] < 0) throw new Error('Invalid incident counter');
    }
    if (record.failureCount > policy.failureWindows || record.successCount > policy.recoveryWindows || record.generation < 1
        || (record.lastWindow != null && (!Number.isSafeInteger(record.lastWindow) || record.lastWindow < 0))
        || (record.lastOutcome != null && !OUTCOMES.has(record.lastOutcome))) throw new Error('Invalid bounded incident state');
    for (const field of ['firstFailureAt', 'lastFailureAt', 'confirmedAt', 'lastSuccessAt', 'resolvedAt']) {
      if (record[field] != null) timestamp(record[field], field);
    }
    if (record.firstFailureAt == null || record.lastFailureAt == null || (record.state === 'resolved' && record.resolvedAt == null)) throw new Error('Missing incident receipt');
    for (const field of ['firstEvidenceHash', 'lastEvidenceHash']) {
      if (record[field] != null && !/^[a-f0-9]{64}$/.test(record[field])) throw new Error('Invalid persisted hash');
    }
    if (record.quarantined != null && typeof record.quarantined !== 'boolean') throw new Error('Invalid quarantine');
  }
  if (active > policy.limits.active || resolved > policy.limits.resolved || bytes(state) > policy.limits.ledgerBytes) throw new Error('Ledger capacity exceeded');
  for (const [key, coverage] of Object.entries(state.coverage)) {
    onlyFields(coverage, new Set(['source', 'stage', 'observedAt', 'outcome', 'activation', 'versions', 'versionMatches', 'checkedAt', 'acceptedAt', 'lastHeartbeatAt']), 'coverage');
    const admitted = policy.sources[coverage.source];
    if (!admitted?.stages.includes(coverage.stage) || key !== `${coverage.source}/${coverage.stage}` || bytes(coverage) > 1024) throw new Error('Invalid coverage');
    if (!OUTCOMES.has(coverage.outcome) || !['active', 'inactive', 'deferred', 'off-season'].includes(coverage.activation)
        || typeof coverage.versionMatches !== 'boolean') throw new Error('Invalid coverage state');
    revisions(coverage.versions); timestamp(coverage.observedAt, 'coverage observation');
    for (const field of ['checkedAt', 'acceptedAt', 'lastHeartbeatAt']) if (coverage[field] != null) timestamp(coverage[field], field);
  }
  if (state.lease) {
    const lease = state.lease;
    onlyFields(lease, new Set(['incidentKey', 'owner', 'baseRevision', 'token', 'expiresAt']), 'lease');
    if (!state.incidents[lease.incidentKey] || !Number.isSafeInteger(lease.token) || lease.token < 1
        || lease.token > state.repairFence) throw new Error('Invalid repair lease');
    identifier(lease.owner, 'lease owner'); identifier(lease.baseRevision, 'base revision');
    timestamp(lease.expiresAt, 'lease expiry');
  }
  if (state.overflow) {
    onlyFields(state.overflow, new Set(['since', 'reason', 'notice']), 'overflow');
    timestamp(state.overflow.since, 'overflow time');
    if (!['active_capacity', 'storage_capacity', 'outbox_capacity'].includes(state.overflow.reason)) throw new Error('Invalid overflow reason');
    validateNotification(state.overflow.notice, state, policy, true);
  }
  let lastSequence = 0;
  const sequences = new Set();
  for (const event of state.outbox) {
    const sequence = validateNotification(event, state, policy);
    if (sequence <= lastSequence) throw new Error('Duplicate/regressed notification sequence');
    lastSequence = sequence;
    sequences.add(sequence);
  }
  if (state.overflow) {
    const sequence = validateNotification(state.overflow.notice, state, policy, true);
    if (sequences.has(sequence)) throw new Error('Duplicate capacity notification');
    sequences.add(sequence);
  }
  if (sequences.size !== state.notificationSequence || (sequences.size && Math.max(...sequences) !== state.notificationSequence)) throw new Error('Missing notification history');
  if (previous) {
    if (state.repairFence < previous.repairFence || state.notificationSequence < previous.notificationSequence) throw new Error('Fencing token cannot regress');
    for (const [key, incident] of Object.entries(previous.incidents)) {
      if (incident.state !== 'resolved' && !state.incidents[key]) throw new Error('Active incident cannot be erased');
    }
    // Delivery is not knowable from this offline engine or read-only status
    // collector. Never discard unacknowledged events merely because they age.
    for (const event of previous.outbox) {
      if (!state.outbox.some(current => current.id === event.id && JSON.stringify(current) === JSON.stringify(event))) throw new Error('Undelivered notification cannot be erased or changed');
    }
    if (previous.overflow && JSON.stringify(previous.overflow) !== JSON.stringify(state.overflow)) throw new Error('Capacity degradation is sticky');
  }
  return state;
}
function compactResolved(state, policy, now, previous) {
  // A just-resolved active incident cannot disappear in the same transaction;
  // its transition and notification must first be durably committed. Likewise,
  // an outstanding lease remains referentially valid until exact-owned cleanup.
  const protectedKeys = new Set(Object.entries(previous?.incidents ?? {})
    .filter(([, record]) => record.state !== 'resolved').map(([key]) => key));
  if (state.lease) protectedKeys.add(state.lease.incidentKey);
  const resolved = Object.values(state.incidents).filter(record => record.state === 'resolved')
    .sort((a, b) => timestamp(b.resolvedAt, 'resolved') - timestamp(a.resolvedAt, 'resolved'));
  let retained = resolved.length;
  for (const record of [...resolved].reverse()) {
    if (!protectedKeys.has(record.key) && (retained > policy.limits.resolved
        || now - timestamp(record.resolvedAt, 'resolved') > policy.limits.resolvedAgeMs)) {
      delete state.incidents[record.key]; retained--;
    }
  }
}
function validateNotification(event, state, policy, capacity = false) {
  onlyFields(event, new Set(['id', 'type', 'key', 'source', 'stage', 'failureClass', 'scope', 'generation', 'time']), 'notification');
  const prefix = `${policy.environment}:notice:`;
  const sequence = event.id?.startsWith(prefix) ? Number(event.id.slice(prefix.length)) : NaN;
  if (!Number.isSafeInteger(sequence) || sequence < 1 || sequence > state.notificationSequence
      || event.id !== `${prefix}${sequence}` || !Number.isSafeInteger(event.generation) || event.generation < 1
      || bytes(event) > 2048) throw new Error('Invalid notification identity');
  timestamp(event.time, 'notification time'); identifier(event.scope, 'notification scope', 96);
  if (capacity) {
    if (event.type !== 'overflow' || event.source !== 'watchdog-ledger' || event.stage !== 'storage'
        || event.failureClass !== 'capacity' || event.key !== JSON.stringify([policy.environment, 'watchdog-ledger', 'storage', 'capacity', {}])) throw new Error('Invalid capacity notice');
  } else {
    const identity = JSON.parse(event.key);
    if (!['confirmed', 'resolved'].includes(event.type) || !policy.sources[event.source]?.stages.includes(event.stage)
        || !Array.isArray(identity) || identity.length !== 5
        || incidentKey({ environment: identity[0], source: identity[1], stage: identity[2], failureClass: identity[3], facts: identity[4] }) !== event.key
        || identity[0] !== policy.environment || identity[1] !== event.source || identity[2] !== event.stage || identity[3] !== event.failureClass) throw new Error('Unadmitted notification');
  }
  return sequence;
}
function nextNotice(state, fields, now) {
  if (state.notificationSequence >= Number.MAX_SAFE_INTEGER) throw new Error('Notification sequence exhausted');
  state.notificationSequence++;
  return { id: `${state.environment}:notice:${state.notificationSequence}`, ...fields, time: iso(now) };
}
function overflow(state, now, reason) {
  const first = !state.overflow;
  state.overflow ??= { since: iso(now), reason, notice: nextNotice(state, { type: 'overflow',
    key: JSON.stringify([state.environment, 'watchdog-ledger', 'storage', 'capacity', {}]),
    source: 'watchdog-ledger', stage: 'storage', failureClass: 'capacity', scope: reason, generation: 1 }, now) };
  return { state, events: first ? [state.overflow.notice] : [], result: 'overflow' };
}
function boundedResult(state, previous, policy, now, events, result) {
  const records = Object.values(state.incidents);
  if (records.filter(record => record.state !== 'resolved').length > policy.limits.active) return overflow(copy(previous), now, 'active_capacity');
  if (records.filter(record => record.state === 'resolved').length > policy.limits.resolved) return overflow(copy(previous), now, 'storage_capacity');
  if (state.outbox.length + events.length > policy.limits.outbox) return overflow(copy(previous), now, 'outbox_capacity');
  const committed = events.map(event => {
    const record = state.incidents[event.key];
    const scope = typeof record.facts.scope === 'string' ? record.facts.scope
      : typeof record.facts.competition === 'string' ? record.facts.competition : 'source';
    return nextNotice(state, { type: event.type, key: event.key, source: record.source, stage: record.stage,
      failureClass: record.failureClass, scope,
      generation: event.generation }, now);
  });
  state.outbox.push(...committed);
  if (bytes(state) > policy.limits.ledgerBytes - (state.overflow ? 0 : 512)) return overflow(copy(previous), now, 'storage_capacity');
  validateLedger(state, policy, previous);
  return { state, events: committed, result };
}
export function listNotifications(state, policy) {
  validateLedger(state, policy);
  return copy([...state.outbox, ...(state.overflow ? [state.overflow.notice] : [])]
    .sort((left, right) => Number(left.id.split(':').at(-1)) - Number(right.id.split(':').at(-1))));
}
export function applyObservation(input, raw, policy, now = Date.now()) {
  now = timestamp(now, 'now');
  validateLedger(input, policy);
  const state = copy(input);
  compactResolved(state, policy, now, input);
  const key = incidentKey(raw);
  if (raw.environment !== policy.environment) throw new Error('Wrong environment');
  const admitted = policy.sources[raw.source];
  if (!admitted?.stages.includes(raw.stage)) throw new Error('Unadmitted source/stage');
  if (!OUTCOMES.has(raw.outcome)) throw new Error('Invalid outcome');
  const observed = timestamp(raw.observedAt, 'observation');
  const checked = raw.checkedAt == null ? observed : timestamp(raw.checkedAt, 'check');
  const versions = revisions(raw.versions);
  if (raw.evidenceHash != null && !/^[a-fA-F0-9]{64}$/.test(raw.evidenceHash)) throw new Error('Invalid evidence hash');
  // No raw upstream message/body/URL/header or private native record is persisted.
  const coverageKey = `${raw.source}/${raw.stage}`;
  const priorCoverage = state.coverage[coverageKey];
  if (checked > observed + policy.futureGraceMs) throw new Error('Future checkedAt');
  if (observed > now + policy.futureGraceMs || now - observed > policy.maxReceiptAgeMs
      || checked > now + policy.futureGraceMs || now - checked > policy.maxReceiptAgeMs
      || (priorCoverage && observed < timestamp(priorCoverage.observedAt, 'prior observation'))) {
    return { state, events: [], result: 'stale' };
  }
  const admittedActive = admitted.activation === 'active';
  let outcome = admittedActive ? raw.outcome : 'inactive';
  if (!sameRevisions(versions, admitted.expected)) outcome = 'unknown';
  const coverage = { source: raw.source, stage: raw.stage, observedAt: iso(observed),
    outcome, activation: admitted.activation, versions, versionMatches: sameRevisions(versions, admitted.expected) };
  for (const name of ['checkedAt', 'acceptedAt', 'lastHeartbeatAt']) {
    if (raw[name] != null) {
      const value = timestamp(raw[name], name);
      if (value > observed + policy.futureGraceMs) throw new Error(`Future ${name}`);
      coverage[name] = iso(value);
    }
  }
  state.coverage[coverageKey] = coverage;
  let record = state.incidents[key];
  if (!record && outcome !== 'failure') return boundedResult(state, input, policy, now, [], outcome);
  if (!record) {
    if (Object.values(state.incidents).filter(item => item.state !== 'resolved').length >= policy.limits.active) return overflow(copy(input), now, 'active_capacity');
    record = { key, environment: raw.environment, source: raw.source, stage: raw.stage,
      failureClass: raw.failureClass, facts: normalizeFacts(raw.facts), state: 'suspect', generation: 1,
      firstFailureAt: iso(observed), lastFailureAt: iso(observed), failureCount: 0, successCount: 0,
      expected: copy(admitted.expected), firstEvidenceHash: raw.evidenceHash?.toLowerCase() ?? null,
      lastEvidenceHash: raw.evidenceHash?.toLowerCase() ?? null, lastWindow: null, lastOutcome: null };
    state.incidents[key] = record;
  }
  const events = [];
  if (!sameRevisions(record.expected, admitted.expected)) {
    record.expected = copy(admitted.expected); record.successCount = 0; record.failureCount = 0;
    record.lastWindow = null; record.lastOutcome = null;
  }
  // Restamping the same old check must not manufacture new recovery windows.
  const window = Math.floor(checked / policy.windowMs);
  if (record.lastWindow != null && window < record.lastWindow) return { state, events, result: 'stale' };
  const duplicate = record.lastWindow === window;
  // A failure dominates a contradictory success within the same window.
  if (duplicate && record.lastOutcome === 'failure' && outcome === 'success') return { state, events, result: 'duplicate' };
  record.lastEvidenceHash = raw.evidenceHash?.toLowerCase() ?? record.lastEvidenceHash;
  if (outcome === 'unknown' || outcome === 'inactive') {
    record.failureCount = 0; record.successCount = 0;
    if (record.state === 'recovering') record.state = 'confirmed';
  } else if (outcome === 'failure') {
    if (record.state === 'resolved') {
      record.generation++; record.firstFailureAt = iso(observed); delete record.resolvedAt;
      delete record.confirmedAt; delete record.quarantined;
      record.firstEvidenceHash = raw.evidenceHash?.toLowerCase() ?? null;
      record.failureCount = 0; record.state = 'suspect';
    }
    record.lastFailureAt = iso(observed); record.successCount = 0;
    if (!duplicate || record.lastOutcome !== 'failure') record.failureCount = Math.min(policy.failureWindows, record.failureCount + 1);
    if (record.state === 'recovering') record.state = 'confirmed';
    if (record.state === 'suspect' && (record.failureCount >= policy.failureWindows || raw.securityViolation === true)) {
      record.state = 'confirmed'; record.confirmedAt = iso(observed);
      record.quarantined = raw.securityViolation === true;
      events.push({ type: 'confirmed', key, generation: record.generation, quarantined: record.quarantined });
    }
  } else if (outcome === 'success' && record.state !== 'resolved') {
    record.failureCount = 0;
    if (!duplicate || record.lastOutcome !== 'success') record.successCount = Math.min(policy.recoveryWindows, record.successCount + 1);
    record.lastSuccessAt = iso(observed);
    if (record.successCount >= policy.recoveryWindows) {
      record.state = 'resolved'; record.resolvedAt = iso(observed);
      if (record.confirmedAt != null) events.push({ type: 'resolved', key, generation: record.generation });
    } else if (record.state !== 'suspect') record.state = 'recovering';
  }
  record.lastWindow = window; record.lastOutcome = outcome;
  compactResolved(state, policy, now, input);
  // Capacity degradation is sticky: automatic repair stays closed until separately reviewed.
  // Reserve space for one durable overflow marker rather than discovering that
  // the capacity alert itself cannot be committed at the ceiling.
  if (bytes(record) > policy.limits.recordBytes || bytes(state) > policy.limits.ledgerBytes - (state.overflow ? 0 : 512)) {
    const preserved = copy(input);
    return overflow(preserved, now, 'storage_capacity');
  }
  return boundedResult(state, input, policy, now, events, outcome);
}
export function claimRepair(input, key, options, policy, now = Date.now()) {
  now = timestamp(now, 'now'); validateLedger(input, policy);
  const state = copy(input), record = state.incidents[key];
  const ttl = options.ttlMs ?? policy.maxLeaseMs;
  identifier(options.owner, 'repair owner'); identifier(options.baseRevision, 'base revision');
  if (!Number.isSafeInteger(ttl) || ttl < 1 || ttl > policy.maxLeaseMs) throw new Error('Invalid repair deadline');
  if (state.lease && timestamp(state.lease.expiresAt, 'lease expiry') > now) return { state, result: 'busy', claim: null };
  if (state.lease) {
    const old = state.incidents[state.lease.incidentKey];
    if (old?.state === 'repairing') old.state = 'confirmed';
    state.lease = null;
  }
  if (state.overflow || !record || record.state !== 'confirmed'
      || policy.sources[record.source]?.activation !== 'active'
      || !sameRevisions(record.expected, policy.sources[record.source].expected)) return { state, result: 'denied', claim: null };
  if (state.repairFence >= Number.MAX_SAFE_INTEGER) throw new Error('Fencing capacity exhausted');
  state.repairFence++;
  const claim = { incidentKey: key, owner: options.owner, baseRevision: options.baseRevision,
    token: state.repairFence, expiresAt: iso(now + ttl) };
  state.lease = claim; record.state = 'repairing';
  validateLedger(state, policy, input);
  return { state, result: 'claimed', claim: copy(claim) };
}
export function assertRepairFence(state, claim, { baseRevision }, policy, now = Date.now()) {
  validateLedger(state, policy); now = timestamp(now, 'now');
  const current = state.lease;
  if (state.overflow || !claim || !current || current.token !== claim.token || current.owner !== claim.owner
      || current.incidentKey !== claim.incidentKey || current.baseRevision !== claim.baseRevision
      || current.baseRevision !== baseRevision || timestamp(current.expiresAt, 'lease expiry') <= now
      || state.incidents[current.incidentKey]?.state !== 'repairing'
      || policy.sources[state.incidents[current.incidentKey]?.source]?.activation !== 'active'
      || !sameRevisions(state.incidents[current.incidentKey]?.expected,
        policy.sources[state.incidents[current.incidentKey]?.source]?.expected)) throw new Error('Stale or inadmissible repair fence');
  return true;
}
export function releaseRepair(input, claim, options, policy, now = Date.now()) {
  // Releasing an exact owned lease is cleanup, not publication authority.
  // Recovery/expiry/disablement may forbid writes while still allowing cleanup.
  validateLedger(input, policy); timestamp(now, 'now');
  const current = input.lease;
  if (!claim || !current || current.token !== claim.token || current.owner !== claim.owner
      || current.incidentKey !== claim.incidentKey || current.baseRevision !== claim.baseRevision
      || current.baseRevision !== options.baseRevision) throw new Error('Stale repair release');
  const state = copy(input), record = state.incidents[claim.incidentKey];
  state.lease = null;
  if (record.state === 'repairing') record.state = 'confirmed';
  return { state, result: 'released' };
}
export function missedRunObservations(spec, now = Date.now()) {
  now = timestamp(now, 'now');
  const interval = spec.intervalMs, grace = spec.graceMs;
  if (!Number.isSafeInteger(interval) || interval < 1 || !Number.isSafeInteger(grace) || grace < 0) throw new Error('Invalid missed-run policy');
  const dimensions = [['completed', 'lastCompletedAt'], ['attempted', 'lastAttemptedAt']];
  if (spec.requiresAccepted === true) dimensions.push(['accepted', 'lastAcceptedAt']);
  return dimensions.map(([dimension, field]) => {
    const start = spec.startedAt == null ? null : timestamp(spec.startedAt, 'monitor start');
    const last = spec[field] == null ? null : timestamp(spec[field], field);
    const origin = last ?? start;
    const outcome = spec.activation !== 'active' ? 'inactive' : origin == null || origin > now ? 'unknown'
      : now - origin > interval + grace ? 'failure' : last == null ? 'unknown' : 'success';
    return { environment: spec.environment, source: spec.source, stage: spec.stage,
      failureClass: 'missing_run', facts: { dimension }, outcome, observedAt: iso(now),
      versions: revisions(spec.versions), checkedAt: iso(now), ...(last == null ? {} : {
        lastHeartbeatAt: iso(last), ...(dimension === 'accepted' ? { acceptedAt: iso(last) } : {}) }) };
  });
}
