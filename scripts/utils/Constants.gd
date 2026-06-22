extends RefCounted
class_name Constants

enum BoardType { MAIN = 0, BATTLE = 1 }

# Game dimensions — phone portrait (390×844)
const GRID_COLS := 7
const GRID_ROWS := 9
const CELL_SIZE := 100
const GRID_WIDTH := GRID_COLS * CELL_SIZE
const GRID_HEIGHT := GRID_ROWS * CELL_SIZE

# Animations
const MERGE_ANIM_DURATION := 0.3
const SPAWN_ANIM_DURATION := 0.25
const SNAP_BACK_DURATION := 0.2
