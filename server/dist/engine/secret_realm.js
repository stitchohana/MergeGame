"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.SecretRealmService = void 0;
const grid_search_1 = require("./grid_search");
const fail = (reason) => ({ ok: false, reason });
const integer = (n, min = 0) => Number.isSafeInteger(n) && Number(n) >= min;
class SecretRealmService {
    engine;
    config;
    defs = new Map();
    monsters = new Map();
    bossFogStages = new Map();
    constructor(raw, engine) {
        this.engine = engine;
        if (!raw)
            return;
        this.config = raw;
        const s = raw.settings?.[0];
        const invalid = () => { throw new Error("invalid_secret_realm_config"); };
        if (raw.settings?.length !== 1 || s.cols !== 6 || s.rows !== 8 || !integer(s.advance, 1)
            || s.advance > s.rows || !integer(s.activity_id, 1) || typeof s.period !== "string" || !s.period)
            invalid();
        if (!Array.isArray(raw.items) || !Array.isArray(raw.monsters) || !Array.isArray(raw.layout)
            || !Array.isArray(raw.stages) || !raw.stages.length || !Array.isArray(raw.merge_drops) || !Array.isArray(raw.order_supply)
            || !Array.isArray(raw.order_supply_realms))
            invalid();
        for (const d of raw.items) {
            if (!d.id || this.defs.has(d.id) || !integer(d.level, 1) || !integer(d.value) || !d.name)
                invalid();
            if (["stamina", "stone"].includes(d.chain) && d.value <= 0)
                invalid();
            this.defs.set(d.id, d);
        }
        for (const [chain, cap] of [["sword", 12], ["qi", 6], ["stamina", 3], ["stone", 3]]) {
            const items = raw.items.filter((d) => d.chain === chain);
            if (items.length !== cap || Array.from({ length: cap }, (_, i) => i + 1).some(l => items.filter((d) => d.level === l).length !== 1))
                invalid();
        }
        if (this.defs.size !== 24)
            invalid();
        const dropsValid = (drops) => Array.isArray(drops) && drops.every(d => this.defs.has(d.id)
            && integer(d.count, 1) && d.count <= 100 && typeof d.immovable === "boolean"
            && (!d.immovable || this.defs.get(d.id).chain === "sword"));
        for (const m of raw.monsters) {
            if (!m.id || this.monsters.has(m.id) || !m.name || typeof m.boss !== "boolean" || !Array.isArray(m.costs)
                || !m.costs.length || m.costs.some(c => !this.defs.has(c.id) || !["sword", "qi"].includes(this.defs.get(c.id).chain) || !integer(c.count, 1))
                || new Set(m.costs.map(c => c.id)).size !== m.costs.length || !dropsValid(m.drops)
                || m.drops.some(d => !["stamina", "stone"].includes(this.defs.get(d.id).chain))
                || m.costs.some(c => c.count > 100 || (m.boss && this.defs.get(c.id).chain === "qi" && this.defs.get(c.id).level !== 6))
                || (m.boss && (!m.costs.some(c => this.defs.get(c.id).chain === "sword") || !m.costs.some(c => this.defs.get(c.id).chain === "qi" && this.defs.get(c.id).level === 6))))
                invalid();
            this.monsters.set(m.id, m);
        }
        const positions = new Set();
        for (const c of raw.layout) {
            const key = `${c.col},${c.row}`;
            if (!integer(c.col) || c.col >= s.cols || !integer(c.row) || c.row >= s.rows + s.advance * (raw.stages.length - 1)
                || positions.has(key) || typeof c.fog !== "boolean" || typeof c.immovable !== "boolean"
                || (!!c.id === !!c.monster) || (c.id && !this.defs.has(c.id)) || (c.monster && !this.monsters.has(c.monster)))
                invalid();
            if (c.id && c.immovable && !["sword", "qi"].includes(this.defs.get(c.id).chain))
                invalid();
            positions.add(key);
        }
        if (positions.size !== s.cols * (s.rows + s.advance * (raw.stages.length - 1)))
            invalid();
        let previousLevel = 1;
        for (let row = 0; row < s.rows + s.advance * (raw.stages.length - 1); row++) {
            const levels = raw.layout.filter((c) => c.row === row && c.id && c.immovable && this.defs.get(c.id).chain === "sword").map((c) => this.defs.get(c.id).level);
            if (levels.length) {
                if (Math.min(...levels) < previousLevel)
                    invalid();
                previousLevel = Math.max(...levels);
            }
        }
        const initialItems = raw.layout.filter((c) => c.row < s.rows && c.id);
        const movable = initialItems.filter((c) => !c.immovable);
        if (movable.length !== 3 || movable.some((c) => c.fog || this.defs.get(c.id).level !== 1)
            || !movable.some((c) => initialItems.some((target) => target !== c && !target.fog && target.id === c.id)))
            invalid();
        if (raw.stages.some((stage, index) => !this.monsters.get(stage.boss)?.boss
            || raw.layout.filter((c) => c.monster === stage.boss).length !== 1
            || !raw.layout.some((c) => c.monster === stage.boss && c.row >= index * s.advance && c.row < index * s.advance + s.rows)))
            invalid();
        for (const [index, stage] of raw.stages.entries()) {
            const boss = raw.layout.find((c) => c.monster === stage.boss);
            const zone = raw.layout.filter((c) => Math.abs(c.col - boss.col) <= 1 && Math.abs(c.row - boss.row) <= 1);
            if (zone.length !== 9 || zone.some((c) => !c.fog || c.row < index * s.advance || c.row >= index * s.advance + s.rows
                || (c.monster && c.monster !== stage.boss)))
                invalid();
            for (const c of zone) {
                const key = `${c.col},${c.row}`;
                if (this.bossFogStages.has(key))
                    invalid();
                this.bossFogStages.set(key, index);
            }
        }
        if (!dropsValid(raw.order_supply) || !raw.order_supply.some((d) => this.defs.get(d.id).chain === "sword" && this.defs.get(d.id).level === 1 && !d.immovable)
            || raw.merge_drops.some((d) => !integer(d.min_level, 2) || !integer(d.max_level, d.min_level) || d.max_level > 12 || !dropsValid(d.drops)
                || d.drops.some((drop) => !["sword", "qi"].includes(this.defs.get(drop.id).chain)
                    || drop.immovable !== (this.defs.get(drop.id).chain === "sword")
                    || (this.defs.get(drop.id).chain === "sword" && this.defs.get(drop.id).level >= d.min_level))))
            invalid();
        if (!raw.merge_drops.some((d) => d.drops.some((drop) => this.defs.get(drop.id).chain === "qi")))
            invalid();
        const supplyLevels = new Set();
        for (const rule of raw.order_supply_realms) {
            if (!integer(rule.cultivation_min, 1) || !integer(rule.cultivation_max, rule.cultivation_min)
                || rule.cultivation_max > this.engine.cultivationStages.length || !dropsValid(rule.drops) || !rule.drops.length
                || rule.drops.some(d => d.immovable || this.defs.get(d.id).chain !== "sword"))
                invalid();
            for (let level = rule.cultivation_min; level <= rule.cultivation_max; level++) {
                if (supplyLevels.has(level))
                    invalid();
                supplyLevels.add(level);
            }
        }
        for (let level = 2; level <= 12; level++) {
            const swordCount = raw.merge_drops
                .filter(r => r.min_level <= level && level <= r.max_level).flatMap(r => r.drops)
                .filter(d => this.defs.get(d.id).chain === "sword").reduce((count, d) => count + d.count, 0);
            if (swordCount > 2)
                invalid();
        }
        // Every mob must be reachable without merging through a locked Boss zone.
        const revealed = new Set(raw.layout.filter((c) => !c.fog).map((c) => `${c.col},${c.row}`));
        for (let stage = 0; stage < raw.stages.length; stage++) {
            const window = raw.layout.filter((c) => c.row >= stage * s.advance && c.row < stage * s.advance + s.rows);
            let changed = true;
            while (changed) {
                changed = false;
                for (const c of window)
                    if (c.id && revealed.has(`${c.col},${c.row}`)) {
                        for (const neighbor of window)
                            if (Math.abs(c.col - neighbor.col) + Math.abs(c.row - neighbor.row) === 1 && !revealed.has(`${neighbor.col},${neighbor.row}`)
                                && (this.bossFogStages.get(`${neighbor.col},${neighbor.row}`) ?? -1) < stage) {
                                revealed.add(`${neighbor.col},${neighbor.row}`);
                                changed = true;
                            }
                    }
            }
            const boss = window.find((c) => c.monster === raw.stages[stage].boss);
            if (window.some((c) => c.monster && !this.monsters.get(c.monster).boss && !revealed.has(`${c.col},${c.row}`)))
                invalid();
            for (const c of window)
                if (this.bossFogStages.get(`${c.col},${c.row}`) === stage)
                    revealed.add(`${c.col},${c.row}`);
            if (!boss || !revealed.has(`${boss.col},${boss.row}`))
                invalid();
        }
    }
    available(state) {
        const activity = this.engine.activityEngine.getActivities().find(a => a.id === this.config?.settings[0].activity_id && a.widget === "SecretRealm");
        return !!activity && this.engine.activityEngine.isActive(activity) && state.cultivation.current_level >= 2;
    }
    initialize(state) {
        if (!this.config || !this.available(state))
            return false;
        const makeCell = (c) => ({ col: c.col, row: c.row, fog: c.fog,
            ...(c.id ? { item: { uid: this.engine._nextUid(state), id: c.id, immovable: c.immovable } } : { monster: c.monster }) });
        if (state.secret_realm?.period === this.config.settings[0].period)
            return false;
        state.secret_realm = { period: this.config.settings[0].period, version: 0, stage: 0, start_row: 0, completed: false,
            cells: this.config.layout.map(makeCell),
            stash: [], receipts: [] };
        return true;
    }
    setViewport(p, startRow) {
        const oldStart = p.start_row;
        p.start_row = startRow;
        // Unlock revealed items as they leave the viewport and enter the stash.
        // Overlapping and future rows keep their original instances and locks.
        for (const c of p.cells)
            if (c.row >= oldStart && c.row < oldStart + this.config.settings[0].rows && !this.visible(p, c) && c.item) {
                if (!c.fog) {
                    c.item.immovable = false;
                    p.stash.push(c.item);
                }
                delete c.item;
            }
        // Reveal the bottom of the newly entering area, just above the old viewport.
        const firstIncomingRow = oldStart + this.config.settings[0].rows;
        if (startRow > oldStart)
            for (const c of p.cells)
                if (c.row === firstIncomingRow && !this.bossFogLocked(p, c))
                    c.fog = false;
    }
    visible(p, c) { return c.row >= p.start_row && c.row < p.start_row + this.config.settings[0].rows; }
    remainingMobs(p) {
        // Fog hides presentation, but never exempts a living mob from the Boss gate.
        return p.cells.filter(c => this.visible(p, c) && c.monster && this.monsters.get(c.monster)?.boss === false).length;
    }
    bossFogLocked(p, c) {
        return (this.bossFogStages.get(`${c.col},${c.row}`) ?? -1) >= p.stage;
    }
    unlockBossFog(p) {
        if (this.remainingMobs(p) !== 0)
            return;
        for (const c of p.cells)
            if (this.bossFogStages.get(`${c.col},${c.row}`) === p.stage)
                c.fog = false;
    }
    definition(chain, level) { return [...this.defs.values()].find(d => d.chain === chain && d.level === level); }
    view(state) {
        if (!this.config)
            return {};
        const p = state.secret_realm?.period === this.config.settings[0].period ? state.secret_realm : undefined;
        return { available: this.available(state), initialized: !!p, ...this.config.settings[0], items: this.config.items,
            ...(p ? { period: p.period, version: p.version, stage: p.stage, stage_name: this.config.stages[p.stage]?.name ?? "秘境通关",
                completed: p.completed, start_row: p.start_row, remaining_mobs: this.remainingMobs(p), stash: structuredClone(p.stash),
                cells: p.cells.filter(c => this.visible(p, c)).map(c => c.fog ? { col: c.col, row: c.row, fog: true,
                    ...(this.bossFogLocked(p, c) ? { special_fog: true } : {}) } : {
                    ...structuredClone(c), ...(c.monster ? { enemy: this.monsters.get(c.monster) } : {})
                }),
                inventory: this.inventory(p).reduce((out, i) => { out[i.id] = (out[i.id] ?? 0) + 1; return out; }, {}) } : {}) };
    }
    inventory(p) {
        return [...p.stash, ...p.cells.filter(c => this.visible(p, c) && !c.fog && c.item).map(c => c.item)].filter(i => !i.immovable);
    }
    grant(state, p, drops, stashOnly = false, discardOverflow = false, origin, effects) {
        const lost = [];
        const cells = stashOnly ? [] : p.cells.filter(c => this.visible(p, c) && !c.fog && !c.item && !c.monster);
        if (origin) {
            const distance = (c) => (c.col - origin.col) ** 2 + (c.row - origin.row) ** 2;
            // Stable ties keep preview, commit and retries identical, regardless of save array order.
            cells.sort((a, b) => distance(a) - distance(b) || a.row - b.row || a.col - b.col);
        }
        let index = 0;
        for (const drop of drops)
            for (let n = 0; n < drop.count; n++) {
                const item = { uid: this.engine._nextUid(state), id: drop.id, immovable: drop.immovable };
                const cell = cells[index++];
                if (cell) {
                    cell.item = item;
                    effects?.push({ item: { ...item }, col: cell.col, row: cell.row });
                }
                else if (discardOverflow) {
                    const existing = lost.find(d => d.id === drop.id && d.immovable === drop.immovable);
                    if (existing)
                        existing.count++;
                    else
                        lost.push({ ...drop, count: 1 });
                }
                else {
                    p.stash.push(item);
                    effects?.push({ item: { ...item }, stash: true });
                }
            }
        return lost;
    }
    awardOrder(state) {
        if (!this.available(state) || state.board_type === 1)
            return;
        this.initialize(state);
        const p = state.secret_realm;
        if (p.completed)
            return;
        const rule = this.config.order_supply_realms.find(r => r.cultivation_min <= state.cultivation.current_level
            && state.cultivation.current_level <= r.cultivation_max);
        this.grant(state, p, rule ? rule.drops : this.config.order_supply, true);
        p.version++;
    }
    transact(state, body) {
        return this.applyAction(state, body);
    }
    gmGrantSwords(state, level, amount) {
        if (!integer(level, 1) || level > 12)
            return fail("invalid_level");
        if (!integer(amount, 1) || amount > 1000)
            return fail("invalid_amount");
        if (!this.available(state))
            return fail("activity_locked");
        const sword = this.definition("sword", level);
        this.initialize(state);
        const p = state.secret_realm;
        this.grant(state, p, [{ id: sword.id, count: amount, immovable: false }], true);
        p.version++;
        state.version++;
        return { ok: true, granted_count: amount, sword_level: level };
    }
    previewMerge(state, body) {
        if (!body || !["move", "place"].includes(body.action))
            return fail("invalid_params");
        return this.applyAction(state, body, true);
    }
    applyAction(state, body, preview = false) {
        if (!this.available(state))
            return fail("activity_locked");
        if (!body || typeof body.request_id !== "string" || !body.request_id.trim() || body.request_id.length > 100
            || !integer(body.version) || body.period !== this.config.settings[0].period
            || !["move", "place", "recall", "use", "fight"].includes(body.action))
            return fail("invalid_params");
        if (body.accept_reward_loss !== undefined && typeof body.accept_reward_loss !== "boolean")
            return fail("invalid_params");
        const signature = JSON.stringify([body.action, body.period, body.version, body.uid ?? null, body.col ?? null, body.row ?? null, ...(body.accept_reward_loss === true ? [true] : [])]);
        const original = state.secret_realm;
        const receipt = original?.receipts.find(r => r.request_id === body.request_id);
        if (!preview && receipt)
            return receipt.signature === signature ? { ok: true, replayed: true, ...(receipt.effects ? { effects: structuredClone(receipt.effects) } : {}) } : fail("state_conflict");
        if (!original || original.period !== body.period || original.version !== body.version)
            return fail("state_conflict");
        // Validate and mutate a detached copy. Even direct engine callers get failure atomicity.
        const copy = structuredClone(state), p = copy.secret_realm;
        let effects;
        const cell = p.cells.find(c => c.col === body.col && c.row === body.row && this.visible(p, c));
        const source = p.cells.find(c => c.item?.uid === body.uid && this.visible(p, c) && !c.fog);
        const stashIndex = p.stash.findIndex(i => i.uid === body.uid);
        const item = source?.item ?? (stashIndex >= 0 ? p.stash[stashIndex] : undefined);
        if (body.action === "move" || body.action === "place") {
            if (!integer(body.uid, 1) || !integer(body.col) || !integer(body.row) || !cell || cell.fog || cell.monster)
                return fail("invalid_target");
            if (!item || (body.action === "move" ? !source : stashIndex < 0) || source === cell)
                return fail("invalid_source");
            // Stash supply follows board merge rules. Explicitly fixed stash items may only
            // be placed on an empty cell; they cannot become movable merge sources.
            if (item.immovable && (body.action === "move" || cell.item))
                return fail("item_locked");
            const target = cell.item;
            const def = this.defs.get(item.id);
            const next = target?.id === item.id ? this.definition(def.chain, def.level + 1) : undefined;
            if (target && !next) {
                if (target.immovable)
                    return fail("item_locked");
                if (!source || body.action !== "move")
                    return fail("invalid_source");
                if (preview)
                    return fail("invalid_target");
                const { cols, rows } = this.config.settings[0];
                const cells = new Map(p.cells.filter(c => this.visible(p, c)).map(c => [`${c.col},${c.row}`, c]));
                const empty = (0, grid_search_1.findNearestEmptyCell)(cols, rows, cell.col, rows - 1 - (cell.row - p.start_row), (col, row) => {
                    const candidate = cells.get(`${col},${p.start_row + rows - 1 - row}`);
                    return !!candidate && !candidate.fog && !candidate.item && !candidate.monster;
                });
                const displaced = empty ? cells.get(`${empty.col},${p.start_row + rows - 1 - empty.row}`) : source;
                delete source.item;
                displaced.item = target;
                cell.item = item;
            }
            else {
                if (source)
                    delete source.item;
                else
                    p.stash.splice(stashIndex, 1);
                if (next) {
                    cell.item = { uid: this.engine._nextUid(copy), id: next.id, immovable: false };
                    for (const neighbor of p.cells)
                        if (this.visible(p, neighbor) && Math.abs(neighbor.col - cell.col) + Math.abs(neighbor.row - cell.row) === 1
                            && !this.bossFogLocked(p, neighbor))
                            neighbor.fog = false;
                    const drops = next.chain === "sword" ? this.config.merge_drops
                        .filter(d => next.level >= d.min_level && next.level <= d.max_level).flatMap(d => d.drops) : [];
                    const freeCells = p.cells.filter(c => this.visible(p, c) && !c.fog && !c.item && !c.monster).length;
                    effects = { request_id: body.request_id, kind: "merge", col: cell.col, row: cell.row, drops: [] };
                    const lost = this.grant(copy, p, drops, false, true, cell, effects.drops);
                    if (preview)
                        return { ok: true, request_id: body.request_id, period: original.period, version: original.version, free_cells: freeCells, lost_drops: lost };
                    if (lost.length && body.accept_reward_loss !== true)
                        return fail("merge_reward_overflow");
                }
                else
                    cell.item = item;
                if (preview)
                    return fail("invalid_target");
            }
        }
        else if (body.action === "recall" || body.action === "use") {
            if (!integer(body.uid, 1) || !item || item.immovable)
                return fail("item_locked");
            if (body.action === "recall") {
                if (!source)
                    return fail("invalid_source");
                delete source.item;
                p.stash.push(item);
            }
            else {
                const def = this.defs.get(item.id);
                if (!["stamina", "stone"].includes(def.chain) || def.level < 2)
                    return fail("merge_reward_first");
                if (source)
                    delete source.item;
                else
                    p.stash.splice(stashIndex, 1);
                if (def.chain === "stamina")
                    this.engine.addStamina(copy, def.value);
                else
                    copy.spirit_stones += def.value;
            }
        }
        else {
            if (!integer(body.col) || !integer(body.row) || !cell || cell.fog || !cell.monster)
                return fail("invalid_target");
            const monster = this.monsters.get(cell.monster);
            if (monster.boss && this.config.stages[p.stage]?.boss !== monster.id)
                return fail("boss_locked");
            if (monster.boss && this.remainingMobs(p) > 0)
                return fail("mobs_remaining");
            if (!integer(body.uid, 1) || !source || !item)
                return fail("invalid_source");
            if (item.immovable)
                return fail("item_locked");
            const cost = monster.costs.find(c => c.id === item.id);
            if (!cost)
                return fail("wrong_submission");
            const submitted = cell.submitted ?? {};
            if ((submitted[item.id] ?? 0) >= cost.count)
                return fail("requirement_filled");
            delete source.item;
            cell.submitted = { ...submitted, [item.id]: (submitted[item.id] ?? 0) + 1 };
            effects = { request_id: body.request_id, kind: "fight", col: cell.col, row: cell.row,
                submitted: { ...cell.submitted }, defeated: false, drops: [] };
            if (monster.costs.every(c => (cell.submitted[c.id] ?? 0) >= c.count)) {
                effects.defeated = true;
                delete cell.monster;
                delete cell.submitted;
                if (!monster.boss)
                    this.unlockBossFog(p);
                this.grant(copy, p, monster.drops, false, false, cell, effects.drops);
                if (monster.boss) {
                    p.stage++;
                    if (p.stage === this.config.stages.length)
                        p.completed = true;
                    else
                        this.setViewport(p, p.start_row + this.config.settings[0].advance);
                }
            }
        }
        p.version++;
        copy.version++;
        p.receipts.push({ request_id: body.request_id, signature, ...(effects ? { effects } : {}) });
        p.receipts = p.receipts.slice(-128);
        Object.assign(state, copy);
        return { ok: true, replayed: false, ...(effects ? { effects: structuredClone(effects) } : {}) };
    }
}
exports.SecretRealmService = SecretRealmService;
