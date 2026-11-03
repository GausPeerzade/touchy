import CPrivate

public enum EdgeControl: Equatable {
    case brightness, volume
}

public struct Adjustment: Equatable {
    public let control: EdgeControl
    public let delta: Float
    public let isStart: Bool
}

/// Turns raw trackpad frames into level adjustments. A gesture only engages when a single
/// finger lands inside an edge strip and then moves mostly vertically; anything else
/// (multi-finger, landing mid-pad, horizontal drag) is ignored until all fingers lift.
/// Once engaged, the finger may drift off the strip and keeps controlling the same level.
public struct EdgeGesture {
    public var edgeWidth: Float
    public var activation: Float
    public var gain: Float

    private enum Phase {
        case idle, rejected
        case pending(id: Int32, control: EdgeControl, x: Float, y: Float)
        case active(id: Int32, control: EdgeControl, y: Float)
    }

    private var phase = Phase.idle

    public init(edgeWidth: Float = 0.08, activation: Float = 0.03, gain: Float = 1.5) {
        self.edgeWidth = edgeWidth
        self.activation = activation
        self.gain = gain
    }

    public mutating func update(_ touches: UnsafeBufferPointer<MTTouch>) -> Adjustment? {
        var finger: MTTouch?
        var count = 0
        for touch in touches where touch.state == 3 || touch.state == 4 {
            count += 1
            finger = touch
        }
        guard count == 1, let finger else {
            phase = count == 0 ? .idle : .rejected
            return nil
        }
        let x = finger.normalized.position.x, y = finger.normalized.position.y

        switch phase {
        case .rejected:
            return nil
        case .idle:
            if x < edgeWidth {
                phase = .pending(id: finger.identifier, control: .brightness, x: x, y: y)
            } else if x > 1 - edgeWidth {
                phase = .pending(id: finger.identifier, control: .volume, x: x, y: y)
            } else {
                phase = .rejected
            }
            return nil
        case let .pending(id, control, x0, y0):
            let dx = abs(x - x0), dy = y - y0
            guard id == finger.identifier else { phase = .rejected; return nil }
            guard max(dx, abs(dy)) >= activation else { return nil }
            guard abs(dy) > dx else { phase = .rejected; return nil }
            phase = .active(id: id, control: control, y: y)
            return Adjustment(control: control, delta: dy * gain, isStart: true)
        case let .active(id, control, lastY):
            guard id == finger.identifier else { phase = .rejected; return nil }
            guard y != lastY else { return nil }
            phase = .active(id: id, control: control, y: y)
            return Adjustment(control: control, delta: (y - lastY) * gain, isStart: false)
        }
    }
}
