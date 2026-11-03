import CPrivate
import Testing
@testable import TouchyCore

private func touch(_ id: Int32, _ x: Float, _ y: Float, state: Int32 = 4) -> MTTouch {
    var t = MTTouch()
    t.identifier = id
    t.state = state
    t.normalized.position = MTPoint(x: x, y: y)
    return t
}

private extension EdgeGesture {
    mutating func feed(_ touches: MTTouch...) -> Adjustment? {
        touches.withUnsafeBufferPointer { update($0) }
    }

    /// Feeds a single-finger path and returns every adjustment it produced.
    mutating func swipe(id: Int32 = 1, x: Float, ys: [Float]) -> [Adjustment] {
        ys.compactMap { feed(touch(id, x, $0)) }
    }
}

@Test func layoutMatchesMultitouchSupport() {
    // The framework hands us a raw array; a size mismatch would misread every contact after the first.
    #expect(MemoryLayout<MTTouch>.stride == 96)
    #expect(MemoryLayout<MTTouch>.offset(of: \MTTouch.normalized) == 32)
}

@Test(arguments: [(Float(0.02), EdgeControl.brightness), (0.98, .volume)])
func edgeSwipeMapsToControlAndDirection(x: Float, control: EdgeControl) {
    var g = EdgeGesture(gain: 2)
    // Up: first event engages past the activation threshold and carries the travel so far;
    // reversing mid-gesture (0.5 -> 0.4) keeps going, and drifting off the strip doesn't end it.
    let up = g.swipe(x: x, ys: [0.2, 0.21, 0.25, 0.3, 0.3, 0.5, 0.4]) + [g.feed(touch(1, 0.5, 0.45))!]
    #expect(up.map(\.control).allSatisfy { $0 == control })
    #expect(up.first?.isStart == true && up.dropFirst().allSatisfy { !$0.isStart })
    #expect(abs(up.reduce(0) { $0 + $1.delta } - 0.5) < 1e-5) // (0.45 - 0.2) * gain, no lost travel
    #expect(up.count == 5) // stationary frame (0.3 -> 0.3) emits nothing

    // Lift, then down on the same edge is a fresh gesture with negative delta.
    _ = g.feed()
    let down = g.swipe(id: 2, x: x, ys: [0.8, 0.7])
    #expect(down.count == 1 && down[0].isStart && down[0].control == control)
    #expect(abs(down[0].delta + 0.2) < 1e-5)
}

@Test func ignoresTapsAndHorizontalDragsFromEdge() {
    var g = EdgeGesture()
    // Click/rest at the edge: jitter below the activation distance never engages.
    #expect(g.swipe(x: 0.02, ys: [0.5, 0.51, 0.49, 0.52]).isEmpty)
    _ = g.feed()
    // Cursor move starting at the edge: horizontal wins, and later vertical movement can't revive it.
    #expect(g.feed(touch(1, 0.02, 0.5)) == nil)
    #expect(g.feed(touch(1, 0.10, 0.52)) == nil)
    #expect(g.swipe(x: 0.10, ys: [0.7, 0.9]).isEmpty)
}

@Test func onlyEngagesWhenFingerLandsInsideEdge() {
    var g = EdgeGesture()
    // Finger lands mid-pad and slides into the edge strip: still a cursor move.
    #expect(g.feed(touch(1, 0.5, 0.5)) == nil)
    #expect(g.swipe(x: 0.01, ys: [0.5, 0.7, 0.9]).isEmpty)
    // After lifting, a real edge landing works again.
    _ = g.feed()
    #expect(!g.swipe(x: 0.01, ys: [0.5, 0.7]).isEmpty)
}

@Test func multiFingerAndNonContactStatesAreHandled() {
    var g = EdgeGesture()
    // Hovering/lifting contacts don't count, so this is still a one-finger edge swipe
    // (the first frame of a contact arrives as state 3, "make touch").
    #expect(g.feed(touch(1, 0.02, 0.2, state: 3), touch(9, 0.5, 0.5, state: 2)) == nil)
    #expect(g.feed(touch(1, 0.02, 0.3), touch(9, 0.5, 0.5, state: 5))?.control == .brightness)
    // A second real finger (e.g. two-finger scroll) kills the gesture until everything lifts.
    #expect(g.feed(touch(1, 0.02, 0.4), touch(2, 0.5, 0.5)) == nil)
    #expect(g.swipe(x: 0.02, ys: [0.5, 0.6]).isEmpty)
    // A different finger id replacing the tracked one mid-gesture is rejected too.
    _ = g.feed()
    _ = g.swipe(id: 1, x: 0.98, ys: [0.2, 0.3])
    #expect(g.feed(touch(3, 0.98, 0.4)) == nil)
    #expect(g.feed(touch(3, 0.98, 0.5)) == nil)
}
