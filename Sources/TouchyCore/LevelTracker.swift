public enum Haptic: Equatable {
    case step, end
}

/// Tracks one level (0...1) through a gesture and decides when a system write is worth making.
public struct LevelTracker {
    /// Haptic steps per full range, matching the brightness/volume keys.
    static let steps: Float = 16

    public private(set) var value: Float
    private var written: Float
    private var muted: Bool
    private var lastBoundary: Int?

    public init(value: Float, muted: Bool = false) {
        self.value = min(max(value, 0), 1)
        self.written = self.value
        self.muted = muted
        // Starting exactly on a boundary (e.g. 100%) mustn't click just for leaving it.
        let scaled = self.value * Self.steps
        if scaled == scaled.rounded(.down) { lastBoundary = Int(scaled) }
    }

    /// Returns the level to write (nil if it moved less than ~0.4% since the last write,
    /// unless it hit an end), whether to unmute, which any upward move does, and which click to play.
    public mutating func apply(_ delta: Float) -> (level: Float?, unmute: Bool, haptic: Haptic?) {
        let unmute = muted && delta > 0
        if unmute { muted = false }
        let old = value
        value = min(max(value + delta, 0), 1)
        let haptic = click(from: old)
        guard value != written, abs(value - written) >= 0.004 || value == 0 || value == 1 else {
            return (nil, unmute, haptic)
        }
        written = value
        return (value, unmute, haptic)
    }

    /// A firm click on reaching an end, a light one on crossing a step. Re-crossing the boundary
    /// that last clicked stays silent, so a finger resting on it doesn't buzz.
    private mutating func click(from old: Float) -> Haptic? {
        let a = Int(old * Self.steps), b = Int(value * Self.steps)
        let atEnd = value != old && (value == 0 || value == 1)
        guard a != b || atEnd else { return nil }
        // The boundary crossed last: the highest one going up, the lowest one going down.
        let boundary = atEnd ? b : b > a ? b : b + 1
        guard boundary != lastBoundary else { return nil }
        lastBoundary = boundary
        return atEnd ? .end : .step
    }
}
