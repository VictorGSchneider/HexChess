# hex_board.gd
# Tabuleiro hexagonal para HexChess — Godot 4.x
# Usa coordenadas axiais (q, r) para gerar um grid em formato de hexágono grande
# Baseado no layout Glinski (91 hexágonos) mas configurável

extends Node2D

# ============================================================
# CONFIGURAÇÃO
# ============================================================

## Raio do grid (quantos anéis ao redor do centro)
## 5 = Glinski (91 hexágonos), 4 = 61 hexágonos, 3 = 37 hexágonos
@export var board_radius: int = 5

## Tamanho de cada hexágono em pixels (do centro até um vértice)
@export var hex_size: float = 40.0

## Cores das 3 faixas do tabuleiro (como no xadrez hexagonal clássico)
@export var color_a: Color = Color("#f0d9b5")  # Clara
@export var color_b: Color = Color("#b58863")  # Média
@export var color_c: Color = Color("#8b6914")  # Escura

## Cor do contorno
@export var outline_color: Color = Color("#5a3e1b")
@export var outline_width: float = 1.5

## Cor de highlight (quando passa o mouse)
@export var highlight_color: Color = Color("#e9a319", 0.4)

## Cor de seleção (quando clica)
@export var select_color: Color = Color("#4ecdc4", 0.5)

# ============================================================
# VARIÁVEIS INTERNAS
# ============================================================

const PIECE_SCENE = preload("res://piece.tscn")
const PIECE_SCRIPT = preload("res://piece.gd")
const NULL_COORD = Vector2i(-999, -999)

# Dicionário principal: Vector2i(q, r) -> HexTile data
var tiles: Dictionary = {}

# Container para as peças (filho da scene)
@onready var pieces_container: Node2D = $Pieces

# Tile atualmente sob o mouse
var hovered_tile: Vector2i = NULL_COORD

# Tile selecionado (clicado)
var selected_tile: Vector2i = NULL_COORD

# Tiles com highlight de movimento válido
var valid_moves: Array[Vector2i] = []

# Turno atual (0 = brancas, 1 = pretas)
var current_turn: int = 0

signal turn_changed(turn: int)
signal piece_moved(from: Vector2i, to: Vector2i)
signal piece_captured(captured)

# ============================================================
# COORDENADAS AXIAIS — FUNDAMENTO
# ============================================================
# Em coordenadas axiais (q, r), a terceira coordenada s = -q - r
# Isso forma um grid hexagonal natural onde:
#   - q cresce pra direita
#   - r cresce pra baixo-direita  
#   - s cresce pra baixo-esquerda
#
# As 6 direções vizinhas em axial:
# Direita:        (+1,  0)    Esquerda:       (-1,  0)
# Cima-Direita:   (+1, -1)    Baixo-Esquerda: (-1, +1)
# Cima-Esquerda:  ( 0, -1)    Baixo-Direita:  ( 0, +1)

# Direções ortogonais (6)
const DIRECTIONS = [
	Vector2i(+1,  0), Vector2i(-1,  0),  # Direita, Esquerda
	Vector2i(+1, -1), Vector2i(-1, +1),  # Cima-Dir, Baixo-Esq
	Vector2i( 0, -1), Vector2i( 0, +1),  # Cima-Esq, Baixo-Dir
]

# Direções diagonais (6) — para bispos no xadrez hexagonal
const DIAGONALS = [
	Vector2i(+2, -1), Vector2i(-2, +1),  # Diag longas horizontais
	Vector2i(+1, -2), Vector2i(-1, +2),  # Diag longas verticais
	Vector2i(+1, +1), Vector2i(-1, -1),  # Diag curtas
]

# ============================================================
# INICIALIZAÇÃO
# ============================================================

func _ready():
	_generate_board()
	_setup_starting_position()
	# Centralizar o tabuleiro na tela
	position = get_viewport_rect().size / 2


func _generate_board():
	"""Gera todos os hexágonos dentro do raio do tabuleiro."""
	tiles.clear()
	
	for q in range(-board_radius, board_radius + 1):
		for r in range(-board_radius, board_radius + 1):
			var s = -q - r
			# Um hexágono pertence ao grid se max(|q|, |r|, |s|) <= radius
			if abs(q) <= board_radius and abs(r) <= board_radius and abs(s) <= board_radius:
				var coord = Vector2i(q, r)
				tiles[coord] = {
					"color_index": _get_color_index(q, r),
					"piece": null,  # Vai guardar a peça depois
				}
	
	print("Tabuleiro gerado: ", tiles.size(), " hexágonos")
	queue_redraw()


func _get_color_index(q: int, r: int) -> int:
	"""Determina a cor do hexágono (0, 1 ou 2) — garante 3 cores alternadas."""
	# Fórmula clássica para 3 cores em grid hexagonal
	var val = ((q % 3) + 3) % 3
	val = (val + ((r % 3) + 3) % 3) % 3
	return val


func _get_hex_color(color_index: int) -> Color:
	"""Retorna a cor baseada no índice (0, 1, 2)."""
	match color_index:
		0: return color_a
		1: return color_b
		2: return color_c
		_: return Color.WHITE

# ============================================================
# CONVERSÃO: AXIAL <-> PIXEL
# ============================================================

func axial_to_pixel(coord: Vector2i) -> Vector2:
	"""Converte coordenada axial (q, r) para posição em pixels."""
	# Layout flat-top (hexágono com vértice pra cima)
	var x = hex_size * (3.0 / 2.0 * coord.x)
	var y = hex_size * (sqrt(3.0) / 2.0 * coord.x + sqrt(3.0) * coord.y)
	return Vector2(x, y)


func pixel_to_axial(pixel: Vector2) -> Vector2i:
	"""Converte posição em pixels para coordenada axial (q, r) mais próxima."""
	# Converter pixel pra coordenadas fracionárias
	var q_frac = (2.0 / 3.0 * pixel.x) / hex_size
	var r_frac = (-1.0 / 3.0 * pixel.x + sqrt(3.0) / 3.0 * pixel.y) / hex_size
	
	# Arredondar para o hexágono mais próximo (cube rounding)
	return _axial_round(q_frac, r_frac)


func _axial_round(q_frac: float, r_frac: float) -> Vector2i:
	"""Arredonda coordenadas fracionárias para o hexágono mais próximo."""
	var s_frac = -q_frac - r_frac
	
	var q_round = round(q_frac)
	var r_round = round(r_frac)
	var s_round = round(s_frac)
	
	var q_diff = abs(q_round - q_frac)
	var r_diff = abs(r_round - r_frac)
	var s_diff = abs(s_round - s_frac)
	
	# Corrigir o componente com maior diferença
	if q_diff > r_diff and q_diff > s_diff:
		q_round = -r_round - s_round
	elif r_diff > s_diff:
		r_round = -q_round - s_round
	
	return Vector2i(int(q_round), int(r_round))

# ============================================================
# DESENHO
# ============================================================

func _draw():
	# Desenhar todos os hexágonos
	for coord in tiles:
		var center = axial_to_pixel(coord)
		var tile_data = tiles[coord]
		var color = _get_hex_color(tile_data["color_index"])
		
		_draw_hexagon(center, hex_size, color, outline_color, outline_width)
	
	# Desenhar highlights de movimentos válidos
	for coord in valid_moves:
		var center = axial_to_pixel(coord)
		_draw_hexagon(center, hex_size * 0.85, select_color, Color.TRANSPARENT, 0)
	
	# Desenhar highlight do hover
	if tiles.has(hovered_tile):
		var center = axial_to_pixel(hovered_tile)
		_draw_hexagon(center, hex_size, highlight_color, Color.WHITE, 2.0)
	
	# Desenhar seleção
	if tiles.has(selected_tile):
		var center = axial_to_pixel(selected_tile)
		_draw_hexagon(center, hex_size, select_color, Color.WHITE, 2.5)


func _draw_hexagon(center: Vector2, size: float, fill: Color, stroke: Color, stroke_w: float):
	"""Desenha um hexágono flat-top no centro dado."""
	var points = PackedVector2Array()
	
	for i in range(6):
		var angle_deg = 60 * i  # flat-top: começa em 0°
		var angle_rad = deg_to_rad(angle_deg)
		points.append(center + Vector2(cos(angle_rad), sin(angle_rad)) * size)
	
	# Preenchimento
	draw_colored_polygon(points, fill)
	
	# Contorno
	if stroke_w > 0 and stroke.a > 0:
		for i in range(6):
			draw_line(points[i], points[(i + 1) % 6], stroke, stroke_w, true)

# ============================================================
# INPUT — MOUSE
# ============================================================

func _input(event):
	if event is InputEventMouseMotion:
		# Converter posição do mouse pra coordenada axial
		var local_pos = (event.global_position - global_position)
		var coord = pixel_to_axial(local_pos)
		
		if coord != hovered_tile:
			hovered_tile = coord
			queue_redraw()
	
	elif event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var local_pos = (event.global_position - global_position)
			var coord = pixel_to_axial(local_pos)
			
			if tiles.has(coord):
				_on_tile_clicked(coord)


func _on_tile_clicked(coord: Vector2i):
	"""Chamado quando um tile é clicado."""
	var clicked_piece = _piece_at(coord)

	# Já há uma peça selecionada
	if selected_tile != NULL_COORD:
		# Mesmo tile → desseleciona
		if selected_tile == coord:
			_clear_selection()
			queue_redraw()
			return
		# Tile é um movimento válido → move
		if coord in valid_moves:
			_move_piece(selected_tile, coord)
			_clear_selection()
			_end_turn()
			queue_redraw()
			return
		# Senão, tenta selecionar outra peça do jogador atual
		if clicked_piece != null and clicked_piece.color == current_turn:
			_select_piece(coord)
			queue_redraw()
			return
		# Clique inválido → desseleciona
		_clear_selection()
		queue_redraw()
		return

	# Sem seleção: só seleciona peça do jogador da vez
	if clicked_piece != null and clicked_piece.color == current_turn:
		_select_piece(coord)
		queue_redraw()


func _select_piece(coord: Vector2i) -> void:
	var p = _piece_at(coord)
	selected_tile = coord
	if p != null:
		valid_moves = p.get_valid_moves()
	else:
		valid_moves.clear()


func _clear_selection() -> void:
	selected_tile = NULL_COORD
	valid_moves.clear()


func _end_turn() -> void:
	current_turn = 1 - current_turn
	turn_changed.emit(current_turn)

# ============================================================
# UTILITÁRIOS DE GRID
# ============================================================

func get_neighbors(coord: Vector2i) -> Array[Vector2i]:
	"""Retorna os vizinhos válidos de um hexágono."""
	var neighbors: Array[Vector2i] = []
	for dir in DIRECTIONS:
		var neighbor = coord + dir
		if tiles.has(neighbor):
			neighbors.append(neighbor)
	return neighbors


func get_diagonal_neighbors(coord: Vector2i) -> Array[Vector2i]:
	"""Retorna os vizinhos diagonais válidos (para bispos)."""
	var diags: Array[Vector2i] = []
	for dir in DIAGONALS:
		var neighbor = coord + dir
		if tiles.has(neighbor):
			diags.append(neighbor)
	return diags


func get_line(start: Vector2i, direction: Vector2i, max_dist: int = -1) -> Array[Vector2i]:
	"""Retorna todos os tiles em linha reta numa direção (para torres/bispos/dama)."""
	var line: Array[Vector2i] = []
	var current = start + direction
	var dist = 0
	
	while tiles.has(current):
		dist += 1
		if max_dist > 0 and dist > max_dist:
			break
		line.append(current)
		# Parar se encontrar uma peça (captura ou bloqueio)
		if tiles[current]["piece"] != null:
			break
		current = current + direction
	
	return line


func hex_distance(a: Vector2i, b: Vector2i) -> int:
	"""Distância entre dois hexágonos (em passos)."""
	var diff = a - b
	return (abs(diff.x) + abs(diff.x + diff.y) + abs(diff.y)) / 2


func is_valid_tile(coord: Vector2i) -> bool:
	"""Verifica se a coordenada é um tile válido do tabuleiro."""
	return tiles.has(coord)

# ============================================================
# PEÇAS — SPAWN / MOVIMENTO
# ============================================================

func _piece_at(coord: Vector2i):
	if not tiles.has(coord):
		return null
	return tiles[coord].get("piece", null)


func _spawn_piece(type: int, color: int, coord: Vector2i) -> Node2D:
	if not tiles.has(coord):
		push_warning("Tentativa de spawn fora do tabuleiro: %s" % str(coord))
		return null
	var piece = PIECE_SCENE.instantiate()
	pieces_container.add_child(piece)
	piece.setup(type, color, coord, self)
	piece.position = axial_to_pixel(coord)
	tiles[coord]["piece"] = piece
	return piece


func _move_piece(from: Vector2i, to: Vector2i) -> void:
	var piece = _piece_at(from)
	if piece == null:
		return
	var captured = _piece_at(to)
	if captured != null:
		piece_captured.emit(captured)
		tiles[to]["piece"] = null
		captured.queue_free()

	tiles[from]["piece"] = null
	tiles[to]["piece"] = piece
	piece.coord = to
	piece.has_moved = true
	piece.position = axial_to_pixel(to)
	piece_moved.emit(from, to)


# ============================================================
# POSIÇÃO INICIAL
# ============================================================

func _setup_starting_position() -> void:
	"""Layout simplificado (não-Glinski) para 91-hex board (raio 5).
	Brancas embaixo (r altos), pretas em cima (r baixos)."""
	var PT = PIECE_SCRIPT.PieceType
	var PC = PIECE_SCRIPT.PieceColor
	var back_rank = [PT.ROOK, PT.KNIGHT, PT.BISHOP, PT.QUEEN, PT.KING, PT.ROOK]

	# Brancas — back rank em r=5 (q = -5..0)
	for i in range(back_rank.size()):
		_spawn_piece(back_rank[i], PC.WHITE, Vector2i(-5 + i, 5))
	# Brancas — peões em r=4 (q = -5..1)
	for q in range(-5, 2):
		_spawn_piece(PT.PAWN, PC.WHITE, Vector2i(q, 4))

	# Pretas — back rank em r=-5 (q = 0..5), espelhado
	for i in range(back_rank.size()):
		_spawn_piece(back_rank[i], PC.BLACK, Vector2i(i, -5))
	# Pretas — peões em r=-4 (q = -1..5)
	for q in range(-1, 6):
		_spawn_piece(PT.PAWN, PC.BLACK, Vector2i(q, -4))
