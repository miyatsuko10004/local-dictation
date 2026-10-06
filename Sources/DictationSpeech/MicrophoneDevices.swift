import Foundation
import CoreAudio
import DictationCore

public struct MicrophoneDevice: Identifiable, Equatable, Sendable {
    public let id: AudioDeviceID
    public let uid: String
    public let name: String
    public init(id: AudioDeviceID, uid: String, name: String) { self.id = id; self.uid = uid; self.name = name }
}
public enum MicrophoneDevices {
    private static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var property = address(selector), size = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString?
        guard AudioObjectGetPropertyData(id, &property, 0, nil, &size, &value) == noErr else { return nil }
        return value as String?
    }
    public static func available() throws -> [MicrophoneDevice] {
        var property = address(kAudioHardwarePropertyDevices), size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size) == noErr else {
            throw DictationError.message("マイク一覧を取得できませんでした。")
        }
        guard size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        let status = ids.withUnsafeMutableBytes { AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size, $0.baseAddress!) }
        guard status == noErr else { throw DictationError.message("マイク一覧を取得できませんでした。") }
        return ids.compactMap { id in
            var streams = address(kAudioDevicePropertyStreamConfiguration, scope: kAudioDevicePropertyScopeInput), bytes: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &bytes) == noErr, bytes >= MemoryLayout<AudioBufferList>.size else { return nil }
            let memory = UnsafeMutableRawPointer.allocate(byteCount: Int(bytes), alignment: MemoryLayout<AudioBufferList>.alignment)
            defer { memory.deallocate() }
            guard AudioObjectGetPropertyData(id, &streams, 0, nil, &bytes, memory) == noErr else { return nil }
            let buffers = UnsafeMutableAudioBufferListPointer(memory.assumingMemoryBound(to: AudioBufferList.self))
            guard buffers.contains(where: { $0.mNumberChannels > 0 }), let uid = string(id, kAudioDevicePropertyDeviceUID) else { return nil }
            return MicrophoneDevice(id: id, uid: uid, name: string(id, kAudioObjectPropertyName) ?? "マイク")
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    public static func currentDefaultID() throws -> AudioDeviceID {
        var property = address(kAudioHardwarePropertyDefaultInputDevice), id: AudioDeviceID = 0, size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size, &id) == noErr, id != 0 else {
            throw DictationError.message("システム標準のマイクがありません。")
        }
        return id
    }
    public static func resolve(uid: String?, devices: [MicrophoneDevice], defaultID: AudioDeviceID) throws -> MicrophoneDevice {
        if let uid {
            guard let device = devices.first(where: { $0.uid == uid }) else { throw DictationError.message("選択したマイクが未接続です。接続するか設定で別のマイクを選んでください。") }
            return device
        }
        guard let device = devices.first(where: { $0.id == defaultID }) else { throw DictationError.message("システム標準の入力機器を利用できません。") }
        return device
    }
    public static func selected(uid: String?) throws -> MicrophoneDevice {
        let devices = try available()
        return try resolve(uid: uid, devices: devices, defaultID: uid == nil ? currentDefaultID() : 0)
    }
}
