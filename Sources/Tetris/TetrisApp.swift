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
    static let lockDelay: TimeInterval = 0.5
    static let maxLockMoves = 15
    static let dasDelay: TimeInterval = 0.17
    static let arrRate: TimeInterval = 0.05
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

    // Hold piece
    @Published var heldPiece: TetrominoType?
    @Published var canHold: Bool = true

    // Lock delay
    @Published var isLocking: Bool = false
    private var lockDelayRemaining: TimeInterval = 0
    private var lockMoveCount: Int = 0

    // DAS (Delayed Auto Shift)
    var leftKeyHeld: Bool = false
    var rightKeyHeld: Bool = false
    private var dasTimer: TimeInterval = 0
    private var arrTimer: TimeInterval = 0
    private var dasDirection: Int = 0

    // T-spin detection
    @Published var lastTSpin: String? = nil
    private var lastMoveWasRotation: Bool = false

    private var timer: Timer?
    private var gameLoopTimer: Timer?
    private var isSoftDropping = false
    private var lastFrameTime: Date = Date()

    init() {
        board = Array(repeating: Array(repeating: Cell(), count: Constants.cols), count: Constants.rows)
        currentPiece = Piece(type: TetrominoType.allCases.randomElement()!, rotation: 0, row: 0, col: 3)
        nextPiece = Piece(type: TetrominoType.allCases.randomElement()!, rotation: 0, row: 0, col: 3)
        updateGhost()
        startTimer()
        startGameLoop()
    }

    func startGameLoop() {
        gameLoopTimer?.invalidate()
        lastFrameTime = Date()
        gameLoopTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.gameLoop()
            }
        }
    }

    func gameLoop() {
        guard !isGameOver && !isPaused else { return }

        let now = Date()
        let deltaTime = now.timeIntervalSince(lastFrameTime)
        lastFrameTime = now

        // Handle DAS
        if leftKeyHeld || rightKeyHeld {
            let direction = leftKeyHeld ? -1 : 1
            if dasDirection != direction {
                dasDirection = direction
                dasTimer = 0
                arrTimer = 0
            }

            dasTimer += deltaTime
            if dasTimer >= Constants.dasDelay {
                arrTimer += deltaTime
                if arrTimer >= Constants.arrRate {
                    arrTimer = 0
                    if direction == -1 {
                        moveLeftInternal()
                    } else {
                        moveRightInternal()
                    }
                }
            }
        } else {
            dasDirection = 0
            dasTimer = 0
            arrTimer = 0
        }

        // Handle lock delay
        if isLocking {
            lockDelayRemaining -= deltaTime
            if lockDelayRemaining <= 0 {
                forceLock()
            }
        }

        // Clear T-spin message after a delay
        if lastTSpin != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.lastTSpin = nil
            }
        }
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
        moveLeftInternal()
        leftKeyHeld = true
        dasDirection = -1
        dasTimer = 0
        arrTimer = 0
    }

    func moveLeftInternal() {
        let moved = currentPiece.moved(dr: 0, dc: -1)
        if isValid(moved) {
            currentPiece = moved
            lastMoveWasRotation = false
            updateGhost()
            resetLockDelayIfNeeded()
        }
    }

    func moveRight() {
        guard !isGameOver && !isPaused else { return }
        moveRightInternal()
        rightKeyHeld = true
        dasDirection = 1
        dasTimer = 0
        arrTimer = 0
    }

    func moveRightInternal() {
        let moved = currentPiece.moved(dr: 0, dc: 1)
        if isValid(moved) {
            currentPiece = moved
            lastMoveWasRotation = false
            updateGhost()
            resetLockDelayIfNeeded()
        }
    }

    func resetLockDelayIfNeeded() {
        if isLocking && lockMoveCount < Constants.maxLockMoves {
            lockMoveCount += 1
            lockDelayRemaining = Constants.lockDelay
        }
    }

    func moveDown() {
        guard !isGameOver && !isPaused else { return }
        let moved = currentPiece.moved(dr: 1, dc: 0)
        if isValid(moved) {
            currentPiece = moved
            lastMoveWasRotation = false
            // If we can move down, cancel any lock delay
            if isLocking {
                isLocking = false
                lockMoveCount = 0
            }
        } else {
            // Start lock delay if not already locking
            if !isLocking {
                isLocking = true
                lockDelayRemaining = Constants.lockDelay
                lockMoveCount = 0
            }
        }
    }

    func forceLock() {
        isLocking = false
        lockMoveCount = 0
        lockPiece()
    }

    func rotate() {
        guard !isGameOver && !isPaused else { return }
        let rotated = currentPiece.rotated()
        if isValid(rotated) {
            currentPiece = rotated
            lastMoveWasRotation = true
            updateGhost()
            resetLockDelayIfNeeded()
            return
        }
        // Wall kick: try shifting left/right by 1 or 2
        for offset in [1, -1, 2, -2] {
            let kicked = Piece(type: rotated.type, rotation: rotated.rotation, row: rotated.row, col: rotated.col + offset)
            if isValid(kicked) {
                currentPiece = kicked
                lastMoveWasRotation = true
                updateGhost()
                resetLockDelayIfNeeded()
                return
            }
        }
    }

    func holdPiece() {
        guard !isGameOver && !isPaused && canHold else { return }

        let currentType = currentPiece.type
        if let held = heldPiece {
            // Swap with held piece
            currentPiece = Piece(type: held, rotation: 0, row: 0, col: 3)
            heldPiece = currentType
        } else {
            // First hold - take next piece
            heldPiece = currentType
            currentPiece = nextPiece
            nextPiece = Piece(type: TetrominoType.allCases.randomElement()!, rotation: 0, row: 0, col: 3)
        }

        canHold = false
        isLocking = false
        lockMoveCount = 0
        lastMoveWasRotation = false
        updateGhost()

        if !isValid(currentPiece) {
            isGameOver = true
            timer?.invalidate()
            gameLoopTimer?.invalidate()
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
        lastMoveWasRotation = false
        isLocking = false
        lockMoveCount = 0
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
        // Detect T-spin before placing piece
        let tSpinType = detectTSpin()

        for (r, c) in currentPiece.cells {
            if r >= 0 && r < Constants.rows && c >= 0 && c < Constants.cols {
                board[r][c] = Cell(filled: true, color: currentPiece.type.color)
            }
        }
        clearLines(tSpinType: tSpinType)
        spawnPiece()
    }

    func detectTSpin() -> String? {
        guard currentPiece.type == .T && lastMoveWasRotation else { return nil }

        // Find the center of the T piece (the cell that connects to all others)
        // For T piece, the center is at rotation-dependent position
        let centerRow: Int
        let centerCol: Int

        switch currentPiece.rotation {
        case 0: // T pointing down
            centerRow = currentPiece.row
            centerCol = currentPiece.col + 1
        case 1: // T pointing left
            centerRow = currentPiece.row + 1
            centerCol = currentPiece.col
        case 2: // T pointing up
            centerRow = currentPiece.row + 1
            centerCol = currentPiece.col + 1
        case 3: // T pointing right
            centerRow = currentPiece.row + 1
            centerCol = currentPiece.col
        default:
            return nil
        }

        // Check the 4 corners around the center
        let corners = [
            (centerRow - 1, centerCol - 1),
            (centerRow - 1, centerCol + 1),
            (centerRow + 1, centerCol - 1),
            (centerRow + 1, centerCol + 1)
        ]

        var filledCorners = 0
        for (r, c) in corners {
            if r < 0 || r >= Constants.rows || c < 0 || c >= Constants.cols {
                filledCorners += 1
            } else if board[r][c].filled {
                filledCorners += 1
            }
        }

        // 3-corner rule: at least 3 corners must be filled
        if filledCorners >= 3 {
            // Check front corners for full T-spin vs mini
            let frontCorners: [(Int, Int)]
            switch currentPiece.rotation {
            case 0:
                frontCorners = [(centerRow + 1, centerCol - 1), (centerRow + 1, centerCol + 1)]
            case 1:
                frontCorners = [(centerRow - 1, centerCol - 1), (centerRow + 1, centerCol - 1)]
            case 2:
                frontCorners = [(centerRow - 1, centerCol - 1), (centerRow - 1, centerCol + 1)]
            case 3:
                frontCorners = [(centerRow - 1, centerCol + 1), (centerRow + 1, centerCol + 1)]
            default:
                return nil
            }

            var frontFilled = 0
            for (r, c) in frontCorners {
                if r < 0 || r >= Constants.rows || c < 0 || c >= Constants.cols {
                    frontFilled += 1
                } else if board[r][c].filled {
                    frontFilled += 1
                }
            }

            return frontFilled >= 2 ? "full" : "mini"
        }

        return nil
    }

    func clearLines(tSpinType: String?) {
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

        // Calculate score with T-spin bonuses
        var points = 0
        if let tSpin = tSpinType {
            if tSpin == "full" {
                switch cleared {
                case 0:
                    points = 400
                    lastTSpin = "T-SPIN!"
                case 1:
                    points = 800
                    lastTSpin = "T-SPIN SINGLE!"
                case 2:
                    points = 1200
                    lastTSpin = "T-SPIN DOUBLE!"
                case 3:
                    points = 1600
                    lastTSpin = "T-SPIN TRIPLE!"
                default:
                    break
                }
            } else { // mini
                switch cleared {
                case 0:
                    points = 100
                    lastTSpin = "T-SPIN MINI!"
                case 1:
                    points = 200
                    lastTSpin = "T-SPIN MINI SINGLE!"
                case 2:
                    points = 400
                    lastTSpin = "T-SPIN MINI DOUBLE!"
                default:
                    break
                }
            }
        } else if cleared > 0 {
            let normalPoints: [Int] = [0, 100, 300, 500, 800]
            points = normalPoints[min(cleared, 4)]
        }

        score += points * level

        if cleared > 0 {
            lines += cleared
            level = (lines / 10) + 1
            startTimer()
        }
    }

    func spawnPiece() {
        currentPiece = nextPiece
        nextPiece = Piece(type: TetrominoType.allCases.randomElement()!, rotation: 0, row: 0, col: 3)
        canHold = true
        lastMoveWasRotation = false
        updateGhost()

        if !isValid(currentPiece) {
            isGameOver = true
            timer?.invalidate()
            gameLoopTimer?.invalidate()
        }
    }

    func togglePause() {
        isPaused.toggle()
    }

    func restart() {
        board = Array(repeating: Array(repeating: Cell(), count: Constants.cols), count: Constants.rows)
        currentPiece = Piece(type: TetrominoType.allCases.randomElement()!, rotation: 0, row: 0, col: 3)
        nextPiece = Piece(type: TetrominoType.allCases.randomElement()!, rotation: 0, row: 0, col: 3)
        heldPiece = nil
        canHold = true
        score = 0
        lines = 0
        level = 1
        isGameOver = false
        isPaused = false
        isLocking = false
        lockMoveCount = 0
        lockDelayRemaining = 0
        lastMoveWasRotation = false
        lastTSpin = nil
        leftKeyHeld = false
        rightKeyHeld = false
        dasTimer = 0
        arrTimer = 0
        dasDirection = 0
        updateGhost()
        startTimer()
        startGameLoop()
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

// MARK: - Hold Piece Preview

struct HoldPieceView: View {
    let pieceType: TetrominoType?
    let canHold: Bool

    var body: some View {
        VStack(spacing: 4) {
            Text("HOLD")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.gray)
            Canvas { context, size in
                let cellSize: CGFloat = 18
                if let type = pieceType {
                    let cells = type.rotations[0]
                    let color = canHold ? type.color : type.color.opacity(0.3)
                    for (r, c) in cells {
                        let rect = CGRect(
                            x: CGFloat(c) * cellSize + 2,
                            y: CGFloat(r) * cellSize + 2,
                            width: cellSize - 2,
                            height: cellSize - 2
                        )
                        context.fill(Path(rect), with: .color(color))
                    }
                }
            }
            .frame(width: 80, height: 80)
        }
        .padding(8)
        .background(Color(white: 0.1))
        .cornerRadius(8)
        .opacity(canHold ? 1.0 : 0.6)
    }
}

// MARK: - Info Panel

struct InfoPanel: View {
    @ObservedObject var game: GameState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HoldPieceView(pieceType: game.heldPiece, canHold: game.canHold)
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
                    Text("C    Hold")
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

            // Prevent key repeat for hard drop and hold
            if event.isARepeat && (event.keyCode == 49 || event.keyCode == 8) { return }

            switch event.keyCode {
            case 123: // left arrow
                if !event.isARepeat {
                    game.moveLeft()
                }
            case 124: // right arrow
                if !event.isARepeat {
                    game.moveRight()
                }
            case 125: // down arrow
                if !event.isARepeat {
                    game.startSoftDrop()
                }
            case 126: // up arrow
                if !event.isARepeat {
                    game.rotate()
                }
            case 49: // space
                game.hardDrop()
            case 8: // C key - hold
                game.holdPiece()
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
            case 123: // left arrow released
                game?.leftKeyHeld = false
            case 124: // right arrow released
                game?.rightKeyHeld = false
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

            // T-spin overlay
            if let tSpin = game.lastTSpin {
                Text(tSpin)
                    .font(.system(size: 24, weight: .black, design: .monospaced))
                    .foregroundColor(.purple)
                    .shadow(color: .purple, radius: 10)
                    .transition(.scale.combined(with: .opacity))
                    .animation(.easeOut(duration: 0.3), value: game.lastTSpin)
            }

            // Invisible key handler
            KeyEventHandling(game: game)
                .frame(width: 0, height: 0)
        }
    }
}
