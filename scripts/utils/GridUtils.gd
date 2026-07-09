extends RefCounted
class_name GridUtils

# Check if two grid positions are neighbors (4-directional)
static func is_neighbor(a: Vector2i, b: Vector2i) -> bool:
	var diff := a - b
	return (abs(diff.x) + abs(diff.y)) == 1

# Manhattan distance between two positions
static func manhattan_distance(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)

# Direction from a to b (normalized)
static func direction(from: Vector2i, to: Vector2i) -> Vector2i:
	return Vector2i(sign(to.x - from.x), sign(to.y - from.y))

# Check if a position is within grid bounds
static func is_in_bounds(pos: Vector2i, cols: int, rows: int) -> bool:
	return pos.x >= 0 and pos.x < cols and pos.y >= 0 and pos.y < rows

# Grid position to local pixel position (top-left of cell)
static func grid_to_local(col: int, row: int, cell_size: int) -> Vector2:
	return Vector2(col * cell_size, row * cell_size)

# Local pixel position to grid position
static func local_to_grid(local_pos: Vector2, cell_size: int) -> Vector2i:
	return Vector2i(int(local_pos.x / cell_size), int(local_pos.y / cell_size))

# Item color from group_id and level
static func item_color(group_id: int, level: int) -> Color:
	var hue := 0.0
	match group_id:
		1:
			hue = float(level - 1) / 8.0
		2:
			hue = 0.25 + float(level - 1) / 6.0 * 0.15
		_:
			hue = float(level - 1) / 8.0
	return Color.from_hsv(hue, 0.6, 0.7)

# Launcher color from group_id
static func launcher_color(group_id: int) -> Color:
	match group_id:
		1:
			return Color(0.6, 0.3, 0.8, 1)
		2:
			return Color(1.0, 0.6, 0.2, 1)
		_:
			return Color(0.5, 0.5, 0.5, 1)
