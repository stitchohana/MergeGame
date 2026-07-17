extends RefCounted
class_name Constants

enum BoardType { MAIN = 0, BATTLE = 1 }

enum ItemType { REGULAR = 0, LAUNCHER = 1, CRAFTING = 2, RECIPE_PRODUCT = 4, EFFECT = 5 }

enum EffectType { NONE = 0, DAMAGE = 1, HEAL = 2, EXP = 3, STAMINA = 4, BREAKTHROUGH = 5, QI = 6, ATK_BOOST = 7 }

enum TokenType { SPIRIT_STONES = 1, QI = 2, STAMINA = 3, EXP = 4 }

const TOKEN_NAMES := {
	TokenType.SPIRIT_STONES: "灵石",
	TokenType.QI: "灵力",
	TokenType.STAMINA: "体力",
	TokenType.EXP: "经验值",
}

enum ResetCycle { NEVER = 0, DAILY = 1, WEEKLY = 2 }

enum ActivityCycle { ONCE = 0, DAILY = 1, WEEKLY = 2, MONTHLY = 3 }

enum QuestType {
	MERGE = 1,
	SPAWN = 2,
	CRAFT = 3,
	SELL = 4,
	BATTLE_ATTACK = 5,
	BATTLE_CLEAR = 6,
	BREAKTHROUGH = 7,
	ANY_ITEM_CONSUME = 8,
	MERIDIAN_CIRCULATION = 9,
}

# Game dimensions — phone portrait (390×844)
const GRID_COLS := 7
const GRID_ROWS := 9
const CELL_SIZE := 86
const CELL_GAP := 3
const CELL_STEP := CELL_SIZE + CELL_GAP
const GRID_WIDTH := GRID_COLS * CELL_STEP - CELL_GAP
const GRID_HEIGHT := GRID_ROWS * CELL_STEP - CELL_GAP

# Animations
const MERGE_ANIM_DURATION := 0.3
const SPAWN_ANIM_DURATION := 0.25
const SNAP_BACK_DURATION := 0.2

# Check if an item has launcher config fields (spawns + max_charges)
static func has_launcher_config(item_data: Dictionary) -> bool:
	var spawns: Array = item_data.get("spawns", [])
	var max_charges: int = item_data.get("max_charges", 0) as int
	return not spawns.is_empty() and max_charges > 0
