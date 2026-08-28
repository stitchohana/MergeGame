import assert from "node:assert/strict";
import { GameEngine } from "../src/engine/game_engine";
import { gameConfigTables } from "../src/worker/config_data";

const engine = new GameEngine(gameConfigTables);
const launcherDef = (gameConfigTables.items as any).launcher.find((item: any) => item.id === 11004);
assert.ok(launcherDef, "expected launcher fixture");

const fullRechargeState: any = {
  grid: [{
    uid: 1,
    id: launcherDef.id,
    col: 0,
    row: 0,
    charges: Number(launcherDef.max_charges) - 1,
    last_charge_time: Date.now() + 1000,
  }],
  spirit_stones: 60,
  version: 7,
};
const completed = engine.executeLauncherSpeedup(fullRechargeState, 1);
assert.equal(completed.ok, true);
if (completed.ok) {
  assert.equal(completed.cost, 60);
  assert.equal(completed.remainingSeconds, 3600);
  assert.equal(completed.charges, launcherDef.max_charges);
}
assert.equal(fullRechargeState.spirit_stones, 0);
assert.equal(fullRechargeState.version, 8);

const rejectedState: any = {
  grid: [{
    uid: 2,
    id: launcherDef.id,
    col: 0,
    row: 0,
    charges: Number(launcherDef.max_charges) - 1,
    last_charge_time: Date.now() + 1000,
  }],
  spirit_stones: 59,
  version: 11,
};
const rejected = engine.executeLauncherSpeedup(rejectedState, 2);
assert.equal(rejected.ok, false);
if (!rejected.ok) {
  assert.equal(rejected.reason, "insufficient_stones");
  assert.equal(rejected.cost, 60);
  assert.equal(rejected.remainingSeconds, 3600);
  assert.equal(rejected.spiritStones, 59);
}
assert.equal(rejectedState.spirit_stones, 59);
assert.equal(rejectedState.grid[0].charges, Number(launcherDef.max_charges) - 1);
assert.equal(rejectedState.version, 11);

console.log("SPEEDUP_SMOKE_OK launcher_success_and_authoritative_failure_details=true");
