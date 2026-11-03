/// Tracks one level (0...1) through a gesture and decides when a system write is worth making.
public struct LevelTracker {
    public private(set) var value: Float
    private var written: Float
    private var muted: Bool

    public init(value: Float, muted: Bool = false) {
        self.value = min(max(value, 0), 1)
        self.written = self.value
        self.muted = muted
    }

    /// Returns the level to write (nil if it moved less than ~0.4% since the last write,
    /// unless it hit an end) and whether to unmute, which any upward move does.
    public mutating func apply(_ delta: Float) -> (level: Float?, unmute: Bool) {
        let unmute = muted && delta > 0
        if unmute { muted = false }
        value = min(max(value + delta, 0), 1)
        guard value != written, abs(value - written) >= 0.004 || value == 0 || value == 1 else {
            return (nil, unmute)
        }
        written = value
        return (value, unmute)
    }
}
