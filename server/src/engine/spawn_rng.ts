const SPAWN_RNG_MODULUS = 2147483647;
const SPAWN_RNG_MULTIPLIER = 48271;

export function deterministicSpawnRoll(
  seed: number,
  sequence: number,
  launcherUid: number,
  totalWeight: number,
): number {
  if (!Number.isInteger(totalWeight) || totalWeight <= 0) return 0;

  let value = (Math.trunc(seed) >>> 0) % (SPAWN_RNG_MODULUS - 1) + 1;
  value = (value * SPAWN_RNG_MULTIPLIER + Math.max(0, Math.trunc(sequence))) % SPAWN_RNG_MODULUS;
  value = (value * SPAWN_RNG_MULTIPLIER + Math.max(0, Math.trunc(launcherUid))) % SPAWN_RNG_MODULUS;
  return value % totalWeight;
}
