//
//  MacPlugin.swift
//  AKInterface
//
//  Created by Isaac Marovitz on 13/09/2022.
//

import AppKit
import CoreGraphics
import Foundation

// Add a lightweight struct so we can decode only the flag we care about
private struct AKAppSettingsData: Codable {
    var hideTitleBar: Bool?
    var floatingWindow: Bool?
    var resolution: Int?
    var resizableAspectRatioWidth: Int?
    var resizableAspectRatioHeight: Int?
}

private final class AKTextInputClientView: NSView, NSTextInputClient {
    var isEditing: () -> Bool = { false }
    var insertTextHandler: (String) -> Void = { _ in }
    var setMarkedTextHandler: (String, NSRange) -> Void = { _, _ in }
    var unmarkTextHandler: () -> Void = {}
    var deleteBackwardHandler: () -> Void = {}
    var selectedRangeProvider: () -> NSRange = { NSRange(location: NSNotFound, length: 0) }
    var markedRangeProvider: () -> NSRange = { NSRange(location: NSNotFound, length: 0) }
    var markedTextProvider: () -> String = { "" }
    var caretRectInWindowProvider: () -> CGRect = { .zero }
    var activeWindowProvider: () -> NSWindow? = { nil }

    private lazy var textInputContext = NSTextInputContext(client: self)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func handle(_ event: NSEvent) -> Bool {
        guard isEditing(), event.type == .keyDown else {
            return false
        }

        attachIfNeeded()
        textInputContext.activate()
        return textInputContext.handleEvent(event)
    }

    func clearMarkedText() {
        textInputContext.discardMarkedText()
    }

    private func attachIfNeeded() {
        guard let window = activeWindowProvider(), let contentView = window.contentView else {
            return
        }

        if superview !== contentView {
            removeFromSuperview()
            frame = .zero
            contentView.addSubview(self)
        }
    }

    override func doCommand(by selector: Selector) {
        switch selector {
        case #selector(NSResponder.deleteBackward(_:)):
            deleteBackwardHandler()
        case #selector(NSResponder.insertNewline(_:)),
             #selector(NSResponder.insertLineBreak(_:)):
            insertTextHandler("\n")
        case #selector(NSResponder.insertTab(_:)):
            insertTextHandler("\t")
        case #selector(NSResponder.cancelOperation(_:)):
            unmarkTextHandler()
        default:
            break
        }
    }

    func insertText(_ string: Any, replacementRange: NSRange) {
        let committedText: String
        if let attributed = string as? NSAttributedString {
            committedText = attributed.string
        } else if let plain = string as? String {
            committedText = plain
        } else {
            committedText = "\(string)"
        }

        guard !committedText.isEmpty else {
            return
        }

        insertTextHandler(committedText)
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        let markedText: String
        if let attributed = string as? NSAttributedString {
            markedText = attributed.string
        } else if let plain = string as? String {
            markedText = plain
        } else {
            markedText = "\(string)"
        }

        setMarkedTextHandler(markedText, selectedRange)
    }

    func unmarkText() {
        unmarkTextHandler()
    }

    func selectedRange() -> NSRange {
        selectedRangeProvider()
    }

    func markedRange() -> NSRange {
        markedRangeProvider()
    }

    func hasMarkedText() -> Bool {
        let range = markedRange()
        return range.location != NSNotFound && range.length > 0
    }

    func attributedSubstring(forProposedRange range: NSRange,
                             actualRange: NSRangePointer?) -> NSAttributedString? {
        let currentMarkedRange = markedRange()
        guard currentMarkedRange.location != NSNotFound else {
            return nil
        }

        let currentMarkedText = markedTextProvider()
        guard !currentMarkedText.isEmpty else {
            return nil
        }

        actualRange?.pointee = currentMarkedRange
        return NSAttributedString(string: currentMarkedText)
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        actualRange?.pointee = range

        guard let window = activeWindowProvider(), let contentView = window.contentView else {
            return .zero
        }

        let caretRect = caretRectInWindowProvider()
        guard !caretRect.isEmpty else {
            return window.convertToScreen(window.frame)
        }

        let appKitRect = NSRect(
            x: caretRect.origin.x,
            y: max(0, contentView.bounds.height - caretRect.maxY),
            width: max(caretRect.width, 1),
            height: max(caretRect.height, 1)
        )
        let windowRect = contentView.convert(appKitRect, to: nil)
        return window.convertToScreen(windowRect)
    }

    func characterIndex(for point: NSPoint) -> Int {
        let range = selectedRange()
        return range.location == NSNotFound ? 0 : range.location
    }
}

class AKPlugin: NSObject, Plugin, PluginTextInputBridge {
    private static let leftOptionKeyCode: UInt16 = 58
    private static let rightOptionKeyCode: UInt16 = 61
    private let textInputClient = AKTextInputClientView(frame: .zero)

    private func containsUIKitContent(_ window: NSWindow) -> Bool {
        let uiWindows = window.value(forKey: "uiWindows") as? [Any]
        return !(uiWindows?.isEmpty ?? true)
    }

    private func activeGameplayWindow(preferred preferredWindow: NSWindow? = nil) -> NSWindow? {
        let preferredWindows = [
            preferredWindow,
            NSApplication.shared.currentEvent?.window,
            NSApplication.shared.keyWindow,
            NSApplication.shared.mainWindow
        ].compactMap { $0 }

        if let window = preferredWindows.first(where: { containsUIKitContent($0) }) {
            return window
        }

        return NSApplication.shared.windows.first(where: { containsUIKitContent($0) })
            ?? preferredWindows.first
            ?? NSApplication.shared.windows.first
    }

    private func applyWindowConfiguration(to window: NSWindow) {
        window.styleMask.insert([.resizable])
        window.collectionBehavior = [.fullScreenPrimary, .managed, .participatesInCycle]
        window.isMovable = true
        window.isMovableByWindowBackground = true

        if self.hideTitleBarSetting == true {
            window.styleMask.insert([.fullSizeContentView])
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.toolbar = nil
            window.title = ""
        }

        if self.floatingWindowSetting == true {
            window.level = .floating
        }

        if let aspectRatio = self.aspectRatioSetting {
            window.contentAspectRatio = aspectRatio
        }
    }

    required override init() {
        super.init()
        textInputClient.activeWindowProvider = { [weak self] in
            self?.activeGameplayWindow()
        }
        if let window = activeGameplayWindow() {
            applyWindowConfiguration(to: window)
            NSWindow.allowsAutomaticWindowTabbing = true
        }

        // Apply the same appearance rules to any subsequent windows that may be created
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main) { notif in
                guard let win = notif.object as? NSWindow else { return }
                guard self.containsUIKitContent(win) else { return }
                self.applyWindowConfiguration(to: win)
        }
    }

    var screenCount: Int {
        NSScreen.screens.count
    }

    var mousePoint: CGPoint {
        activeGameplayWindow()?.mouseLocationOutsideOfEventStream ?? CGPoint()
    }

    var windowFrame: CGRect {
        guard let window = activeGameplayWindow() else {
            return CGRect()
        }
        // `mouseLocationOutsideOfEventStream` is reported in the window's content-space.
        // Use the content rect here so mouse-to-touch scaling matches the playable surface.
        return window.contentRect(forFrameRect: window.frame)
    }

    var isMainScreenEqualToFirst: Bool {
        let activeScreen = activeGameplayWindow()?.screen ?? NSScreen.main
        return activeScreen == NSScreen.screens.first
    }

    var mainScreenFrame: CGRect {
        (activeGameplayWindow()?.screen ?? NSScreen.main ?? NSScreen.screens.first)?.frame ?? CGRect()
    }

    var isFullscreen: Bool {
        activeGameplayWindow()?.styleMask.contains(.fullScreen) ?? false
    }

    var cmdPressed: Bool = false
    var cursorHideLevel = 0
    func hideCursor() {
        NSCursor.hide()
        cursorHideLevel += 1
        CGAssociateMouseAndMouseCursorPosition(0)
        warpCursor()
    }

    func hideCursorMove() {
        NSCursor.setHiddenUntilMouseMoves(true)
    }

    func warpCursor() {
        guard let firstScreen = NSScreen.screens.first else {return}
        let frame = windowFrame
        // Convert from NS coordinates to CG coordinates
        CGWarpMouseCursorPosition(CGPoint(x: frame.midX, y: firstScreen.frame.maxY - frame.midY))
    }

    func unhideCursor() {
        NSCursor.unhide()
        cursorHideLevel -= 1
        if cursorHideLevel <= 0 {
            CGAssociateMouseAndMouseCursorPosition(1)
        }
    }

    func terminateApplication() {
        NSApplication.shared.terminate(self)
    }

    private var modifierFlag: UInt = 0
    private var swapModeShortcutActive = false

    private func isOptionKey(_ keyCode: UInt16) -> Bool {
        keyCode == Self.leftOptionKeyCode || keyCode == Self.rightOptionKeyCode
    }

    private func isModifierPressed(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        switch keyCode {
        case 54, 55:
            modifierFlags.contains(.command)
        case 56, 60:
            modifierFlags.contains(.shift)
        case 57:
            modifierFlags.contains(.capsLock)
        case 58, 61:
            modifierFlags.contains(.option)
        case 59, 62:
            modifierFlags.contains(.control)
        default:
            modifierFlag < modifierFlags.rawValue
        }
    }

    // swiftlint:disable:next function_body_length
    func setupKeyboard(keyboard: @escaping (UInt16, Bool, Bool, Bool) -> Bool,
                       swapMode: @escaping () -> Bool) {
        func checkCmd(modifier: NSEvent.ModifierFlags) -> Bool {
            if modifier.contains(.command) {
                self.cmdPressed = true
                return true
            } else if self.cmdPressed {
                self.cmdPressed = false
            }
            return false
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            if checkCmd(modifier: event.modifierFlags) {
                return event
            }
            if self.textInputClient.isEditing() {
                if self.textInputClient.handle(event) {
                    return nil
                }
                return event
            }
            let consumed = keyboard(event.keyCode, true, event.isARepeat,
                                    event.modifierFlags.contains(.control))
            if consumed {
                return nil
            }
            return event
        })
        NSEvent.addLocalMonitorForEvents(matching: .keyUp, handler: { event in
            if checkCmd(modifier: event.modifierFlags) {
                return event
            }
            if self.textInputClient.isEditing() {
                return event
            }
            let consumed = keyboard(event.keyCode, false, false,
                                    event.modifierFlags.contains(.control))
            if consumed {
                return nil
            }
            return event
        })
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { event in
            if checkCmd(modifier: event.modifierFlags) {
                return event
            }
            let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let pressed = self.isModifierPressed(keyCode: event.keyCode, modifierFlags: modifierFlags)
            self.modifierFlag = modifierFlags.rawValue

            if self.textInputClient.isEditing() {
                return event
            }

            if self.isOptionKey(event.keyCode) {
                // If Option toggled cursor mode, swallow both edges so the next click is not treated as Option-click.
                if pressed {
                    self.swapModeShortcutActive = swapMode()
                    if self.swapModeShortcutActive {
                        return nil
                    }
                } else if self.swapModeShortcutActive {
                    self.swapModeShortcutActive = false
                    return nil
                }
                return event
            }
            let consumed = keyboard(event.keyCode, pressed, false,
                                    modifierFlags.contains(.control))
            if consumed {
                return nil
            }
            return event
        })
    }

    func setupTextInputBridge(
        isEditing: @escaping () -> Bool,
        insertText: @escaping (String) -> Void,
        setMarkedText: @escaping (String, NSRange) -> Void,
        unmarkText: @escaping () -> Void,
        deleteBackward: @escaping () -> Void,
        selectedRange: @escaping () -> NSRange,
        markedRange: @escaping () -> NSRange,
        markedText: @escaping () -> String,
        caretRectInWindow: @escaping () -> CGRect
    ) {
        textInputClient.isEditing = isEditing
        textInputClient.insertTextHandler = insertText
        textInputClient.setMarkedTextHandler = setMarkedText
        textInputClient.unmarkTextHandler = unmarkText
        textInputClient.deleteBackwardHandler = deleteBackward
        textInputClient.selectedRangeProvider = selectedRange
        textInputClient.markedRangeProvider = markedRange
        textInputClient.markedTextProvider = markedText
        textInputClient.caretRectInWindowProvider = caretRectInWindow
    }

    func setupMouseMoved(_ mouseMoved: @escaping (CGFloat, CGFloat) -> Bool) {
        let mask: NSEvent.EventTypeMask = [.leftMouseDragged, .otherMouseDragged, .rightMouseDragged]
        NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in
            let consumed = mouseMoved(event.deltaX, event.deltaY)
            if consumed {
                return nil
            }
            return event
        })
        // transpass mouse moved event when no button pressed, for traffic light button to light up
        NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { event in
            _ = mouseMoved(event.deltaX, event.deltaY)
            return event
        })
    }

    func setupMouseButton(left: Bool, right: Bool, _ consumed: @escaping (Int, Bool) -> Bool) {
        let downType: NSEvent.EventTypeMask = left ? .leftMouseDown : right ? .rightMouseDown : .otherMouseDown
        let upType: NSEvent.EventTypeMask = left ? .leftMouseUp : right ? .rightMouseUp : .otherMouseUp

        // Helper to detect whether the event is inside any of the window "traffic-light" buttons
        func isInTrafficLightArea(_ event: NSEvent) -> Bool {
            if self.hideTitleBarSetting == false {
                return false
            }
            guard let win = event.window else { return false }
            let pointInWindow = event.locationInWindow
            let buttonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton, .fullScreenButton]
            for type in buttonTypes {
                if let button = win.standardWindowButton(type) {
                    let localPoint = button.convert(pointInWindow, from: nil) // convert from window coords
                    if button.bounds.contains(localPoint) {
                        return true
                    }
                }
            }
            return false
        }

        NSEvent.addLocalMonitorForEvents(matching: downType, handler: { event in
            // Always allow clicks on the window traffic-light buttons to pass through
            if isInTrafficLightArea(event) {
                return event
            }

            // Detect double-clicks on the title-bar area (respecting system preference)

            if left && event.clickCount == 2, self.hideTitleBarSetting, let win = event.window {
                let contentRect = win.contentLayoutRect
                // Title-bar area is the region above contentLayoutRect
                if event.locationInWindow.y > contentRect.maxY {
                    win.performZoom(nil)
                    return nil
                }
            }

            guard let eventWindow = event.window else {
                return event
            }
            guard let activeWindow = self.activeGameplayWindow(preferred: eventWindow) else {
                return event
            }
            if eventWindow != activeWindow {
                return event
            }
            if consumed(event.buttonNumber, true) {
                return nil
            }
            return event
        })
        NSEvent.addLocalMonitorForEvents(matching: upType, handler: { event in
            // Always allow releases on the traffic-light buttons to pass through
            if isInTrafficLightArea(event) {
                return event
            }
            if consumed(event.buttonNumber, false) {
                return nil
            }
            return event
        })
    }

    func setupScrollWheel(_ onMoved: @escaping (CGFloat, CGFloat) -> Bool) {
        NSEvent.addLocalMonitorForEvents(matching: NSEvent.EventTypeMask.scrollWheel, handler: { event in
            var deltaX = event.scrollingDeltaX, deltaY = event.scrollingDeltaY
            if !event.hasPreciseScrollingDeltas {
                deltaX *= 16
                deltaY *= 16
            }
            let consumed = onMoved(deltaX, deltaY)
            if consumed {
                return nil
            }
            return event
        })
    }

    func urlForApplicationWithBundleIdentifier(_ value: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: value)
    }

    func setMenuBarVisible(_ visible: Bool) {
        NSMenu.setMenuBarVisible(visible)
    }

    /// Convenience instance property that exposes the cached static preference.
    private var hideTitleBarSetting: Bool { Self.akAppSettingsData?.hideTitleBar ?? false }
    private var floatingWindowSetting: Bool { Self.akAppSettingsData?.floatingWindow ?? false }
    private var aspectRatioSetting: NSSize? {
        guard Self.akAppSettingsData?.resolution == 6 else {
            return nil
        }
        let width = Self.akAppSettingsData?.resizableAspectRatioWidth ?? 0
        let height = Self.akAppSettingsData?.resizableAspectRatioHeight ?? 0
        guard width > 0 && height > 0 else {
            return nil
        }
        return NSSize(width: width, height: height)
    }

    fileprivate static var akAppSettingsData: AKAppSettingsData? = {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? ""
        let settingsURL = URL(fileURLWithPath: "/Users/\(NSUserName())/Library/Containers/io.playcover.PlayCover")
            .appendingPathComponent("App Settings")
            .appendingPathComponent("\(bundleIdentifier).plist")
        guard let data = try? Data(contentsOf: settingsURL),
              let decoded = try? PropertyListDecoder().decode(AKAppSettingsData.self, from: data) else {
            return nil
        }
        return decoded
    }()
}
