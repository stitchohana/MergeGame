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
