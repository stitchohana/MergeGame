import sys

def replace_in_file(path, old, new, label):
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()
    if old in content:
        content = content.replace(old, new)
        with open(path, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f'  {label}: OK')
        return True
    else:
        print(f'  {label}: NOT FOUND')
        return False

# === Server: game_engine.ts ===
path = 'D:/GodotProject/MergeGame2/MergeGame/server/src/engine/game_engine.ts'

# 1. Fix pouchDeposit
replace_in_file(path,
    ' const idx = state.grid.findIndex((g) => g.uid === uid);\n'
    ' if (idx < 0) return { ok: false, reason: "item_not_found" };\n'
    ' const itemId = state.grid[idx].id;\n'
    ' state.grid.splice(idx, 1);\n'
    ' state.pouch.push(itemId);\n'
    ' console.log(`[engine] pouch deposit: #${itemId} (uid=${uid}) | pouch=${state.pouch.length} items`);\n'
    ' return { ok: true, pouch: state.pouch };',
    ' const idx = state.grid.findIndex((g) => g.uid === uid);\n'
    ' if (idx < 0) return { ok: false, reason: "item_not_found" };\n'
    ' const item = state.grid[idx];\n'
    ' state.grid.splice(idx, 1);\n'
    ' state.pouch.push({ uid: item.uid!, id: item.id });\n'
    ' console.log(`[engine] pouch deposit: #${item.id} (uid=${item.uid}) | pouch=${state.pouch.length} items`);\n'
    ' return { ok: true, pouch: state.pouch };',
    'pouchDeposit')

# 2. Fix pouchWithdraw
replace_in_file(path,
    ' pouchWithdraw(\n'
    ' state: GameState,\n'
    ' itemId: number,\n'
    ' col: number,\n'
    ' row: number\n'
    ' ): { ok: true; pouch: number[] } | { ok: false; reason: string } {\n'
    ' const idx = state.pouch.indexOf(itemId);\n'
    ' if (idx < 0) return { ok: false, reason: "item_not_in_pouch" };\n'
    ' if (!this.isInBounds(col, row)) return { ok: false, reason: "invalid_position" };\n'
    ' if (state.grid.some((g) => g.col === col && g.row === row)) return { ok: false, reason: "cell_occupied" };\n'
    ' state.pouch.splice(idx, 1);\n'
    ' state.grid.push({ uid: this._nextUid(state), id: itemId, col, row }); console.log(`[engine] pouch withdraw: #${itemId} at (${col},${row}) | pouch=${state.pouch.length} items`);\n'
    ' return { ok: true, pouch: state.pouch };',
    ' pouchWithdraw(\n'
    ' state: GameState,\n'
    ' uid: number,\n'
    ' col: number,\n'
    ' row: number\n'
    ' ): { ok: true; pouch: PouchItem[] } | { ok: false; reason: string } {\n'
    ' const idx = state.pouch.findIndex((p) => p.uid === uid);\n'
    ' if (idx < 0) return { ok: false, reason: "item_not_in_pouch" };\n'
    ' if (!this.isInBounds(col, row)) return { ok: false, reason: "invalid_position" };\n'
    ' if (state.grid.some((g) => g.col === col && g.row === row)) return { ok: false, reason: "cell_occupied" };\n'
    ' const item = state.pouch[idx];\n'
    ' state.pouch.splice(idx, 1);\n'
    ' state.grid.push({ uid: item.uid, id: item.id, col, row });\n'
    ' console.log(`[engine] pouch withdraw: #${item.id} (uid=${item.uid}) at (${col},${row}) | pouch=${state.pouch.length} items`);\n'
    ' return { ok: true, pouch: state.pouch };',
    'pouchWithdraw')

# 3. Fix addIngredientToTable - store uid
replace_in_file(path,
    ' craft._craft_stored.push({ id: ingredientId } as Record<string, unknown>);',
    ' craft._craft_stored.push({ uid: gridItem.uid!, id: ingredientId });',
    'addIngredientToTable stored')

# 4. Fix removeIngredientFromTable
replace_in_file(path,
    ' removeIngredientFromTable(\n'
    ' state: GameState,\n'
    ' tableCol: number,\n'
    ' tableRow: number,\n'
    ' ingredientId: number,\n'
    ' targetCol: number,\n'
    ' targetRow: number\n'
    ' ): { ok: true; } | { ok: false; reason: string } {',
    ' removeIngredientFromTable(\n'
    ' state: GameState,\n'
    ' tableCol: number,\n'
    ' tableRow: number,\n'
    ' uid: number,\n'
    ' targetCol: number,\n'
    ' targetRow: number\n'
    ' ): { ok: true; } | { ok: false; reason: string } {',
    'removeIngredientFromTable signature')

replace_in_file(path,
    ' const stored: Record<string, unknown>[] = craft._craft_stored;\n'
    ' const idx = stored.findIndex((s: any) => s.id === ingredientId);\n'
    ' if (idx < 0) return { ok: false, reason: "ingredient_not_in_table" };',
    ' const stored = craft._craft_stored;\n'
    ' const idx = stored.findIndex((s) => s.uid === uid);\n'
    ' if (idx < 0) return { ok: false, reason: "ingredient_not_in_table" };',
    'removeIngredientFromTable find')

replace_in_file(path,
    ' const ingName = this.getItemData(ingredientId)?.name ?? ("#" + ingredientId);\n'
    ' console.log(`[engine] craft remove: ${ingName} from table -> grid (${targetCol},${targetRow}) | stored=${stored.length}`);',
    ' const removedItem = stored[idx];\n'
    ' const ingName = this.getItemData(removedItem.id)?.name ?? ("#" + removedItem.id);\n'
    ' console.log(`[engine] craft remove: ${ingName} (uid=${removedItem.uid}) from table -> grid (${targetCol},${targetRow}) | stored=${stored.length}`);',
    'removeIngredientFromTable name')

replace_in_file(path,
    ' state.grid.push({ uid: this._nextUid(state), id: ingredientId, col: targetCol, row: targetRow });',
    ' state.grid.push({ uid: removedItem.uid, id: removedItem.id, col: targetCol, row: targetRow });',
    'removeIngredientFromTable push')

# 5. Fix duplicate check
replace_in_file(path,
    ' if (craft._craft_stored.some((s: any) => s.id === ingredientId)) {',
    ' if (craft._craft_stored.some((s) => s.id === ingredientId)) {',
    'duplicate check type')

# 6. Fix matchRecipe
replace_in_file(path,
    ' private matchRecipe(\n'
    ' stored: Record<string, unknown>[],\n'
    ' recipes: RecipeDef[]\n'
    ' ): RecipeDef | null {\n'
    ' const storedCounts = new Map<number, number>();\n'
    ' for (const item of stored) {\n'
    ' const id = item.id as number;\n'
    ' storedCounts.set(id, (storedCounts.get(id) || 0) + 1);\n'
    ' }',
    ' private matchRecipe(\n'
    ' stored: PouchItem[],\n'
    ' recipes: RecipeDef[]\n'
    ' ): RecipeDef | null {\n'
    ' const storedCounts = new Map<number, number>();\n'
    ' for (const item of stored) {\n'
    ' const id = item.id;\n'
    ' storedCounts.set(id, (storedCounts.get(id) || 0) + 1);\n'
    ' }',
    'matchRecipe')

# === Server: routes/game.ts ===
path2 = 'D:/GodotProject/MergeGame2/MergeGame/server/src/routes/game.ts'

replace_in_file(path2,
    ' const { item_id, target_col, target_row } = req.body;\n'
    ' if (typeof item_id !== "number" || typeof target_col !== "number" || typeof target_row !== "number") {',
    ' const { uid, target_col, target_row } = req.body;\n'
    ' if (typeof uid !== "number" || typeof target_col !== "number" || typeof target_row !== "number") {',
    'routes pouch/withdraw params')

replace_in_file(path2,
    ' const result = engine.pouchWithdraw(state, item_id, target_col, target_row);',
    ' const result = engine.pouchWithdraw(state, uid, target_col, target_row);',
    'routes pouch/withdraw call')

replace_in_file(path2,
    ' const { table_col, table_row, ingredient_id, target_col, target_row } = req.body;\n'
    ' if (typeof table_col !== "number" || typeof table_row !== "number" || typeof ingredient_id !== "number" || typeof target_col !== "number" || typeof target_row !== "number") {',
    ' const { table_col, table_row, uid, target_col, target_row } = req.body;\n'
    ' if (typeof table_col !== "number" || typeof table_row !== "number" || typeof uid !== "number" || typeof target_col !== "number" || typeof target_row !== "number") {',
    'routes craft/remove params')

replace_in_file(path2,
    ' const result = engine.removeIngredientFromTable(state, table_col, table_row, ingredient_id, target_col, target_row);',
    ' const result = engine.removeIngredientFromTable(state, table_col, table_row, uid, target_col, target_row);',
    'routes craft/remove call')

# Also update craft/remove body log
replace_in_file(path2,
    'console.log(`[craft/remove] body:`, JSON.stringify(req.body));\n    ',
    '',
    'routes craft/remove body log removal')

# === Client: CloudService.gd ===
path3 = 'D:/GodotProject/MergeGame2/MergeGame/autoload/CloudService.gd'

replace_in_file(path3,
    'func submit_pouch_withdraw(item_id: int, target_col: int, target_row: int) -> void:\n'
    '\tvar body := JSON.stringify({"item_id": item_id, "target_col": target_col, "target_row": target_row})',
    'func submit_pouch_withdraw(uid: int, target_col: int, target_row: int) -> void:\n'
    '\tvar body := JSON.stringify({"uid": uid, "target_col": target_col, "target_row": target_row})',
    'CloudService pouch_withdraw')

# === Client: StoragePouch.gd ===
path4 = 'D:/GodotProject/MergeGame2/MergeGame/autoload/StoragePouch.gd'

replace_in_file(path4,
    'var _pending_withdraw_id: int = 0',
    'var _pending_withdraw_uid: int = 0',
    'StoragePouch field')

replace_in_file(path4,
    'func withdraw(item_id: int, target_pos: Vector2i) -> void:\n'
    '\t_pending_withdraw_id = item_id\n'
    '\t_pending_withdraw_pos = target_pos\n'
    '\tCloudService.submit_pouch_withdraw(item_id, target_pos.x, target_pos.y)',
    'func withdraw(uid: int, target_pos: Vector2i) -> void:\n'
    '\t_pending_withdraw_uid = uid\n'
    '\t_pending_withdraw_pos = target_pos\n'
    '\tCloudService.submit_pouch_withdraw(uid, target_pos.x, target_pos.y)',
    'StoragePouch withdraw')

replace_in_file(path4,
    '_pending_withdraw_id = 0',
    '_pending_withdraw_uid = 0',
    'StoragePouch reset')

# Update the _on_withdraw_confirmed to use uid
replace_in_file(path4,
    'if _pending_withdraw_id > 0:\n'
    '\t\tvar item_data := ConfigDatabase.get_item_data(_pending_withdraw_id)',
    'if _pending_withdraw_uid > 0:\n'
    '\t\tvar pouch_entry: Dictionary = {}\n'
    '\t\tfor p in items:\n'
    '\t\t\tif p.get("uid", 0) == _pending_withdraw_uid:\n'
    '\t\t\t\tpouch_entry = p\n'
    '\t\t\t\tbreak\n'
    '\t\tvar item_id: int = pouch_entry.get("id", 0) as int\n'
    '\t\tvar item_data := ConfigDatabase.get_item_data(item_id)')

print('\nDone!')
