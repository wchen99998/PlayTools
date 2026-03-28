//
//  ControlMode.swift
//  PlayTools
//

import Foundation
import GameController
import UIKit

let mode = ControlMode.mode

public enum ControlModeLiteral: String {
    case textInput
    case cameraRotate
    case arbitraryClick
    case off
    case editor
}
// This class handles different control logic under different control mode

public class ControlMode: Equatable {
    static public let mode = ControlMode()

    private var controlMode = ControlModeLiteral.off

    private var keyboardAdapter: KeyboardEventAdapter!
    private var mouseAdapter: MouseEventAdapter!
    private var controllerAdapter: ControllerEventAdapter!
    private var keyWindowObserver: NSObjectProtocol?
    private let textInputBridge = UIKitTextInputBridge()

    public func cursorHidden() -> Bool {
        return mouseAdapter?.cursorHidden() ?? false
    }

    public func initialize() {
        setupTextInputObservers()
        setupTextInputBridge()

        if PlaySettings.shared.noKMOnInput {
            set(.arbitraryClick)
        } else {
            set(.off)
        }

        setupGameController()
        setupKeyboard()
        if PlaySettings.shared.enableScrollWheel {
            setupScrollWheel()
        }

        // Mouse polling rate as high as 1000 causes issue to some games
        setupMouseMoved(maxPollingRate: 125)
        setupMouseButtons()

        if PlaySettings.shared.resizableWindow {
            initializeResizableWindowSupport()
        }

        ActionDispatcher.build()
    }

    private func setupTextInputObservers() {
        let centre = NotificationCenter.default
        let main = OperationQueue.main
        centre.addObserver(forName: UITextField.textDidEndEditingNotification, object: nil, queue: main) { notification in
            self.textInputBridge.endEditing(notification.object as? UIResponder)
            if PlaySettings.shared.noKMOnInput {
                ModeAutomaton.onUITextInputEndEdit()
            }
            Toucher.writeLog(logMessage: "uitextinput end edit")
        }
        centre.addObserver(forName: UITextField.textDidBeginEditingNotification, object: nil, queue: main) { notification in
            self.textInputBridge.beginEditing(notification.object as? UIResponder)
            if PlaySettings.shared.noKMOnInput {
                ModeAutomaton.onUITextInputBeginEdit()
            }
            Toucher.writeLog(logMessage: "uitextinput begin edit")
        }
        centre.addObserver(forName: UITextView.textDidEndEditingNotification, object: nil, queue: main) { notification in
            self.textInputBridge.endEditing(notification.object as? UIResponder)
            if PlaySettings.shared.noKMOnInput {
                ModeAutomaton.onUITextInputEndEdit()
            }
            Toucher.writeLog(logMessage: "uitextinput end edit")
        }
        centre.addObserver(forName: UITextView.textDidBeginEditingNotification, object: nil, queue: main) { notification in
            self.textInputBridge.beginEditing(notification.object as? UIResponder)
            if PlaySettings.shared.noKMOnInput {
                ModeAutomaton.onUITextInputBeginEdit()
            }
            Toucher.writeLog(logMessage: "uitextinput begin edit")
        }
    }

    private func setupTextInputBridge() {
        guard let textInputBridgePlugin = AKInterface.shared as? PluginTextInputBridge else {
            Toucher.writeLog(logMessage: "plugin missing text input bridge support")
            return
        }

        textInputBridgePlugin.setupTextInputBridge(
            isEditing: { [weak self] in
                guard let self else {
                    return false
                }
                return self.controlMode != .editor && self.textInputBridge.isEditing
            },
            insertText: { [weak self] text in
                self?.textInputBridge.insertText(text)
            },
            setMarkedText: { [weak self] text, selectedRange in
                self?.textInputBridge.setMarkedText(text, selectedRange: selectedRange)
            },
            unmarkText: { [weak self] in
                self?.textInputBridge.unmarkText()
            },
            deleteBackward: { [weak self] in
                self?.textInputBridge.deleteBackward()
            },
            selectedRange: { [weak self] in
                self?.textInputBridge.selectedRange ?? NSRange(location: NSNotFound, length: 0)
            },
            markedRange: { [weak self] in
                self?.textInputBridge.markedRange ?? NSRange(location: NSNotFound, length: 0)
            },
            markedText: { [weak self] in
                self?.textInputBridge.markedText ?? ""
            },
            caretRectInWindow: { [weak self] in
                self?.textInputBridge.caretRectInWindow ?? .zero
            }
        )
    }

    private func setupGameController() {
        let centre = NotificationCenter.default
        let main = OperationQueue.main
        centre.addObserver(forName: NSNotification.Name.GCControllerDidConnect, object: nil, queue: main) { _ in
            GCController.shouldMonitorBackgroundEvents = true
            GCController.current?.extendedGamepad?.valueChangedHandler = { profile, element in
                self.controllerAdapter.handleValueChanged(profile, element)
            }
        }
    }

    private func setupKeyboard() {
        AKInterface.shared!.setupKeyboard(
            keyboard: { keycode, pressed, isRepeat, ctrlModified in
                self.keyboardAdapter.handleKey(
                    keycode: keycode,
                    pressed: pressed,
                    isRepeat: isRepeat,
                    ctrlModified: ctrlModified
                )
            },
            swapMode: ModeAutomaton.onOption
        )
    }

    private func setupScrollWheel() {
        AKInterface.shared!.setupScrollWheel({ deltaX, deltaY in
            self.mouseAdapter.handleScrollWheel(deltaX: deltaX, deltaY: deltaY)
        })
    }

    private func setupMouseButtons() {
        AKInterface.shared!.setupMouseButton(left: true, right: false, { _, pressed in
            self.mouseAdapter.handleLeftButton(pressed: pressed)
        })

        AKInterface.shared!.setupMouseButton(left: false, right: false, { id, pressed in
            self.mouseAdapter.handleOtherButton(id: id, pressed: pressed)
        })

        AKInterface.shared!.setupMouseButton(left: false, right: true, { id, pressed in
            self.mouseAdapter.handleOtherButton(id: id, pressed: pressed)
        })
    }

    private func initializeResizableWindowSupport() {
        // Reactivate keymapping once the key window is initialized
        keyWindowObserver = NotificationCenter.default.addObserver(forName: UIWindow.didBecomeKeyNotification,
            object: nil, queue: .main) { _ in
            ActionDispatcher.build()
            if let observer = self.keyWindowObserver {
                NotificationCenter.default.removeObserver(observer)
                self.keyWindowObserver = nil
            }
        }
        // Reactivate keymapping once the user finishes resizing the window
        NotificationCenter.default.addObserver(forName: Notification.Name("NSWindowDidEndLiveResizeNotification"),
            object: nil, queue: .main) { _ in
            ActionDispatcher.build()
        }
    }

    private func setupMouseMoved(maxPollingRate: Int) {
        let minMoveInterval =
            DispatchTimeInterval.milliseconds(1000/maxPollingRate)
        var lastMoveWhen = DispatchTime.now()
        // Repeat the return value of last processed event
        var consumed = true
        var movement: CGVector = CGVector()

        AKInterface.shared!.setupMouseMoved({deltaX, deltaY in
            // limit move frequency
            let now = DispatchTime.now()
            movement.dy += deltaY
            movement.dx += deltaX
            if now < lastMoveWhen.advanced(by: minMoveInterval) {
                return consumed
            }

            lastMoveWhen = now
            consumed = self.mouseAdapter.handleMove(deltaX: movement.dx, deltaY: movement.dy)
            movement.dy = 0
            movement.dx = 0
            return consumed
        })
    }

    public func set(_ mode: ControlModeLiteral) {
        let wasHidden = mouseAdapter?.cursorHidden() ?? false
        let first = mouseAdapter == nil
        keyboardAdapter = EventAdapters.keyboard(controlMode: mode)
        mouseAdapter = EventAdapters.mouse(controlMode: mode)
        controllerAdapter = EventAdapters.controller(controlMode: mode)
        controlMode = mode
        if !first {
//            Toast.showHint(title: "should hide cursor? \(mouseAdapter.cursorHidden())",
//                       text: ["current state: " + mode])
        }
        if mouseAdapter.cursorHidden() != wasHidden && settings.keymapping {
            if wasHidden {
                NotificationCenter.default.post(name: NSNotification.Name.playtoolsCursorWillShow,
                                                object: nil, userInfo: [:])
                if screen.fullscreen {
                    screen.switchDock(true)
                }

                if mode == .off || mode == .editor {
                    ActionDispatcher.invalidateActions()
                } else {
                    // In case any touch point failed to release
                    // (might because of system glitch)
                    // Work around random zoom in zoom out
                    ActionDispatcher.invalidateNonButtonActions()
                }

                AKInterface.shared!.unhideCursor()
            } else {
                NotificationCenter.default.post(name: NSNotification.Name.playtoolsCursorWillHide,
                                                object: nil, userInfo: [:])
                AKInterface.shared!.hideCursor()

                // Fix when people hold fake mouse while pressing option
                // and it becomes random zoom in zoom out
                ActionDispatcher.invalidateNonButtonActions()

                if screen.fullscreen {
                    screen.switchDock(false)
                }
            }
            Toucher.writeLog(logMessage: "cursor show switched to \(!wasHidden)")
        }
    }

    public static func == (lhs: ControlModeLiteral, rhs: ControlMode) -> Bool {
        lhs == rhs.controlMode
    }

    public static func == (lhs: ControlMode, rhs: ControlModeLiteral) -> Bool {
        rhs == lhs
    }

    public static func == (lhs: ControlMode, rhs: ControlMode) -> Bool {
        rhs.controlMode == lhs.controlMode
    }

}

private typealias ActiveTextInputResponder = UIResponder & UITextInput

private final class UIKitTextInputBridge {
    private weak var activeResponder: UIResponder?

    var isEditing: Bool {
        currentTextInputResponder() != nil
    }

    var selectedRange: NSRange? {
        guard let responder = currentTextInputResponder(),
              let range = responder.selectedTextRange else {
            return nil
        }

        return nsRange(from: range, in: responder)
    }

    var markedRange: NSRange? {
        guard let responder = currentTextInputResponder(),
              let range = responder.markedTextRange else {
            return nil
        }

        return nsRange(from: range, in: responder)
    }

    var markedText: String? {
        guard let responder = currentTextInputResponder(),
              let range = responder.markedTextRange else {
            return nil
        }

        return responder.text(in: range)
    }

    var caretRectInWindow: CGRect? {
        guard let responder = currentTextInputResponder(),
              let view = responder as? UIView,
              let window = view.window else {
            return nil
        }

        if let selectedRange = responder.selectedTextRange {
            let caretRect = responder.caretRect(for: selectedRange.start)
            return view.convert(caretRect, to: window)
        }

        return view.convert(view.bounds, to: window)
    }

    func beginEditing(_ responder: UIResponder?) {
        activeResponder = responder
    }

    func endEditing(_ responder: UIResponder?) {
        guard let responder else {
            activeResponder = nil
            return
        }

        if activeResponder === responder {
            activeResponder = nil
        }
    }

    func insertText(_ text: String) {
        guard !text.isEmpty,
              let responder = currentTextInputResponder() else {
            return
        }

        responder.insertText(text)
    }

    func setMarkedText(_ text: String, selectedRange: NSRange) {
        guard let responder = currentTextInputResponder() else {
            return
        }

        responder.setMarkedText(text, selectedRange: selectedRange)
    }

    func unmarkText() {
        currentTextInputResponder()?.unmarkText()
    }

    func deleteBackward() {
        currentTextInputResponder()?.deleteBackward()
    }

    private func currentTextInputResponder() -> ActiveTextInputResponder? {
        if let responder = activeResponder as? ActiveTextInputResponder,
           responder.isFirstResponder {
            return responder
        }

        let responder = locateActiveTextInputResponder()
        activeResponder = responder
        return responder
    }

    private func locateActiveTextInputResponder() -> ActiveTextInputResponder? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes
            .flatMap(\.windows)
            .sorted { lhs, rhs in
                if lhs.isKeyWindow != rhs.isKeyWindow {
                    return lhs.isKeyWindow
                }
                if lhs.windowLevel != rhs.windowLevel {
                    return lhs.windowLevel.rawValue > rhs.windowLevel.rawValue
                }
                return !lhs.isHidden && rhs.isHidden
            }

        for window in windows {
            if let responder = findTextInputResponder(in: window) {
                return responder
            }
        }

        return nil
    }

    private func findTextInputResponder(in view: UIView) -> ActiveTextInputResponder? {
        if view.isFirstResponder,
           let responder = view as? ActiveTextInputResponder {
            return responder
        }

        for subview in view.subviews.reversed() {
            if let responder = findTextInputResponder(in: subview) {
                return responder
            }
        }

        return nil
    }

    private func nsRange(from textRange: UITextRange, in responder: ActiveTextInputResponder) -> NSRange {
        let location = responder.offset(from: responder.beginningOfDocument, to: textRange.start)
        let length = responder.offset(from: textRange.start, to: textRange.end)
        return NSRange(location: max(0, location), length: max(0, length))
    }
}

extension NSNotification.Name {
    public static let playtoolsCursorWillHide: NSNotification.Name
                    = NSNotification.Name("playtools.cursorWillHide")

    public static let playtoolsCursorWillShow: NSNotification.Name
                    = NSNotification.Name("playtools.cursorWillShow")
}
