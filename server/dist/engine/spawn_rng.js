"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.deterministicSpawnRoll = deterministicSpawnRoll;
const SPAWN_RNG_MODULUS = 2147483647;
const SPAWN_RNG_MULTIPLIER = 48271;
function deterministicSpawnRoll(seed, sequence, launcherUid, totalWeight) {
    if (!Number.isInteger(totalWeight) || totalWeight <= 0)
        return 0;
    let value = (Math.trunc(seed) >>> 0) % (SPAWN_RNG_MODULUS - 1) + 1;
    value = (value * SPAWN_RNG_MULTIPLIER + Math.max(0, Math.trunc(sequence))) % SPAWN_RNG_MODULUS;
    value = (value * SPAWN_RNG_MULTIPLIER + Math.max(0, Math.trunc(launcherUid))) % SPAWN_RNG_MODULUS;
    return value % totalWeight;
}
