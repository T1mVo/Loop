//
//  KeybindMonitor.swift
//  Loop
//
//  Created by Kai Azim on 2023-06-18.
//

import Cocoa
import Defaults

class KeybindMonitor {
    static let shared = KeybindMonitor()

    private var eventMonitor: CGEventMonitor?
    private var flagsEventMonitor: CGEventMonitor?
    private var pressedKeys = Set<CGKeyCode>()
    private var lastKeyReleaseTime: Date = Date.now

    // Currently, special events only contain the globe key, as it can also be used as a emoji key.
    private let specialEvents: [CGKeyCode] = [179]
    var canPassthroughSpecialEvents = true  // If mouse has been moved

    func resetPressedKeys() {
        KeybindMonitor.shared.pressedKeys = []
    }

    func start() {
        guard self.eventMonitor == nil,
              PermissionsManager.Accessibility.getStatus() else {
            return
        }

        self.eventMonitor = CGEventMonitor(eventMask: [.keyDown, .keyUp]) { cgEvent in
             if cgEvent.type == .keyDown || cgEvent.type == .keyUp,
                let event = NSEvent(cgEvent: cgEvent),
                !event.isARepeat {

                 if !self.specialEvents.contains(event.keyCode.baseKey) {
                     if event.type == .keyUp {
                         KeybindMonitor.shared.pressedKeys.remove(event.keyCode.baseKey)
                     } else if event.type == .keyDown {
                         KeybindMonitor.shared.pressedKeys.insert(event.keyCode.baseKey)
                     }

                     if self.performKeybind(event: event) {
                         return nil
                     }
                 } else {
                     if self.canPassthroughSpecialEvents {
                         return Unmanaged.passRetained(cgEvent)
                     } else {
                         return nil
                     }
                 }
            }

            return Unmanaged.passRetained(cgEvent)
        }

        self.flagsEventMonitor = CGEventMonitor(eventMask: .flagsChanged) { cgEvent in
            if cgEvent.type == .flagsChanged,
               let event = NSEvent(cgEvent: cgEvent),
               !Defaults[.triggerKey].contains(where: { $0.baseModifier == event.keyCode.baseModifier }) {

                self.checkForModifier(event, .kVK_Shift, .shift)
                self.checkForModifier(event, .kVK_Command, .command)
                self.checkForModifier(event, .kVK_Option, .option)
                self.checkForModifier(event, .kVK_Function, .function)

                self.performKeybind(event: event)
            }
            return Unmanaged.passRetained(cgEvent)
        }

        self.eventMonitor!.start()
        self.flagsEventMonitor!.start()
    }

    func stop() {
        self.resetPressedKeys()
        self.canPassthroughSpecialEvents = true

        guard self.eventMonitor != nil &&
              self.flagsEventMonitor != nil else {
            return
        }

        self.eventMonitor?.stop()
        self.eventMonitor = nil

        self.flagsEventMonitor?.stop()
        self.flagsEventMonitor = nil
    }

    @discardableResult
    private func performKeybind(event: NSEvent) -> Bool {
        // If the current key up event is within 100 ms of the last key up event, return.
        // This is used when the user is pressing 2+ keys so that it doesn't switch back
        // to the one key direction when they're letting go of the keys.
        if event.type == .keyUp ||
            (event.type == .flagsChanged &&
             !event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.shift)) {
            if (abs(lastKeyReleaseTime.timeIntervalSinceNow)) > 0.1 {
                return true
            }
            lastKeyReleaseTime = Date.now
        }

        if pressedKeys.contains(.kVK_Escape) {
            Notification.Name.forceCloseLoop.post()
            return true
        }

        if let newAction = WindowAction.getAction(for: pressedKeys) {
            Notification.Name.directionChanged.post(userInfo: ["action": newAction])
            return true
        }

        // If this wasn't a valid keybind, return false, which will
        // then forward the key event to the frontmost app
        return false
    }

    private func checkForModifier(_ event: NSEvent, _ key: CGKeyCode, _ modifierFlag: NSEvent.ModifierFlags) {
        if event.keyCode.baseKey == key {
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(modifierFlag) {
                KeybindMonitor.shared.pressedKeys.insert(key)
            } else {
                KeybindMonitor.shared.pressedKeys.remove(key)
            }
        }
    }
}
