extends Resource
class_name CellData

enum SurfaceType { NONE, FIRE, WATER, OIL, ICE }
@export var is_wall: bool = false
@export var move_cost_multiplier: float = 1.0

var is_occupied: bool = false
var occupant: Node = null # This stores the Unit or WorldObject

# Environmental logic
var surface_vfx_node: WorldVFX = null
var surface_type: Globals.SurfaceType = Globals.SurfaceType.NONE
var surface_timer: int = 0
