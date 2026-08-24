class_name Crewman
extends Node2D

## A visible crew member riding a ship. The original's enemy ships are
## CREWED, never automated: one NPC always drives, the others man the
## turrets (and, awkwardly, the driver can also man turrets straight from
## the control panel — copied knowingly, see BACKLOG). This is the minimal
## faithful step: the gunner exists, stands at his gun, and the turret
## only fires while he is aboard. He cannot yet be fought — characters are
## not shot geometry — so boarding-to-silence-the-guns arrives with
## Sprint 4's real NPCs.

var ship: Ship = null
## Where he stands, in ship-local px.
var local_pos := Vector2.ZERO
var body_size := Vector2(10.0, 18.0)
## "driver" holds the panel; "gunner" makes the turret fire.
var role := "gunner"


func _process(_delta: float) -> void:
	if ship == null or not is_instance_valid(ship):
		queue_free()  # his ship is gone; so is he
		return
	global_position = ship.to_global(local_pos)
	rotation = ship.rotation
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(-body_size * 0.5, body_size)
	draw_rect(rect, Color(0.75, 0.25, 0.22))
	draw_rect(rect, Color(0.40, 0.10, 0.08), false, 1.0)
