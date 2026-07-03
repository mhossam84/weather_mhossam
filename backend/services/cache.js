/**
 * Minimal in-memory TTL cache. The spec explicitly rules out a database for
 * the prototype ("fetch on demand, cache in memory if needed"), so this
 * just wraps a Map -- state resets whenever the server restarts.
 */

const store = new Map();

function get(key) {
  const entry = store.get(key);
  if (!entry) return undefined;
  if (Date.now() > entry.expiresAt) {
    store.delete(key);
    return undefined;
  }
  return entry.value;
}

function set(key, value, ttlMs) {
  store.set(key, { value, expiresAt: Date.now() + ttlMs });
}

module.exports = { get, set };
