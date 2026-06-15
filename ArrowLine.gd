extends Node2D

## Directed line segment used for targeting. Draws a shaft from points[0]
## to points[1] with an arrowhead at the end. Keeps the Line2D-style
## `points` API so existing callers keep working.

@export var width: float = 8.0:
	set(value):
		width = value
		queue_redraw()

@export var default_color: Color = Color(1, 0, 0, 1):
	set(value):
		default_color = value
		queue_redraw()

@export var arrow_length: float = 28.0
@export var arrow_width: float = 26.0

var points: PackedVector2Array = PackedVector2Array():
	set(value):
		points = value
		queue_redraw()

func _draw() -> void:
	if points.size() < 2:
		return
	var start: Vector2 = to_local(points[0])
	var end: Vector2 = to_local(points[1])
	var dir: Vector2 = end - start
	var dist: float = dir.length()
	if dist <= 0.001:
		return
	dir = dir / dist

	# Stop the shaft where the arrowhead begins so they don't overlap.
	var head_len: float = min(arrow_length, dist)
	var shaft_end: Vector2 = end - dir * head_len

	draw_line(start, shaft_end, default_color, width, true)

	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var base: Vector2 = end - dir * head_len
	var p1: Vector2 = base + perp * (arrow_width * 0.5)
	var p2: Vector2 = base - perp * (arrow_width * 0.5)
	draw_colored_polygon(PackedVector2Array([end, p1, p2]), default_color)
