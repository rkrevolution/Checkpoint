import CoreAudio
import CoreMediaIO
import Foundation
import os.log

private let log = Logger(subsystem: "com.rkrev.checkpoint", category: "CallDetector")

/// Detects when the user is probably on a call: some app is using the microphone or a camera (#1).
///
/// Only reads whether devices are in use (public CoreAudio / CoreMediaIO properties); it never
/// opens the microphone or camera, so no permission prompt is involved. Polls on a slow,
/// tolerant timer and reports changes through `onChange`.
@MainActor
final class CallDetector {

    private(set) var isInCall = false
    var onChange: ((Bool) -> Void)?

    private var timer: Timer?
    #if DEBUG
    /// Set by Debug commands to simulate a call.
    var debugOverride: Bool? { didSet { refresh() } }
    #endif

    func start() {
        refresh()
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh() {
        var inCall = Self.microphoneInUse() || Self.cameraInUse()
        #if DEBUG
        if let debugOverride { inCall = debugOverride }
        #endif
        guard inCall != isInCall else { return }
        isInCall = inCall
        log.notice("Call \(inCall ? "started" : "ended", privacy: .public) (microphone or camera \(inCall ? "in use" : "free", privacy: .public))")
        onChange?(inCall)
    }

    // MARK: - Microphone

    /// True if any process is capturing audio input. Uses per-process input state, so music
    /// playing through a headset (whose device also has a microphone) doesn't count.
    nonisolated static func microphoneInUse() -> Bool {
        let processes: [AudioObjectID] = audioArray(
            AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList)
        return processes.contains { process in
            audioUInt32(process, kAudioProcessPropertyIsRunningInput) != 0
        }
    }

    private nonisolated static func audioArray(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private nonisolated static func audioUInt32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return 0 }
        return value
    }

    // MARK: - Camera

    /// True if any camera is in use by any app.
    nonisolated static func cameraInUse() -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return false }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &devices) == noErr else { return false }

        return devices.contains { device in
            var running = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
            var value: UInt32 = 0
            var valueSize = UInt32(MemoryLayout<UInt32>.size)
            var valueUsed: UInt32 = 0
            return CMIOObjectGetPropertyData(device, &running, 0, nil, valueSize, &valueUsed, &value) == noErr && value != 0
        }
    }
}
