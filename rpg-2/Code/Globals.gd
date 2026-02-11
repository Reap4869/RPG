extends Node

# --- DEBUG & SETTINGS ---
var screen_effects_enabled: bool = true
var gm_mode: bool = false
var show_unit_paths := true
var show_cell_outlines := true
var show_cell_ocupancy := false
var play_footstep_sounds: bool = true


# --- GAMEPLAY CONSTANTS ---
const BASE_MOVE_COST = 20
const TILE_SIZE = 32 # Helps avoid magic numbers like '32' everywhere

enum GameMode { EXPLORATION, COMBAT }
var current_mode = GameMode.EXPLORATION

# --- ENUMS (The Game's Dictionary) ---
enum TurnState { 
	PLAYER_TURN, 
	ENEMY_TURN, 
	PROCESSING, 
	VICTORY, 
	GAME_OVER 
}

enum DieType { D4 = 4, D6 = 6, D8 = 8, D10 = 10, D12 = 12, D20 = 20 }

enum AttackCategory { PHYSICAL, SPELL }

enum ScalingStat { NONE, STRENGTH, INTELLIGENCE, AGILITY }

enum DamageType { 
	NONE,
	RAW,
 	PHYSICAL,
 	WATER,
 	EARTH,
	FIRE,
 	AIR,
	GRASS,
	POISON,
	ELECTRIC,
	DARK,
	LOVE,
	ICE,
	}

const DAMAGE_COLORS = {
	DamageType.RAW: Color.WHITE,
	DamageType.PHYSICAL: Color.DIM_GRAY,
	DamageType.WATER: Color.DEEP_SKY_BLUE,
	DamageType.EARTH: Color.SADDLE_BROWN,
	DamageType.FIRE: Color.ORANGE,
	DamageType.AIR: Color.LIGHT_CYAN,
	DamageType.GRASS: Color.WEB_GREEN,
	DamageType.POISON: Color.REBECCA_PURPLE,
	DamageType.ELECTRIC: Color.GOLDENROD,
	DamageType.DARK: Color.MIDNIGHT_BLUE,
	DamageType.LOVE: Color.HOT_PINK,
	DamageType.ICE: Color.LIGHT_SKY_BLUE,
	}

enum AreaShape {
	SQUARE,    # Chebyshev (max(|dx|,|dy|)) — square
	DIAMOND,   # Manhattan (|dx| + |dy|)
	LINE,      # Straight line in facing
	CLEAVE,    # Frontal semicircle / cone-like wide short attack
	CONE,      # Directional cone with fov angle
}

enum ShakeType { NONE, SMALL, MID, BIG }
enum FreezeType { NONE, SMALL, MID, BIG }
enum ZoomType { NONE, SMALL, MID, BIG }

enum SurfaceType { 
	NONE,
 	WATER,
 	EARTH,
	FIRE,
 	AIR,
	GRASS,
	POISON,
	ELECTRIC,
	DARK,
	LOVE,
	ICE,
}

# Use SurfaceData resources here so we can access .buff_to_apply
var SURFACES = {
	SurfaceType.FIRE: preload("res://Resources/Surfaces/FireSurfaceData.tres"),
	SurfaceType.WATER: preload("res://Resources/Surfaces/WaterSurfaceData.tres"),
	SurfaceType.POISON: preload("res://Resources/Surfaces/PoisonSurfaceData.tres"),
}

# --- STATE VARIABLES ---
var current_state: TurnState = TurnState.PLAYER_TURN

# --- HELPER FUNCTIONS ---
static func get_bbcode_color(type: DamageType) -> String:
	var color = DAMAGE_COLORS.get(type, Color.WHITE)
	return "#" + color.to_html(false) # Returns something like "#ff4500"

# Function to roll any die: e.g., Globals.roll(DieType.D8)
static func roll(die: DieType) -> int:
	return randi() % int(die) + 1
