//
//  RemoteDetector.swift
//  Remotastic
//
//  Detects Siri Remote via IOKit HID
//

import IOKit
import IOKit.hid

class RemoteDetector {
    private var manager: IOHIDManager?
    private var deviceCallback: ((IOHIDDevice?) -> Void)?
    private var currentDevice: IOHIDDevice?
    // 一个 A2540 会暴露 7 个 HID 接口，全部共享 vendor:product。
    // 必须按接口对象分别跟踪：否则任一接口移除就会把整台设备误判为断开，
    // 回调 nil 清空 RemoteInputHandler.devices，刚恢复的接管立刻失效。
    private var knownInterfaces: Set<ObjectIdentifier> = []
    private var loggedKeys: Set<String> = []
    private let processingQueue = DispatchQueue(label: "com.remotastic.deviceProcessing")
    
    private let appleVendorID: Int = 0x004C
    
    // Known Siri Remote / Apple TV Remote product IDs
    // 0x0314 = 2nd-gen Siri Remote (A2540) — verified locally on this Mac
    // 0x0315 = 3rd-gen Siri Remote (A2854)
    private let knownProductIDs: [Int] = [
        0x0221, 0x0255, 0x0266, 0x0267, 0x0269,
        0x0C4E, 0x0C4F, 0x030D, 0x030E, 0x0314, 0x0315
    ]
    
    init(deviceCallback: @escaping (IOHIDDevice?) -> Void) {
        self.deviceCallback = deviceCallback
    }
    
    func startDetection() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let manager = manager else { return }
        
        let matchingDict: [String: Any] = [kIOHIDVendorIDKey: appleVendorID]
        IOHIDManagerSetDeviceMatching(manager, matchingDict as CFDictionary)
        
        IOHIDManagerRegisterDeviceMatchingCallback(manager, deviceAddedCallback, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterDeviceRemovalCallback(manager, deviceRemovedCallback, Unmanaged.passUnretained(self).toOpaque())
        
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { return }
        
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.enumerateAllDevices()
        }
    }
    
    /// 恢复接管时重新枚举当前已连接的遥控器 HID 接口，
    /// 用于补回休眠期间被移除 / 重新枚举的设备。
    func refreshDevices() {
        DispatchQueue.main.async { [weak self] in
            self?.enumerateAllDevices()
        }
    }

    func stopDetection() {
        if let manager = manager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            self.manager = nil
        }
        currentDevice = nil
        knownInterfaces.removeAll()
        loggedKeys.removeAll()
        deviceCallback?(nil)
    }
    
    private func enumerateAllDevices() {
        guard let manager = manager,
              let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return }
        
        // Use the same isSiriRemote check for consistency
        for device in deviceSet {
            if isSiriRemote(device) {
                handleDeviceAdded(device)
            }
        }
    }
    
    private func isSiriRemote(_ device: IOHIDDevice) -> Bool {
        guard let vendorID = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int,
              vendorID == appleVendorID else { return false }
        
        if let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int,
           knownProductIDs.contains(productID) {
            return true
        }
        
        if let productName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String {
            let name = productName.lowercased()
            return name.contains("remote") || name.contains("siri") || name.contains("apple tv")
        }
        
        return false
    }
    
    func handleDeviceAdded(_ device: IOHIDDevice) {
        guard isSiriRemote(device) else { return }

        let vendorID = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
        let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        let deviceKey = "\(vendorID):\(productID)"
        let identifier = ObjectIdentifier(device)

        processingQueue.async { [weak self] in
            guard let self = self else { return }
            let isNewInterface = self.knownInterfaces.insert(identifier).inserted
            let shouldLog = !self.loggedKeys.contains(deviceKey)
            if shouldLog { self.loggedKeys.insert(deviceKey) }
            self.currentDevice = device

            if shouldLog {
                let productName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Unknown"
                print("✅ Siri Remote connected: \(productName) (Vendor: 0x\(String(vendorID, radix: 16, uppercase: true)), Product: 0x\(String(productID, radix: 16, uppercase: true)))")
            }
            // 每个接口都要交给 RemoteInputHandler（它内部会去重），
            // 同时让「设备重新出现」成为休眠期间的第二条唤醒路径。
            if isNewInterface || self.knownInterfaces.count == 1 {
                DispatchQueue.main.async { self.deviceCallback?(device) }
            }
        }
    }

    func handleDeviceRemoved(_ device: IOHIDDevice) {
        guard isSiriRemote(device) else { return }
        let identifier = ObjectIdentifier(device)

        processingQueue.async { [weak self] in
            guard let self = self else { return }
            guard self.knownInterfaces.contains(identifier) else { return }
            self.knownInterfaces.remove(identifier)

            // 只有最后一个接口也消失，才算整台遥控器断开。
            // 蓝牙睡眠时单个接口会短暂重枚举，不能因此清空已恢复的接管。
            guard self.knownInterfaces.isEmpty else { return }
            self.loggedKeys.removeAll()
            let productName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Unknown"
            print("❌ Siri Remote disconnected: \(productName)")
            self.currentDevice = nil
            DispatchQueue.main.async { self.deviceCallback?(nil) }
        }
    }
}

// C callbacks
private func deviceAddedCallback(context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?, device: IOHIDDevice) {
    guard let context = context else { return }
    let detector = Unmanaged<RemoteDetector>.fromOpaque(context).takeUnretainedValue()
    detector.handleDeviceAdded(device)
}

private func deviceRemovedCallback(context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?, device: IOHIDDevice) {
    guard let context = context else { return }
    let detector = Unmanaged<RemoteDetector>.fromOpaque(context).takeUnretainedValue()
    detector.handleDeviceRemoved(device)
}
