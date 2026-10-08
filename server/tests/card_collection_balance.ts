// Deterministic tuning aid; pack counts are not a prediction of calendar days.
import { CardCollectionService } from "../src/engine/card_collection";
import { GameEngine } from "../src/engine/game_engine";
import { gameConfigTables } from "../src/worker/config_data";

const engine = new GameEngine(gameConfigTables);
const initial = engine.createInitialState();
const sampleSize = 200;
const summaries = [];
for (const star of [1, 3, 5]) {
  const completions: number[] = [];
  let totalCards = 0;
  let uniqueCards = 0;
  for (let player = 1; player <= sampleSize; player++) {
    let seed = player * 104729;
    const random = () => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed / 4294967296; };
    const service = new CardCollectionService(gameConfigTables.cardCollection, gameConfigTables.activities.activities, random);
    const state = structuredClone(initial); const progress = service.ensureProgress(state)[1];
    progress.packs[star] = 3000;
    for (let opened = 0; opened < 3000; opened++) {
      const result = service.open(state, 1, star, `sim-${opened}`, opened);
      if (!result.ok) throw new Error(result.reason);
      totalCards += result.cards!.length; uniqueCards += result.cards!.filter(c => c.is_new).length;
      if (Object.keys(progress.cards).length === gameConfigTables.cardCollection.cards.length) { completions.push(opened + 1); break; }
    }
  }
  completions.sort((a, b) => a - b);
  summaries.push({pack_star:star,players:sampleSize,completed:completions.length,all_sets_p50_packs:completions[Math.floor(completions.length * 0.5)],all_sets_p90_packs:completions[Math.floor(completions.length * 0.9)],duplicate_percent:Math.round((1 - uniqueCards / totalCards) * 1000) / 10});
}
console.log(JSON.stringify(summaries, null, 2));
