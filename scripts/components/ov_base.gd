class_name OvBase
extends Node2D
## 覆盖层基类：统一遮罩、面板命中、点击外部关闭、Esc 关闭。

var main: Node
var _hover := Vector2(-1, -1)

func _process(delta: float) -> void:
	_on_tick(delta)
	queue_redraw()

func _on_tick(_delta: float) -> void:
	pass

func vp() -> Vector2:
	return get_viewport_rect().size

func panel_rect() -> Rect2:
	return Rect2(0, 0, 0, 0)

func close() -> void:
	main.close_overlay()

func handle_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not panel_rect().has_point(event.position):
			_on_outside_click()
			return
		_on_click(event.position)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_escape()

func _on_click(_pos: Vector2) -> void:
	pass

func _on_outside_click() -> void:
	close()

func _on_escape() -> void:
	close()
