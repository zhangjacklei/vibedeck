//
//  VoiceInput.swift
//  Remotastic (local fork)
//
//  按住语音键说话 → 系统级语音转文字（SFSpeechRecognizer）→ 粘贴到当前输入框。
//  麦克风可在 App 内选择：Mac 默认输入设备，或任意已接入的输入设备（含遥控器麦克风，
//  前提是它在 CoreAudio 里以输入设备形式出现）。
//

import Foundation
import AVFoundation
import Speech
import CoreAudio
import Combine

// MARK: - 输入设备枚举

struct AudioInputDevice: Identifiable, Hashable {
    let id: String        // CoreAudio UID
    let name: String
    let deviceID: AudioDeviceID
}

enum AudioInputDevices {
    static func list() -> [AudioInputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address,
                                             0, nil, &dataSize) == noErr else { return [] }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                         0, nil, &dataSize, &ids) == noErr else { return [] }

        return ids.compactMap { deviceID -> AudioInputDevice? in
            guard hasInput(deviceID) else { return nil }
            let name = name(of: deviceID) ?? "未知设备"
            let uid = uid(of: deviceID) ?? "\(deviceID)"
            // 跳过聚合设备的空壳条目
            guard !name.isEmpty else { return nil }
            return AudioInputDevice(id: uid, name: name, deviceID: deviceID)
        }
    }

    static func device(forUID uid: String) -> AudioInputDevice? {
        list().first { $0.id == uid }
    }

    private static func hasInput(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr else { return false }
        return size > 0
    }

    private static func name(of deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &name) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer)
        }
        guard status == noErr else { return nil }
        return name as String
    }

    private static func uid(of deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &uid) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer)
        }
        guard status == noErr else { return nil }
        return uid as String
    }
}

// MARK: - 语音识别

final class VoiceInputController: ObservableObject {
    static let shared = VoiceInputController()

    enum State: Equatable {
        case idle
        case listening
        case finishing
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var transcript: String = ""
    @Published private(set) var level: Float = 0
    @Published var authorized: Bool = false
    @Published var micDevices: [AudioInputDevice] = []
    /// 选择「遥控器麦克风」时使用的标记值
    static let remoteMicTag = "remote-mic"
    /// 空字符串 = 跟随系统默认输入设备
    @Published var selectedDeviceUID: String = UserDefaults.standard.string(forKey: "voice.deviceUID") ?? "" {
        willSet {
            UserDefaults.standard.set(newValue, forKey: "voice.deviceUID")
        }
    }
    @Published var locale: String = UserDefaults.standard.string(forKey: "voice.locale") ?? "zh-CN" {
        didSet { UserDefaults.standard.set(locale, forKey: "voice.locale") }
    }
    /// 实时转写浮窗：默认关闭，避免遮挡输入框 / 抢焦点。
    /// 换用 v2 key，让旧版本残留的 true 不会让浮窗重新冒出来。
    @Published var showHUD: Bool = UserDefaults.standard.object(forKey: "voice.showHUD.v2") as? Bool ?? false {
        didSet {
            UserDefaults.standard.set(showHUD, forKey: "voice.showHUD.v2")
            if !showHUD { VoiceHUDController.shared.hide(animated: false) }
        }
    }
    /// 停止后是否自动粘贴到前台应用
    @Published var autoPaste: Bool = UserDefaults.standard.object(forKey: "voice.autoPaste") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoPaste, forKey: "voice.autoPaste") }
    }

    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var finalText: String = ""
    private var stopRequested = false

    var isListening: Bool { state == .listening }

    private init() {
        refreshDevices()
        checkAuthorization()
    }

    func refreshDevices() {
        micDevices = AudioInputDevices.list()
    }

    /// 遥控器的麦克风只有在 CoreAudio 把它暴露成输入设备时才可用
    var remoteMicDevice: AudioInputDevice? {
        let keys = ["siri", "remote", "apple tv", "appletv"]
        return micDevices.first { device in
            let name = device.name.lowercased()
            return keys.contains { name.contains($0) }
        }
    }

    var remoteMicAvailable: Bool { remoteMicDevice != nil }

    func checkAuthorization() {
        // 与概览页 / --diag 共用同一份探测结果，避免三处显示三种状态
        PermissionCenter.shared.refreshSync()
        authorized = PermissionCenter.shared.voiceGranted
    }

    func requestAuthorization(completion: (() -> Void)? = nil) {
        // 测试报告 4.3：裸二进制请求语音授权会 SIGABRT，必须在调用 TCC 前拦截
        if let reason = AppIdentity.voiceBlockReason() {
            state = .failed(reason)
            PermissionPrimer.log("🎙️ 跳过语音授权请求：\(reason)")
            DispatchQueue.main.async { completion?() }
            return
        }
        SFSpeechRecognizer.requestAuthorization { status in
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                DispatchQueue.main.async {
                    PermissionProbe.invalidateCachedStatuses()
                    self.checkAuthorization()
                    PermissionPrimer.log("🎙️ speech=\(status.rawValue) mic=\(PermissionCenter.shared.microphoneRaw) authorized=\(self.authorized)")
                    completion?()
                }
            }
        }
    }

    // MARK: - 开始 / 停止

    func start() {
        guard !isListening else { return }
        if !authorized {
            requestAuthorization { [weak self] in
                guard let self = self, self.authorized else {
                    self?.state = .failed("还没授予麦克风 / 语音识别权限，请到「语音输入」页点“请求授权”")
                    return
                }
                self.start()
            }
            return
        }
        finalText = ""
        transcript = ""
        stopRequested = false

        // TCC 只认 App bundle 里的 usage description；从 shell 直接跑二进制会直接 abort，
        // 这里直接拒绝，给出可读提示。
        guard AppIdentity.isAppBundle else {
            state = .failed(AppIdentity.voiceBlockReason() ?? "请通过 vibedeck.app 启动")
            PermissionPrimer.log("🎙️ 非 .app 启动，跳过语音识别")
            return
        }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)), recognizer.isAvailable else {
            state = .failed("当前语言（\(locale)）的语音识别不可用，请在「语音」页换一个语言")
            PermissionPrimer.log("🎙️ recognizer unavailable for \(locale)")
            return
        }
        self.recognizer = recognizer

        let engine = AVAudioEngine()
        self.engine = engine

        // 解析麦克风选择：遥控器 / 指定设备 / 系统默认
        var resolvedUID = selectedDeviceUID
        if resolvedUID == VoiceInputController.remoteMicTag {
            if let remote = remoteMicDevice {
                resolvedUID = remote.id
                PermissionPrimer.log("🎙️ 使用遥控器麦克风：\(remote.name)")
            } else {
                resolvedUID = ""
                PermissionPrimer.log("🎙️ 遥控器麦克风未被 macOS 暴露为输入设备，回退到系统默认麦克风")
            }
        }

        // 可选：把输入切到指定设备（例如遥控器麦克风）
        if !resolvedUID.isEmpty, let device = AudioInputDevices.device(forUID: resolvedUID) {
            if let unit = engine.inputNode.audioUnit {
                var deviceID = device.deviceID
                let status = AudioUnitSetProperty(unit,
                                                  kAudioOutputUnitProperty_CurrentDevice,
                                                  kAudioUnitScope_Global, 0,
                                                  &deviceID,
                                                  UInt32(MemoryLayout<AudioDeviceID>.size))
                PermissionPrimer.log("🎙️ input device → \(device.name) (status \(status))")
            }
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            state = .failed("所选麦克风没有输入通道，请换一个设备")
            self.engine = nil
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            if let result = result {
                let text = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    self.transcript = text
                    self.finalText = text
                }
                if result.isFinal {
                    DispatchQueue.main.async { self.finishIfNeeded() }
                }
            }
            if let error = error, !self.stopRequested {
                let message = error.localizedDescription
                DispatchQueue.main.async {
                    PermissionPrimer.log("🎙️ recognition error: \(message)")
                    self.state = .failed(message)
                    self.teardown()
                }
            }
        }

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            guard let self = self else { return }
            let level = VoiceInputController.rms(buffer)
            DispatchQueue.main.async { self.level = level }
        }

        do {
            engine.prepare()
            try engine.start()
            state = .listening
            if showHUD { VoiceHUDController.shared.show() }
            PermissionPrimer.log("🎙️ listening (locale=\(locale), device=\(selectedDeviceUID.isEmpty ? "system default" : selectedDeviceUID))")
        } catch {
            VoiceHUDController.shared.hide()
            state = .failed("麦克风启动失败：\(error.localizedDescription)")
            PermissionPrimer.log("🎙️ engine start failed: \(error)")
            teardown()
        }
    }

    /// 结束识别（松开语音键时调用）
    func stop() {
        guard isListening else { return }
        stopRequested = true
        state = .finishing
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        request?.endAudio()
        // 给识别器一点时间吐最终结果
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.finishIfNeeded()
        }
    }

    private func finishIfNeeded() {
        guard state != .idle else { return }
        VoiceHUDController.shared.hide()
        let text = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        teardown()
        state = .idle
        guard !text.isEmpty else {
            PermissionPrimer.log("🎙️ no speech recognised")
            return
        }
        PermissionPrimer.log("🎙️ transcript: \(text)")
        if autoPaste {
            KeySender.paste(text: text)
        }
    }

    private func teardown() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        request?.endAudio()
        task?.cancel()
        engine = nil
        request = nil
        task = nil
        level = 0
    }

    private static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<count {
            let value = channel[index]
            sum += value * value
        }
        let rms = sqrt(sum / Float(count))
        return min(max(rms * 12, 0), 1)
    }
}
