# game_manager.gd
# Gerenciador principal do HexChess - Godot 4.x
# Integra hex_board.gd + piece.gd, controla turnos, xeque e regras

extends Node2D

# =============================================
# SINAIS
# =============================================

signal turn_changed(current_color: int)
signal piece_moved(piece_type: int, from_coord: Vector2i, to_coord: Vector2i)
signal piece_captured(captured_type: int, captured_color: int)
signal check_declared(king_color: int)
signal checkmate(loser_color: int)
signal stalemate()
signal sentinel_toggled(coord: Vector2i, is_blocking: bool)
signal spy_revealed(coord: Vector2i)
signal portal_created(coord: Vector2i)

# =============================================
# REFERENCIAS
# =============================================

@onready var board: Node2D = $HexBoard  # hex_board.gd

# =============================================
# ESTADO DO JOGO
# =============================================

var current_turn: int = 0  # PieceColor.WHITE
var pieces: Array = []  # Todas as pecas vivas
var captured_white: Array = []  # Pecas brancas capturadas
var captured_black: Array = []  # Pecas pretas capturadas
var selected_piece = null  # Peca selecionada pelo jogador
var valid_moves_cache: Array[Vector2i] = []
var move_history: Array = []  # Historico pra IA e undo
var game_over: bool = false

# Portais ativos (max 2 por cor)
var portals_white: Array = []
var portals_black: Array = []

# =============================================
# SETUP INICIAL
# =============================================

func _ready():
	board.connect("tile_clicked", _on_tile_clicked)
	_setup_pieces()


func _setup_pieces():
	# Posicionamento Glinski (radius=5, 91 hexagonos)
	# Adaptado pra incluir pecas hibridas e ineditas
	# Brancas embaixo (r positivo), pretas em cima (r negativo)

	# --- BRANCAS ---
	_place(0, "KING", 0, Vector2i(0, 4))
	_place(0, "QUEEN", 0, Vector2i(-1, 4))
	_place(0, "BISHOP", 0, Vector2i(0, 3))
	_place(0, "BISHOP", 0, Vector2i(1, 3))
	_place(0, "BISHOP", 0, Vector2i(-1, 3))
	_place(0, "KNIGHT", 0, Vector2i(2, 3))
	_place(0, "KNIGHT", 0, Vector2i(-2, 4))
	_place(0, "ROOK", 0, Vector2i(3, 2))
	_place(0, "ROOK", 0, Vector2i(-3, 5))
	# Hibridas
	_place(0, "ARCHBISHOP", 0, Vector2i(1, 4))
	_place(0, "CHANCELLOR", 0, Vector2i(-2, 5))
	# Ineditas
	_place(0, "SENTINEL", 0, Vector2i(2, 4))
	_place(0, "SPY", 0, Vector2i(-3, 4))
	_place(0, "PORTAL", 0, Vector2i(3, 3))
	_place(0, "PORTAL", 0, Vector2i(-4, 5))
	# Peoes
	for q in range(-4, 5):
		var r = 2
		if board.is_valid_tile(Vector2i(q, r)):
			_place(0, "PAWN", 0, Vector2i(q, r))

	# --- PRETAS (espelhado) ---
	_place(0, "KING", 1, Vector2i(0, -4))
	_place(0, "QUEEN", 1, Vector2i(1, -4))
	_place(0, "BISHOP", 1, Vector2i(0, -3))
	_place(0, "BISHOP", 1, Vector2i(-1, -3))
	_place(0, "BISHOP", 1, Vector2i(1, -3))
	_place(0, "KNIGHT", 1, Vector2i(-2, -3))
	_place(0, "KNIGHT", 1, Vector2i(2, -4))
	_place(0, "ROOK", 1, Vector2i(-3, -2))
	_place(0, "ROOK", 1, Vector2i(3, -5))
	# Hibridas
	_place(0, "ARCHBISHOP", 1, Vector2i(-1, -4))
	_place(0, "CHANCELLOR", 1, Vector2i(2, -5))
	# Ineditas
	_place(0, "SENTINEL", 1, Vector2i(-2, -4))
	_place(0, "SPY", 1, Vector2i(3, -4))
	_place(0, "PORTAL", 1, Vector2i(-3, -3))
	_place(0, "PORTAL", 1, Vector2i(4, -5))
	# Peoes
	for q in range(-4, 5):
		var r = -2
		if board.is_valid_tile(Vector2i(q, r)):
			_place(0, "PAWN", 1, Vector2i(q, r))

	print("Pecas posicionadas: ", pieces.size())


func _place(_unused: int, type_name: String, color_val: int, coord: Vector2i):
	# Cria e posiciona uma peca no tabuleiro
	var piece_scene = preload("res://piece.tscn")  # Cena da peca
	var piece = piece_scene.instantiate()
	piece.type = piece.PieceType[type_name]
	piece.color = color_val  # 0=WHITE, 1=BLACK
	piece.coord = coord
	piece.board = board
	piece.position = board.axial_to_pixel(coord)

	# Registrar no tile do board
	if board.tiles.has(coord):
		board.tiles[coord]["piece"] = piece

	pieces.append(piece)
	add_child(piece)

	# Registrar portais
	if type_name == "PORTAL":
		if color_val == 0:
			portals_white.append(piece)
			if portals_white.size() == 2:
				portals_white[0].portal_pair_coord = portals_white[1].coord
				portals_white[1].portal_pair_coord = portals_white[0].coord
		else:
			portals_black.append(piece)
			if portals_black.size() == 2:
				portals_black[0].portal_pair_coord = portals_black[1].coord
				portals_black[1].portal_pair_coord = portals_black[0].coord

# =============================================
# LOGICA DE TURNO
# =============================================

func _on_tile_clicked(coord: Vector2i):
	if game_over:
		return

	var piece_on_tile = _get_piece_at(coord)

	if selected_piece == null:
		# Nenhuma peca selecionada - tentar selecionar
		if piece_on_tile != null and piece_on_tile.color == current_turn:
			_select_piece(piece_on_tile)
	else:
		# Peca ja selecionada
		if coord == selected_piece.coord:
			# Clicou na mesma peca
			if selected_piece.type == selected_piece.PieceType.SENTINEL:
				_toggle_sentinel(selected_piece)
				_deselect()
				_end_turn()
			elif selected_piece.type == selected_piece.PieceType.SPY and not selected_piece.is_revealed:
				_reveal_spy(selected_piece)
				_deselect()
				_end_turn()
			elif selected_piece.type == selected_piece.PieceType.PORTAL:
				_activate_portal(selected_piece)
				_deselect()
				_end_turn()
			else:
				_deselect()
		elif coord in valid_moves_cache:
			# Movimento valido
			_execute_move(selected_piece, coord)
		elif piece_on_tile != null and piece_on_tile.color == current_turn:
			# Clicou em outra peca aliada - trocar selecao
			_select_piece(piece_on_tile)
		else:
			_deselect()


func _select_piece(piece):
	selected_piece = piece
	valid_moves_cache = _get_legal_moves(piece)
	board.valid_moves = valid_moves_cache
	board.selected_tile = piece.coord
	board.queue_redraw()


func _deselect():
	selected_piece = null
	valid_moves_cache.clear()
	board.valid_moves.clear()
	board.selected_tile = Vector2i(-999, -999)
	board.queue_redraw()


func _end_turn():
	current_turn = 1 - current_turn  # Alterna WHITE/BLACK
	emit_signal("turn_changed", current_turn)

	# Verificar xeque/xeque-mate
	if _is_in_check(current_turn):
		emit_signal("check_declared", current_turn)
		if _is_checkmate(current_turn):
			emit_signal("checkmate", current_turn)
			game_over = true
			return
	elif _is_stalemate(current_turn):
		emit_signal("stalemate")
		game_over = true
		return

	# Auto-revelar espiao se adjacente a inimigo
	_check_spy_auto_reveal(current_turn)

# =============================================
# EXECUCAO DE MOVIMENTO
# =============================================

func _execute_move(piece, target: Vector2i):
	var from = piece.coord
	var captured = _get_piece_at(target)

	# Captura
	if captured != null:
		_capture_piece(captured)

	# Atualizar board
	board.tiles[from]["piece"] = null
	board.tiles[target]["piece"] = piece

	# Atualizar peca
	piece.coord = target
	piece.position = board.axial_to_pixel(target)
	piece.has_moved = true

	# Atualizar portal pair coords se for portal
	if piece.type == piece.PieceType.PORTAL:
		_update_portal_pairs(piece)

	# Historico
	move_history.append({
		"piece": piece,
		"from": from,
		"to": target,
		"captured": captured,
		"turn": current_turn,
	})

	emit_signal("piece_moved", piece.type, from, target)

	# Promocao de peao
	if piece.type == piece.PieceType.PAWN:
		if _should_promote(piece):
			_promote_pawn(piece)

	# Verificar sentinelas inimigas (bloqueio)
	# (movimentos ja filtrados em _get_legal_moves)

	_deselect()
	_end_turn()


func _capture_piece(piece):
	if piece.color == 0:
		captured_white.append(piece)
	else:
		captured_black.append(piece)

	board.tiles[piece.coord]["piece"] = null
	pieces.erase(piece)

	# Se portal capturado, remover o par tambem
	if piece.type == piece.PieceType.PORTAL:
		_remove_portal_pair(piece)

	emit_signal("piece_captured", piece.type, piece.color)
	piece.queue_free()

# =============================================
# XEQUE E XEQUE-MATE
# =============================================

func _is_in_check(color_val: int) -> bool:
	# Encontrar o rei da cor
	var king_coord = _find_king(color_val)
	if king_coord == Vector2i(-999, -999):
		return false
	# Verificar se alguma peca inimiga ataca o rei
	return _is_tile_attacked(king_coord, 1 - color_val)


func _is_tile_attacked(target: Vector2i, by_color: int) -> bool:
	# Verifica se alguma peca da cor dada pode atacar o tile
	for piece in pieces:
		if piece.color == by_color:
			var moves = piece.get_valid_moves()
			if target in moves:
				return true
	return false


func _find_king(color_val: int) -> Vector2i:
	for piece in pieces:
		if piece.type == piece.PieceType.KING and piece.color == color_val:
			return piece.coord
	return Vector2i(-999, -999)


func _get_legal_moves(piece) -> Array[Vector2i]:
	# Movimentos validos que NAO deixam o proprio rei em xeque
	var pseudo_moves = piece.get_valid_moves()
	var legal: Array[Vector2i] = []

	# Filtrar tiles bloqueados por Sentinela inimiga
	var blocked = _get_all_blocked_tiles(1 - piece.color)

	for target in pseudo_moves:
		# Ignorar tiles bloqueados (exceto se for a Sentinela inimiga em si)
		if target in blocked:
			var blocker = _get_piece_at(target)
			if blocker == null or blocker.type != blocker.PieceType.SENTINEL:
				continue

		# Simular o movimento e verificar se o rei fica em xeque
		if not _would_leave_in_check(piece, target):
			legal.append(target)

	return legal


func _would_leave_in_check(piece, target: Vector2i) -> bool:
	# Simula o movimento temporariamente
	var from = piece.coord
	var captured = _get_piece_at(target)

	# Fazer movimento
	board.tiles[from]["piece"] = null
	board.tiles[target]["piece"] = piece
	piece.coord = target
	if captured != null:
		pieces.erase(captured)

	# Verificar xeque
	var in_check = _is_in_check(piece.color)

	# Desfazer
	piece.coord = from
	board.tiles[from]["piece"] = piece
	board.tiles[target]["piece"] = captured
	if captured != null:
		pieces.append(captured)

	return in_check


func _is_checkmate(color_val: int) -> bool:
	# Xeque-mate: esta em xeque E nao tem nenhum movimento legal
	if not _is_in_check(color_val):
		return false
	return not _has_any_legal_move(color_val)


func _is_stalemate(color_val: int) -> bool:
	# Afogamento: NAO esta em xeque mas nao tem movimentos legais
	if _is_in_check(color_val):
		return false
	return not _has_any_legal_move(color_val)


func _has_any_legal_move(color_val: int) -> bool:
	for piece in pieces:
		if piece.color == color_val:
			var moves = _get_legal_moves(piece)
			if moves.size() > 0:
				return true
	return false

# =============================================
# MECANICAS ESPECIAIS
# =============================================

func _toggle_sentinel(piece):
	piece.is_blocking = not piece.is_blocking
	emit_signal("sentinel_toggled", piece.coord, piece.is_blocking)


func _reveal_spy(piece):
	piece.is_revealed = true
	emit_signal("spy_revealed", piece.coord)


func _check_spy_auto_reveal(color_val: int):
	# Auto-revela espioes se adjacentes a pecas inimigas
	for piece in pieces:
		if piece.type == piece.PieceType.SPY and piece.color == color_val and not piece.is_revealed:
			for d in piece.DIR_ORTHO:
				var neighbor = piece.coord + d
				var np = _get_piece_at(neighbor)
				if np != null and np.color != color_val:
					piece.is_revealed = true
					emit_signal("spy_revealed", piece.coord)
					break


func _activate_portal(piece):
	# Marca o tile atual como portal
	emit_signal("portal_created", piece.coord)


func _update_portal_pairs(moved_portal):
	# Atualizar coordenadas do par quando um portal se move
	var portal_list = portals_white if moved_portal.color == 0 else portals_black
	if portal_list.size() == 2:
		portal_list[0].portal_pair_coord = portal_list[1].coord
		portal_list[1].portal_pair_coord = portal_list[0].coord


func _remove_portal_pair(captured_portal):
	# Quando um portal e capturado, o par perde a conexao
	var portal_list = portals_white if captured_portal.color == 0 else portals_black
	portal_list.erase(captured_portal)
	for p in portal_list:
		p.portal_pair_coord = Vector2i(-999, -999)


func _get_all_blocked_tiles(by_color: int) -> Array[Vector2i]:
	# Retorna todos os tiles bloqueados por Sentinelas de uma cor
	var blocked: Array[Vector2i] = []
	for piece in pieces:
		if piece.type == piece.PieceType.SENTINEL and piece.color == by_color:
			blocked.append_array(piece.get_sentinel_blocked_tiles())
	return blocked


func _should_promote(pawn) -> bool:
	# Peao promove ao chegar na borda oposta
	var r = pawn.coord.y
	if pawn.color == 0 and r <= -board.board_radius + 1:
		return true
	if pawn.color == 1 and r >= board.board_radius - 1:
		return true
	return false


func _promote_pawn(pawn):
	# TODO: UI pra escolher peca de promocao
	# Por enquanto promove pra Dama automaticamente
	pawn.type = pawn.PieceType.QUEEN
	print("Peao promovido a Dama em ", pawn.coord)

# =============================================
# UTILITARIOS
# =============================================

func _get_piece_at(coord: Vector2i):
	if not board.tiles.has(coord):
		return null
	return board.tiles[coord].get("piece", null)


func get_all_pieces_of_color(color_val: int) -> Array:
	var result = []
	for p in pieces:
		if p.color == color_val:
			result.append(p)
	return result


func get_game_state() -> Dictionary:
	# Snapshot do estado (pra IA e save/load)
	return {
		"turn": current_turn,
		"pieces": pieces.map(func(p): return {
			"type": p.type, "color": p.color, "coord": p.coord,
			"has_moved": p.has_moved, "is_revealed": p.is_revealed,
			"is_blocking": p.is_blocking,
		}),
		"move_count": move_history.size(),
		"game_over": game_over,
	}
