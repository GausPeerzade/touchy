import Testing
import TouchyCore

@Test func smallMovesAccumulateUntilWorthWriting() {
    var t = LevelTracker(value: 0.5)
    // Each step is below the write threshold, but none of the travel is lost.
    #expect(t.apply(0.003).level == nil)
    let level = t.apply(0.003).level
    #expect(level != nil && abs(level! - 0.506) < 1e-6)
    // Reversing back under the threshold relative to the last write stays silent.
    #expect(t.apply(-0.003).level == nil)
    #expect(abs(t.value - 0.503) < 1e-6)
}

@Test func clampsAndAlwaysWritesTheEnds() {
    var t = LevelTracker(value: 0.998)
    // Hitting an end is written even though it's a tiny change, then pinned there.
    #expect(t.apply(0.5).level == 1)
    #expect(t.apply(0.5).level == nil)
    // Coming back down from beyond the clamp starts from 1, not from the overshoot.
    #expect(t.apply(-0.01).level.map { abs($0 - 0.99) < 1e-6 } == true)
    #expect(t.apply(-5).level == 0)
}

@Test(arguments: [Float(0), 0.5, 1])
func upwardMoveUnmutesOnceAtAnyLevel(start: Float) {
    // Downward never unmutes.
    var down = LevelTracker(value: start, muted: true)
    #expect(down.apply(-0.1).unmute == false)
    // The first upward move does, straight from the start level (even pinned at 1), and only once.
    var up = LevelTracker(value: start, muted: true)
    #expect(up.apply(0.1).unmute == true)
    #expect(up.apply(0.1).unmute == false)
}
