// Shared per-user operation queue — sequential execution per user
// Used by all route modules (game, cultivation, gm) to prevent
// concurrent state mutations for the same user.

const userQueues = new Map<string, Promise<void>>();

export function enqueue(userId: string, fn: () => Promise<void>): Promise<void> {
  const prev = userQueues.get(userId) ?? Promise.resolve();
  const next = prev.then(fn, (err) => {
    // prev rejected: log and reset the queue so future ops aren't blocked
    console.error(`[queue] prev promise rejected for ${userId}:`, err);
    return fn();
  }).catch((err) => {
    console.error(`[queue] handler error for ${userId}:`, err);
    // Don't re-throw — queue must stay healthy for subsequent requests
  });
  userQueues.set(userId, next);
  return next;
}
