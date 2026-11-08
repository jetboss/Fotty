// Offline/local qualification store. Production hosting must supply its own
// transactional persistence; this is not a cross-cloud repair authority.
import { promises as fs, constants } from 'node:fs';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { applyObservation, assertRepairFence, claimRepair, emptyLedger, releaseRepair, validateLedger } from './incident-policy.mjs';

export async function openIncidentStore(directory, { policy, lockTimeoutMs = 2000 } = {}) {
  if (!policy || !Number.isInteger(lockTimeoutMs) || lockTimeoutMs < 1 || lockTimeoutMs > 5000) throw new Error('Invalid store configuration');
  const root = path.resolve(directory);
  await fs.mkdir(root, { recursive: true, mode: 0o700 });
  const rootStat = await fs.lstat(root);
  if (!rootStat.isDirectory() || rootStat.isSymbolicLink()) throw new Error('Unsafe store directory');
  const ledgerPath = path.join(root, 'incident-ledger.json');
  const lockPath = path.join(root, '.incident-lock');
  async function read() {
    let handle;
    try {
      handle = await fs.open(ledgerPath, constants.O_RDONLY | constants.O_NOFOLLOW);
      const stat = await handle.stat();
      if (!stat.isFile() || stat.size > policy.limits.ledgerBytes) throw new Error('Unsafe or oversize incident store');
      return validateLedger(JSON.parse(await handle.readFile('utf8')), policy);
    } catch (error) {
      if (error.code === 'ENOENT') return emptyLedger(policy);
      throw new Error('Incident store unreadable; repairs closed', { cause: error });
    } finally { await handle?.close(); }
  }
  async function acquire() {
    const deadline = Date.now() + lockTimeoutMs;
    const nonce = randomUUID();
    while (Date.now() <= deadline) {
      try {
        await fs.mkdir(lockPath, { mode: 0o700 });
        try { await fs.writeFile(path.join(lockPath, 'owner.json'), JSON.stringify({ pid: process.pid, nonce }), { flag: 'wx', mode: 0o600 }); }
        catch (error) { await fs.rmdir(lockPath).catch(() => {}); throw error; }
        return nonce;
      } catch (error) {
        if (error.code !== 'EEXIST') throw new Error('Incident lock unavailable; repairs closed', { cause: error });
        // Never steal/rename an existing lock based on an earlier owner read:
        // another contender could already have replaced it. A crashed writer
        // requires separately verified operator cleanup, not automatic repair.
        await new Promise(resolve => setTimeout(resolve, 10));
      }
    }
    throw new Error('Incident lock deadline exceeded; repairs closed');
  }
  async function unlock(nonce) {
    const owner = JSON.parse(await fs.readFile(path.join(lockPath, 'owner.json'), 'utf8'));
    if (owner.nonce !== nonce || owner.pid !== process.pid) throw new Error('Incident lock ownership changed');
    await fs.unlink(path.join(lockPath, 'owner.json'));
    await fs.rmdir(lockPath);
  }
  async function transact(mutator) {
    const nonce = await acquire();
    const temporary = path.join(root, `.incident-write-${nonce}`);
    try {
      const previous = await read();
      const result = await mutator(JSON.parse(JSON.stringify(previous)));
      if (!result?.state) throw new Error('Transaction omitted ledger');
      if (result.state.revision !== previous.revision) throw new Error('Stale transaction base revision');
      result.state.revision = previous.revision + 1;
      if (!Number.isSafeInteger(result.state.revision)) throw new Error('Store revision exhausted');
      validateLedger(result.state, policy, previous);
      const handle = await fs.open(temporary, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW, 0o600);
      try { await handle.writeFile(JSON.stringify(result.state)); await handle.sync(); }
      finally { await handle.close(); }
      await fs.rename(temporary, ledgerPath);
      const directoryHandle = await fs.open(root, constants.O_RDONLY);
      try { await directoryHandle.sync(); } finally { await directoryHandle.close(); }
      return result;
    } catch (error) {
      throw new Error('Incident transaction failed; no repair authority granted', { cause: error });
    } finally {
      await fs.unlink(temporary).catch(error => { if (error.code !== 'ENOENT') throw error; });
      await unlock(nonce);
    }
  }
  return {
    read, transact,
    observe: (receipt, now) => transact(state => applyObservation(state, receipt, policy, now)),
    claimRepair: (key, options, now) => transact(state => claimRepair(state, key, options, policy, now)),
    releaseRepair: (claim, options, now) => transact(state => releaseRepair(state, claim, options, policy, now)),
    // A read-and-check result must not be used later as publication authority.
    // The trusted persistence/publisher must enforce this fence in its write transaction.
    fenceRepair: (claim, options, now) => transact(state => {
      assertRepairFence(state, claim, options, policy, now);
      return { state, result: 'valid' };
    })
  };
}
