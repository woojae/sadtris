import SwiftUI

// MARK: - App Entry Point

@main
struct TetrisApp: App {
    var body: some Scene {
        WindowGroup {
            GameView()
                .frame(width: 480, height: 620)
                .background(Color.black)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 480, height: 620)
    }
}

// MARK: - Constants

enum Constants {
    static let rows = 20
    static let cols = 10
    static let cellSize: CGFloat = 28
    static let tickInterval: TimeInterval = 0.5
    static let fastTickInterval: TimeInterval = 0.05
}

// MARK: - Tetromino Definitions

enum TetrominoType: Int, CaseIterable {
    case I, O, T, S, Z, J, L

    var color: Color {
        switch self {
        case .I: return .cyan
        case .O: return .yellow
        case .T: return .purple
        case .S: return .green
        case .Z: return .red
        case .J: return .blue
        case .L: return .orange
        }
    }

    /// Each rotation state is an array of (row, col) offsets from the piece origin.
    var rotations: [[(Int, Int)]] {
        switch self {
        case .I:
            return [
                [(0,0),(0,1),(0,2),(0,3)],
                [(0,0),(1,0),(2,0),(3,0)],
                [(0,0),(0,1),(0,2),(0,3)],
                [(0,0),(1,0),(2,0),(3,0)]
            ]
        case .O:
            return [
                [(0,0),(0,1),(1,0),(1,1)],
                [(0,0),(0,1),(1,0),(1,1)],
                [(0,0),(0,1),(1,0),(1,1)],
                [(0,0),(0,1),(1,0),(1,1)]
            ]
        case .T:
            return [
                [(0,0),(0,1),(0,2),(1,1)],
                [(0,0),(1,0),(2,0),(1,1)],
                [(0,1),(1,0),(1,1),(1,2)],
                [(0,0),(1,0),(2,0),(1,-1)]
            ]
        case .S:
            return [
                [(0,1),(0,2),(1,0),(1,1)],
                [(0,0),(1,0),(1,1),(2,1)],
                [(0,1),(0,2),(1,0),(1,1)],
                [(0,0),(1,0),(1,1),(2,1)]
            ]
        case .Z:
            return [
                [(0,0),(0,1),(1,1),(1,2)],
                [(0,1),(1,0),(1,1),(2,0)],
                [(0,0),(0,1),(1,1),(1,2)],
                [(0,1),(1,0),(1,1),(2,0)]
            ]
        case .J:
            return [
                [(0,0),(1,0),(1,1),(1,2)],
                [(0,0),(0,1),(1,0),(2,0)],
                [(0,0),(0,1),(0,2),(1,2)],
                [(0,0),(1,0),(2,0),(2,-1)]
            ]
        case .L:
            return [
                [(0,2),(1,0),(1,1),(1,2)],
                [(0,0),(1,0),(2,0),(2,1)],
                [(0,0),(0,1),(0,2),(1,0)],
                [(0,0),(0,1),(1,1),(2,1)]
            ]
        }
    }
}

struct Piece {
    var type: TetrominoType
    var rotation: Int
    var row: Int
    var col: Int

    var cells: [(Int, Int)] {
        type.rotations[rotation].map { (row + $0.0, col + $0.1) }
    }

    func rotated() -> Piece {
        Piece(type: type, rotation: (rotation + 1) % 4, row: row, col: col)
    }

    func moved(dr: Int, dc: Int) -> Piece {
        Piece(type: type, rotation: rotation, row: row + dr, col: col + dc)
    }
}

// MARK: - Game State

struct Cell {
    var filled: Bool = false
    var color: Color = .clear
}

class GameState: ObservableObject {
    @Published var board: [[Cell]]
    @Published var currentPiece: Piece
    @Published var nextPiece: Piece
    @Published var score: Int = 0
    @Published var lines: Int = 0
    @Published var level: Int = 1
    @Published var isGameOver: Bool = false
    @Published var isPaused: Bool = false
    @Published var ghostRow: Int = 0

    private var timer: Timer?
    private var isSoftDropping = false

    init() {
        board = Array(repeating: Array(repeating: Cell(), count: Constants.cols), count: Constants.rows)
        currentPiece = Piece(type: TetrominoType.allCases.randomElement()!, rotation: 0, row: 0, col: 3)
        nextPiece = Piece(type: TetrominoType.allCases.randomElement()!, rotation: 0, row: 0, col: 3)
        updateGhost()
        startTimer()
    }

    var tickInterval: TimeInterval {
        let base = Constants.tickInterval
        let speedup = Double(level - 1) * 0.045
        return max(base - speedup, 0.1)
    }

    func startTimer() {
        timer?.invalidate()
        let interval = isSoftDropping ? Constants.fastTickInterval : tickInterval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.tick()
            }
        }
    }

    func tick() {
        guard !isGameOver && !isPaused else { return }
        moveDown()
    }

    func isValid(_ piece: Piece) -> Bool {
        for (r, c) in piece.cells {
            if r < 0 || r >= Constants.rows || c < 0 || c >= Constants.cols {
                return false
            }
            if board[r][c].filled {
                return false
            }
        }
        return true
    }

    func updateGhost() {
        var ghost = currentPiece
        while isValid(ghost.moved(dr: 1, dc: 0)) {
            ghost = ghost.moved(dr: 1, dc: 0)
        }
        ghostRow = ghost.row
    }

    func moveLeft() {
        guard !isGameOver && !isPaused else { return }
        let moved = currentPiece.moved(dr: 0, dc: -1)
        if isValid(moved) {
            currentPiece = moved
            updateGhost()
        }
    }

    func moveRight() {
        guard !isGameOver && !isPaused else { return }
        let moved = currentPiece.moved(dr: 0, dc: 1)
        if isValid(moved) {
            currentPiece = moved
            updateGhost()
        }
    }

    func moveDown() {
        guard !isGameOver && !isPaused else { return }
        let moved = currentPiece.moved(dr: 1, dc: 0)
        if isValid(moved) {
            currentPiece = moved
        } else {
            lockPiece()
        }
    }

    func rotate() {
        guard !isGameOver && !isPaused else { return }
        let rotated = currentPiece.rotated()
        if isValid(rotated) {
            currentPiece = rotated
            updateGhost()
            return
        }
        // Wall kick: try shifting left/right by 1 or 2
        for offset in [1, -1, 2, -2] {
            let kicked = Piece(type: rotated.type, rotation: rotated.rotation, row: rotated.row, col: rotated.col + offset)
            if isValid(kicked) {
                currentPiece = kicked
                updateGhost()
                return
            }
        }
    }

    func hardDrop() {
        guard !isGameOver && !isPaused else { return }
        var dropped = currentPiece
        var dropDistance = 0
        while isValid(dropped.moved(dr: 1, dc: 0)) {
            dropped = dropped.moved(dr: 1, dc: 0)
            dropDistance += 1
        }
        score += dropDistance * 2
        currentPiece = dropped
        lockPiece()
    }

    func startSoftDrop() {
        isSoftDropping = true
        startTimer()
    }

    func stopSoftDrop() {
        isSoftDropping = false
        startTimer()
    }

    func lockPiece() {
        for (r, c) in currentPiece.cells {
            if r >= 0 && r < Constants.rows && c >= 0 && c < Constants.cols {
                board[r][c] = Cell(filled: true, color: currentPiece.type.color)
            }
        }
        clearLines()
        spawnPiece()
    }

    func clearLines() {
        var cleared = 0
        var newBoard = board.filter { row in
            let full = row.allSatisfy { $0.filled }
            if full { cleared += 1 }
            return !full
        }
        while newBoard.count < Constants.rows {
            newBoard.insert(Array(repeating: Cell(), count: Constants.cols), at: 0)
        }
        board = newBoard

        if cleared > 0 {
            lines += cleared
            let points: [Int] = [0, 100, 300, 500, 800]
            score += points[cleared] * level
            level = (lines / 10) + 1
            startTimer() // update speed for new level
        }
    }

    func spawnPiece() {
        currentPiece = nextPiece
        nextPiece = Piece(type: TetrominoType.allCases.randomElement()!, rotation: 0, row: 0, col: 3)
        updateGhost()

        if !isValid(currentPiece) {
            isGameOver = true
            timer?.invalidate()
        }
    }

    func togglePause() {
        isPaused.toggle()
    }

    func restart() {
        board = Array(repeating: Array(repeating: Cell(), count: Constants.cols), count: Constants.rows)
        currentPiece = Piece(type: TetrominoType.allCases.randomElement()!, rotation: 0, row: 0, col: 3)
        nextPiece = Piece(type: TetrominoType.allCases.randomElement()!, rotation: 0, row: 0, col: 3)
        score = 0
        lines = 0
        level = 1
        isGameOver = false
        isPaused = false
        updateGhost()
        startTimer()
    }
}

// MARK: - Game Board View

struct BoardView: View {
    @ObservedObject var game: GameState

    var body: some View {
        Canvas { context, size in
            let cellW = Constants.cellSize
            let cellH = Constants.cellSize

            // Draw background grid
            for r in 0..<Constants.rows {
                for c in 0..<Constants.cols {
                    let rect = CGRect(
                        x: CGFloat(c) * cellW,
                        y: CGFloat(r) * cellH,
                        width: cellW,
                        height: cellH
                    )
                    context.fill(Path(rect), with: .color(Color(white: 0.08)))
                    context.stroke(Path(rect), with: .color(Color(white: 0.15)), lineWidth: 0.5)
                }
            }

            // Draw locked cells
            for r in 0..<Constants.rows {
                for c in 0..<Constants.cols {
                    if game.board[r][c].filled {
                        drawCell(context: context, row: r, col: c, color: game.board[r][c].color, cellW: cellW, cellH: cellH)
                    }
                }
            }

            // Draw ghost piece
            let ghostPiece = Piece(type: game.currentPiece.type, rotation: game.currentPiece.rotation, row: game.ghostRow, col: game.currentPiece.col)
            for (r, c) in ghostPiece.cells {
                if r >= 0 && r < Constants.rows && c >= 0 && c < Constants.cols {
                    let rect = CGRect(
                        x: CGFloat(c) * cellW + 1,
                        y: CGFloat(r) * cellH + 1,
                        width: cellW - 2,
                        height: cellH - 2
                    )
                    context.stroke(Path(rect), with: .color(game.currentPiece.type.color.opacity(0.4)), lineWidth: 1.5)
                }
            }

            // Draw current piece
            for (r, c) in game.currentPiece.cells {
                if r >= 0 && r < Constants.rows && c >= 0 && c < Constants.cols {
                    drawCell(context: context, row: r, col: c, color: game.currentPiece.type.color, cellW: cellW, cellH: cellH)
                }
            }
        }
        .frame(
            width: CGFloat(Constants.cols) * Constants.cellSize,
            height: CGFloat(Constants.rows) * Constants.cellSize
        )
        .border(Color.gray.opacity(0.5), width: 2)
    }

    func drawCell(context: GraphicsContext, row: Int, col: Int, color: Color, cellW: CGFloat, cellH: CGFloat) {
        let rect = CGRect(
            x: CGFloat(col) * cellW + 1,
            y: CGFloat(row) * cellH + 1,
            width: cellW - 2,
            height: cellH - 2
        )
        context.fill(Path(rect), with: .color(color))

        // Highlight (top-left shine)
        let highlight = CGRect(
            x: CGFloat(col) * cellW + 1,
            y: CGFloat(row) * cellH + 1,
            width: cellW - 2,
            height: 3
        )
        context.fill(Path(highlight), with: .color(Color.white.opacity(0.3)))

        // Shadow (bottom)
        let shadow = CGRect(
            x: CGFloat(col) * cellW + 1,
            y: CGFloat(row) * cellH + cellH - 4,
            width: cellW - 2,
            height: 3
        )
        context.fill(Path(shadow), with: .color(Color.black.opacity(0.3)))
    }
}

// MARK: - Next Piece Preview

struct NextPieceView: View {
    let piece: Piece

    var body: some View {
        VStack(spacing: 4) {
            Text("NEXT")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.gray)
            Canvas { context, size in
                let cellSize: CGFloat = 18
                let cells = piece.type.rotations[0]
                for (r, c) in cells {
                    let rect = CGRect(
                        x: CGFloat(c) * cellSize + 2,
                        y: CGFloat(r) * cellSize + 2,
                        width: cellSize - 2,
                        height: cellSize - 2
                    )
                    context.fill(Path(rect), with: .color(piece.type.color))
                }
            }
            .frame(width: 80, height: 80)
        }
        .padding(8)
        .background(Color(white: 0.1))
        .cornerRadius(8)
    }
}

// MARK: - Info Panel

struct InfoPanel: View {
    @ObservedObject var game: GameState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            NextPieceView(piece: game.nextPiece)

            statBlock(label: "SCORE", value: "\(game.score)")
            statBlock(label: "LINES", value: "\(game.lines)")
            statBlock(label: "LEVEL", value: "\(game.level)")

            Spacer()

            VStack(alignment: .leading, spacing: 4) {
                Text("CONTROLS")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)
                Group {
                    Text("← →  Move")
                    Text("↑    Rotate")
                    Text("↓    Soft Drop")
                    Text("Space Hard Drop")
                    Text("P    Pause")
                    Text("R    Restart")
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Color(white: 0.5))
            }
        }
        .frame(width: 110)
    }

    func statBlock(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.gray)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Key Handling

struct KeyEventHandling: NSViewRepresentable {
    let game: GameState

    class KeyView: NSView {
        var game: GameState?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            guard let game = game else { return }

            // Prevent key repeat for hard drop
            if event.isARepeat && event.keyCode == 49 { return }

            switch event.keyCode {
            case 123: // left arrow
                game.moveLeft()
            case 124: // right arrow
                game.moveRight()
            case 125: // down arrow
                if !event.isARepeat {
                    game.startSoftDrop()
                }
            case 126: // up arrow
                game.rotate()
            case 49: // space
                game.hardDrop()
            case 35: // P
                game.togglePause()
            case 15: // R
                game.restart()
            default:
                break
            }
        }

        override func keyUp(with event: NSEvent) {
            switch event.keyCode {
            case 125: // down arrow released
                game?.stopSoftDrop()
            default:
                break
            }
        }
    }

    func makeNSView(context: Context) -> KeyView {
        let view = KeyView()
        view.game = game
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: KeyView, context: Context) {
        nsView.game = game
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

// MARK: - Main Game View

struct GameView: View {
    @StateObject private var game = GameState()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            HStack(spacing: 20) {
                BoardView(game: game)
                InfoPanel(game: game)
            }
            .padding()

            // Game Over overlay
            if game.isGameOver {
                VStack(spacing: 16) {
                    Text("GAME OVER")
                        .font(.system(size: 36, weight: .black, design: .monospaced))
                        .foregroundColor(.red)
                    Text("Score: \(game.score)")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                    Text("Press R to restart")
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(.gray)
                }
                .padding(32)
                .background(Color.black.opacity(0.85))
                .cornerRadius(16)
            }

            // Pause overlay
            if game.isPaused && !game.isGameOver {
                VStack(spacing: 12) {
                    Text("PAUSED")
                        .font(.system(size: 32, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                    Text("Press P to resume")
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(.gray)
                }
                .padding(32)
                .background(Color.black.opacity(0.85))
                .cornerRadius(16)
            }

            // Invisible key handler
            KeyEventHandling(game: game)
                .frame(width: 0, height: 0)
        }
    }
}
