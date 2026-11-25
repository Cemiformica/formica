# --- Añadir a player.gd (C5.6, césped) ---

## Nombre del parámetro global del shader del césped (Project Settings → Shader Globals).
const GRASS_PLAYER_PARAM: StringName = &"player_position"


# Llamarlo al final de _physics_process (o en _process, si ya lo tiene):
func _update_grass_push() -> void:
	# global_position es el de los pies de Mira: el shader compara con la raíz de cada brizna.
	RenderingServer.global_shader_parameter_set(GRASS_PLAYER_PARAM, global_position)
