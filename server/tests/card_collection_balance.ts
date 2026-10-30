// Deterministic tuning aid; pack counts are not a prediction of calendar days.
import { CardCollectionService } from "../src/engine/card_collection";
import { GameEngine } from "../src/engine/game_engine";
import { gameConfigTables } from "../src/worker/config_data";

const engine = new GameEngine(gameConfigTables);
const initial = engine.createInitialState();
initial.cultivation.current_level = 2;
const sampleSize = 200;
const summaries = [];
for (const star of [1, 3, 5]) {
  const completions: number[] = [];
  const setCompletions = new Map(gameConfigTables.cardCollection.card_sets.map(set => [set.set_id, [] as number[]]));
  let totalCards = 0;
  let uniqueCards = 0;
  for (let player = 1; player <= sampleSize; player++) {
    let seed = player * 104729;
    const random = () => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed / 4294967296; };
    const service = new CardCollectionService(gameConfigTables.cardCollection, gameConfigTables.activities.activities, random,
      (state, rewards) => engine.applyRewards(state, rewards));
    const state = structuredClone(initial); const progress = service.ensureProgress(state)[1];
    for (let opened = 0; opened < 3000; opened++) {
      service.awardPack(state, star, 1);
      const result = service.openPending(state, 1, state.pending_rewards[0].uid, false, `sim-${opened}`, opened);
      if (!result.ok) throw new Error(result.reason);
      totalCards += result.cards!.reduce((n,c)=>n+(c.gained??1),0); uniqueCards += result.cards!.filter(c => c.is_new).length;
      for (const set of result.completed_sets ?? []) setCompletions.get(set.set_id)!.push(opened + 1);
      if (Object.keys(progress.cards).length === gameConfigTables.cardCollection.cards.length) { completions.push(opened + 1); break; }
    }
  }
  completions.sort((a, b) => a - b);
  const percentile = (values: number[], fraction: number) => {
    values.sort((a,b)=>a-b);
    return values[Math.floor(sampleSize * fraction)] ?? null; // Censored runs must not understate percentiles.
  };
  summaries.push({pack_star:star,players:sampleSize,pack_limit:3000,completed:completions.length,all_sets_p50_packs:percentile(completions,0.5),all_sets_p90_packs:percentile(completions,0.9),duplicate_percent:Math.round((1 - uniqueCards / totalCards) * 1000) / 10,sets:[...setCompletions].map(([set_id,values])=>({set_id,completed:values.length,p50_packs:percentile(values,0.5)}))});
}
console.log(JSON.stringify(summaries, null, 2));
