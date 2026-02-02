extends Node

# --- DEBUG & SETTINGS ---
var screen_effects_enabled: bool = true
var gm_mode: bool = false
var show_unit_paths := true
var show_cell_outlines := true
var show_cell_occupancy := false

# --- GAMEPLAY CONSTANTS ---
const BASE_MOVE_COST = 20
const TILE_SIZE = 32 # Helps avoid magic numbers like '32' everywhere

# --- ENUMS (The Game's Dictionary) ---
enum TurnState { 
	PLAYER_TURN, 
	ENEMY_TURN, 
	PROCESSING, 
	VICTORY, 
	GAME_OVER 
}

enum DieType { D4 = 4, D6 = 6, D8 = 8, D10 = 10, D12 = 12, D20 = 20 }

enum DamageType { 
	RAW,
 	PHYSICAL,
 	FIRE,
 	WATER,
 	EARTH,
 	AIR
	}

const DAMAGE_COLORS = {
	DamageType.RAW: Color.GOLD,
	DamageType.PHYSICAL: Color.WHITE,
	DamageType.FIRE: Color.ORANGE,
	DamageType.WATER: Color.DEEP_SKY_BLUE,
	DamageType.EARTH: Color.SADDLE_BROWN,
	DamageType.AIR: Color.LIGHT_CYAN
	}

enum AreaShape { SQUARE, DIAMOND, CIRCLE }

enum ShakeType { NONE, SMALL, MID, BIG }
enum FreezeType { NONE, SMALL, MID, BIG }
enum ZoomType { NONE, SMALL, MID, BIG }

# Added for your Divinity-style surfaces
enum SurfaceType { 
	NONE, 
	FIRE, 
	WATER, 
	OIL, 
	ICE, 
	ELECTRIFIED 
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
