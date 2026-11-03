import AudioToolbox
import CPrivate
import TouchyCore

/// Applies gesture adjustments to the system. Runs on the multitouch callback thread only.
struct Levels {
    private var control: EdgeControl?
    private var tracker = LevelTracker(value: 0)
    private var device = AudioObjectID(kAudioObjectUnknown)

    mutating func apply(_ adjustment: Adjustment) {
        if adjustment.isStart {
            control = begin(adjustment.control) ? adjustment.control : nil
            // Show the current level right away, so a swipe that's already at an end still gets feedback.
            if let control { showLevel(control, tracker.value) }
        }
        guard control == adjustment.control else { return }
        let (level, unmute, haptic) = tracker.apply(adjustment.delta)
        if let haptic { TPHaptic(haptic == .end) }
        if let level { showLevel(adjustment.control, level) }
        if control == .brightness {
            if let level { TPSetBrightness(level) }
            return
        }
        if unmute { _ = setProperty(device, kAudioDevicePropertyMute, UInt32(0)) }
        if let level { _ = setProperty(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, Float32(level)) }
    }

    private mutating func begin(_ control: EdgeControl) -> Bool {
        var value: Float = 0
        if control == .brightness {
            guard TPGetBrightness(&value) else { return false }
            tracker = LevelTracker(value: value)
            return true
        }
        var muteFlag: UInt32 = 0
        guard getProperty(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice,
                          &device, scope: kAudioObjectPropertyScopeGlobal),
              getProperty(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, &value)
        else { return false }
        tracker = LevelTracker(value: value, muted: getProperty(device, kAudioDevicePropertyMute, &muteFlag) && muteFlag != 0)
        return true
    }
}

private func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

private func getProperty<T: BitwiseCopyable>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ value: inout T,
                            scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput) -> Bool {
    var addr = address(selector, scope)
    var size = UInt32(MemoryLayout<T>.size)
    return AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr
}

private func setProperty<T: BitwiseCopyable>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ value: T) -> Bool {
    var addr = address(selector, kAudioDevicePropertyScopeOutput)
    var value = value
    return AudioObjectSetPropertyData(object, &addr, 0, nil, UInt32(MemoryLayout<T>.size), &value) == noErr
}
