## Cafe grid, furniture footprint, walkability, seat tags and pathfinding (AStarGrid2D).
extends RefCounted

const Data = preload("res://scripts/core/data.gd")

const W := 18
const H := 12
const DOOR := Vector2i(9, 11)
const DOOR_IN := Vector2i(9, 10)
const GREET_SPOT := Vector2i(10, 10)
const RECEPTION_DESK := Vector2i(12, 10)
const STOVE1 := Vector2i(1, 1)
const STOVE2 := Vector2i(2, 1)
const COFFEE := Vector2i(4, 1)
const PASS_SLOTS := [Vector2i(1, 4), Vector2i(2, 4), Vector2i(3, 4), Vector2i(4, 4)]
const KITCHEN_WALL := [Vector2i(6, 1), Vector2i(6, 2), Vector2i(6, 3)]
const STAFF_WALL := [Vector2i(12, 1), Vector2i(12, 2)]
const SOFA := [Vector2i(15, 1), Vector2i(16, 1)]
const REST_SPOTS := [Vector2i(14, 2), Vector2i(15, 2), Vector2i(16, 2), Vector2i(13, 2), Vector2i(14, 3), Vector2i(16, 3)]
const WINDOW_SPOTS := [Vector2i(3, 10), Vector2i(14, 10), Vector2i(16, 8)]
const IDLE_SPOTS := {
	"reception": [Vector2i(11, 10), Vector2i(11, 9)],
	"kitchen": [Vector2i(3, 2), Vector2i(5, 2)],
	"floor": [Vector2i(5, 6), Vector2i(5, 7)],
	"support": [Vector2i(5, 8), Vector2i(9, 4)],
	"stage": [Vector2i(9, 3)],
	"off": [Vector2i(14, 3)],
}
const RESERVED := [Vector2i(9, 10), Vector2i(10, 10), Vector2i(8, 10), Vector2i(11, 10), Vector2i(1, 5), Vector2i(2, 5), Vector2i(3, 5),
	Vector2i(4, 5), Vector2i(5, 5), Vector2i(5, 4), Vector2i(12, 3), Vector2i(9, 9)]
const NEIGHBORS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const SEATING := ["table", "sofa_table"]

var furniture: Array
var upgrades: Dictionary
var kinds := {}             # key -> kind string
var furniture_at := {}      # key -> furniture dict
var tables: Array = []      # {id, type, cell, seats, tags}
var stations: Array = []    # {id, kind, cell, stand}
var stage_cells: Array = []
var astar := AStarGrid2D.new()

static func key(c: Vector2i) -> String:
	return "%d,%d" % [c.x, c.y]

static func manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func _init(p_furniture: Array, p_upgrades: Dictionary) -> void:
	furniture = p_furniture
	upgrades = p_upgrades
	rebuild()

func rebuild() -> void:
	kinds.clear()
	for x in W:
		for z in H:
			var edge := x == 0 or z == 0 or x == W - 1 or z == H - 1
			var k := "wall" if edge else "floor"
			if x >= 13 and x <= 16 and z >= 1 and z <= 3:
				k = "staff"
			kinds[key(Vector2i(x, z))] = k
	kinds[key(DOOR)] = "door"
	for c in [STOVE1, STOVE2, COFFEE, Vector2i(3, 1), Vector2i(5, 1)]:
		kinds[key(c)] = "kitchen"
	for c in PASS_SLOTS:
		kinds[key(c)] = "counter"
	for c in KITCHEN_WALL + STAFF_WALL:
		kinds[key(c)] = "wall"
	kinds[key(RECEPTION_DESK)] = "desk"
	if upgrades.get("sofa", false):
		for c in SOFA:
			kinds[key(c)] = "sofa"
	stations = [{"id": "stove1", "kind": "stove", "cell": STOVE1, "stand": Vector2i(1, 2)}]
	if upgrades.get("second_stove", false):
		stations.append({"id": "stove2", "kind": "stove", "cell": STOVE2, "stand": Vector2i(2, 2)})
	stations.append({"id": "coffee", "kind": "coffee", "cell": COFFEE, "stand": Vector2i(4, 2)})
	furniture_at.clear()
	tables.clear()
	stage_cells.clear()
	for f in furniture:
		var def: Dictionary = Data.FURNITURE[f.type]
		for off in def.fp:
			var c := Vector2i(int(f.x) + off[0], int(f.z) + off[1])
			furniture_at[key(c)] = f
			kinds[key(c)] = "furniture"
			if f.type == "stage":
				stage_cells.append(c)
		if f.type in SEATING:
			var seats := [Vector2i(int(f.x) - 1, int(f.z)), Vector2i(int(f.x) + 1, int(f.z))]
			for s in seats:
				kinds[key(s)] = "seat"
			tables.append({"id": f.id, "type": f.type, "cell": Vector2i(int(f.x), int(f.z)), "seats": seats, "tags": {}})
	_tag_tables()
	astar.region = Rect2i(0, 0, W, H)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.update()
	for x in W:
		for z in H:
			var c := Vector2i(x, z)
			astar.set_point_solid(c, not walkable(c))

## Seat tags drive customer seat preferences (window / quiet / bookshelf / sofa / stage / private).
func _tag_tables() -> void:
	for t in tables:
		var cells: Array = [t.cell] + t.seats
		var tags := {}
		for c in cells:
			if c.x <= 1 or c.x >= W - 2 or c.y >= H - 2:
				tags["window"] = true
		if t.type == "sofa_table":
			tags["sofa"] = true
		for f in furniture:
			var fc := Vector2i(int(f.x), int(f.z))
			var near := 99
			for c in cells:
				near = mini(near, manhattan(c, fc))
			if f.type == "bookshelf" and near <= 2:
				tags["bookshelf"] = true
			if f.type == "partition" and near <= 1:
				tags["private"] = true
			if f.type == "stage" and near <= 3:
				tags["stage"] = true
		var quiet := manhattan(t.cell, DOOR_IN) >= 6 and not tags.has("stage")
		if quiet or tags.has("private"):
			tags["quiet"] = true
		t.tags = tags

func kind_at(c: Vector2i) -> String:
	return kinds.get(key(c), "wall")

func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < W and c.y < H

func walkable(c: Vector2i) -> bool:
	var k := kind_at(c)
	return k == "floor" or k == "staff" or k == "door"

func adjacent_walkable(cells: Array) -> Array:
	var out := []
	var seen := {}
	for c in cells:
		for n in NEIGHBORS:
			var nc: Vector2i = c + n
			var k := key(nc)
			if not seen.has(k) and walkable(nc):
				seen[k] = true
				out.append(nc)
	return out

func table_by_id(id: String):
	for t in tables:
		if t.id == id:
			return t
	return null

func table_goals(id: String) -> Array:
	var t = table_by_id(id)
	if t == null:
		return []
	return adjacent_walkable([t.cell] + t.seats)

func furniture_cells(type: String) -> Array:
	var out := []
	for f in furniture:
		if f.type == type:
			out.append(Vector2i(int(f.x), int(f.z)))
	return out

## Shortest path from start to any of goals. Returns cells excluding start, or null when unreachable.
## allow_goal: goals may be non-walkable (chairs, stage); the last step enters them.
## avoid: cell keys to make expensive (other agents), used when re-routing around congestion.
func find_path(start: Vector2i, goals: Array, allow_goal := false, avoid := {}):
	if goals.is_empty():
		return null
	for g in goals:
		if g == start:
			return []
	var touched := []
	for k in avoid:
		var p: PackedStringArray = String(k).split(",")
		var c := Vector2i(int(p[0]), int(p[1]))
		if in_bounds(c) and walkable(c) and c != start:
			astar.set_point_weight_scale(c, 8.0)
			touched.append(c)
	var start_solid := astar.is_point_solid(start)
	if start_solid:
		astar.set_point_solid(start, false)
	var best = null
	var best_cost := INF
	for g in goals:
		var targets := [g]
		var tail = null
		if not walkable(g):
			if not allow_goal:
				continue
			targets = adjacent_walkable([g])
			tail = g
		for t in targets:
			if t == start:
				var p0 := [] if tail == null else [tail]
				if p0.size() < best_cost:
					best = p0
					best_cost = p0.size()
				continue
			var ids := astar.get_id_path(start, t)
			if ids.is_empty():
				continue
			var path := []
			for i in range(1, ids.size()):
				path.append(ids[i])
			if tail != null:
				path.append(tail)
			var cost := 0.0
			for c in path:
				cost += astar.get_point_weight_scale(c) if in_bounds(c) else 1.0
			if cost < best_cost:
				best_cost = cost
				best = path
	if start_solid:
		astar.set_point_solid(start, true)
	for c in touched:
		astar.set_point_weight_scale(c, 1.0)
	return best

func placeable(c: Vector2i) -> bool:
	if not in_bounds(c) or kind_at(c) != "floor":
		return false
	if c in RESERVED:
		return false
	if c.x <= 6 and c.y <= 4:
		return false
	return true

## Returns an error message, or "" when the placement is valid.
func can_place(type: String, x: int, z: int) -> String:
	var def: Dictionary = Data.FURNITURE[type]
	for off in def.fp:
		if not placeable(Vector2i(x + off[0], z + off[1])):
			return "這裡不能擺放。"
	if type == "stage":
		for f in furniture:
			if f.type == "stage":
				return "店裡只放得下一座舞台。"
	var test_f := furniture.duplicate()
	test_f.append({"id": "__test", "type": type, "x": x, "z": z})
	var test = get_script().new(test_f, upgrades)
	if not test.all_reachable():
		return "這樣會擋住走道，有地方走不到了。"
	return ""

func reachable_from(start: Vector2i) -> Dictionary:
	var seen := {key(start): true}
	var q := [start]
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		for n in NEIGHBORS:
			var nc: Vector2i = c + n
			var k := key(nc)
			if not seen.has(k) and walkable(nc):
				seen[k] = true
				q.append(nc)
	return seen

func all_reachable() -> bool:
	var reach := reachable_from(DOOR_IN)
	var need := [[GREET_SPOT], [REST_SPOTS[0]]]
	for s in stations:
		need.append([s.stand])
	for p in PASS_SLOTS:
		need.append(adjacent_walkable([p]))
	for t in tables:
		for s in t.seats:
			need.append(adjacent_walkable([s]))
	for f in furniture:
		if f.type in ["bookshelf", "vase", "display", "photo"]:
			need.append(adjacent_walkable([Vector2i(int(f.x), int(f.z))]))
	for group in need:
		var ok := false
		for c in group:
			if reach.has(key(c)):
				ok = true
				break
		if not ok:
			return false
	return true

## Simple flow metrics for the space-analysis panel.
func flow_metrics() -> Dictionary:
	var kitchen := []
	var door := []
	for t in tables:
		var goals := table_goals(t.id)
		var p1 = find_path(Vector2i(2, 5), goals)
		var p2 = find_path(DOOR_IN, goals)
		kitchen.append(p1.size() if p1 != null else 99)
		door.append(p2.size() if p2 != null else 99)
	var rest = find_path(Vector2i(5, 6), [REST_SPOTS[0]])
	var narrow := 0
	for x in range(1, W - 1):
		for z in range(5, H - 1):
			var c := Vector2i(x, z)
			if not walkable(c):
				continue
			var open := 0
			for n in NEIGHBORS:
				if walkable(c + n):
					open += 1
			if open <= 2:
				narrow += 1
	var avg := func(a: Array) -> float:
		var t := 0.0
		for v in a:
			t += v
		return t / maxf(1.0, a.size())
	return {
		"kitchen_avg": avg.call(kitchen), "kitchen_max": kitchen.max() if not kitchen.is_empty() else 0,
		"door_avg": avg.call(door), "rest": rest.size() if rest != null else 99, "narrow": narrow,
	}
