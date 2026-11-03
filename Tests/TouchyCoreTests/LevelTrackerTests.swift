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

@Test func clicksOnStepsAndEndsWithoutBuzzing() {
    var t = LevelTracker(value: 0.53) // steps are 1/16 = 0.0625 apart
    let path: [(Float, Haptic?)] = [
        (0.04, .step),  // 0.57 crosses 0.5625
        (-0.01, nil),   // finger resting on that boundary: no repeat clicks
        (0.01, nil),
        (-0.10, .step), // 0.47 crosses it back and 0.5, the new one clicks
        (0.50, .step),  // 0.97, several steps in one frame is a single click
        (0.10, .end),   // pinned at 1
        (0.10, nil),    // pushing past the end
        (-0.01, nil),   // jitter at the end doesn't re-fire the firm click
        (0.01, nil),
        (-2, .end),     // all the way down
    ]
    for (i, (delta, expected)) in path.enumerated() {
        #expect(t.apply(delta).haptic == expected, "step \(i)")
    }
    // Starting exactly on a boundary: leaving it is silent, crossing the next one clicks.
    for start: Float in [1, 0.5] {
        var s = LevelTracker(value: start)
        #expect(s.apply(-0.01).haptic == nil)
        #expect(s.apply(-0.06).haptic == .step)
    }
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
