# SurfaceData.gd
extends Resource
class_name SurfaceData

@export var type: Globals.SurfaceType
@export var buff_to_apply: BuffResource
@export var vfx_template: VisualEffectData
@export var default_duration: int = 3 # Default for attacks
