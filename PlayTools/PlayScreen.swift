//
//  ScreenController.swift
//  PlayTools
//
import Foundation
import UIKit

let screen = PlayScreen.shared
let isInvertFixEnabled = PlaySettings.shared.inverseScreenValues && PlaySettings.shared.adaptiveDisplay
let mainScreenWidth =  !isInvertFixEnabled ? PlaySettings.shared.windowSizeWidth : PlaySettings.shared.windowSizeHeight
let mainScreenHeight = !isInvertFixEnabled ? PlaySettings.shared.windowSizeHeight : PlaySettings.shared.windowSizeWidth
let customScaler = PlaySettings.shared.customScaler

extension CGSize {
    func aspectRatio() -> CGFloat {
        if mainScreenWidth > mainScreenHeight {
            return mainScreenWidth / mainScreenHeight
        } else {
            return mainScreenHeight / mainScreenWidth
        }
    }

    func toAspectRatio() -> CGSize {
        if #available(iOS 16.3, *) {
            return CGSize(width: mainScreenWidth, height: mainScreenHeight)
        } else {
            return CGSize(width: mainScreenHeight, height: mainScreenWidth)
        }
    }

    func toAspectRatioInternal() -> CGSize {
        return CGSize(width: mainScreenHeight, height: mainScreenWidth)
    }
    func toAspectRatioDefault() -> CGSize {
        return CGSize(width: mainScreenHeight, height: mainScreenWidth)
    }
    func toAspectRatioInternalDefault() -> CGSize {
        return CGSize(width: mainScreenWidth, height: mainScreenHeight)
    }
}

extension CGRect {
    func aspectRatio() -> CGFloat {
        if mainScreenWidth > mainScreenHeight {
            return mainScreenWidth / mainScreenHeight
        } else {
            return mainScreenHeight / mainScreenWidth
        }
    }

    func toAspectRatio(_ multiplier: CGFloat = 1) -> CGRect {
        return CGRect(x: minX, y: minY, width: mainScreenWidth * multiplier, height: mainScreenHeight * multiplier)
    }

    func toAspectRatioReversed() -> CGRect {
        return CGRect(x: minX, y: minY, width: mainScreenHeight, height: mainScreenWidth)
    }
    func toAspectRatioDefault(_ multiplier: CGFloat = 1) -> CGRect {
        return CGRect(x: minX, y: minY, width: mainScreenWidth * multiplier, height: mainScreenHeight * multiplier)
    }
    func toAspectRatioReversedDefault() -> CGRect {
        return CGRect(x: minX, y: minY, width: mainScreenHeight, height: mainScreenWidth)
    }
}

extension UIScreen {
    static var aspectRatio: CGFloat {
        let count = AKInterface.shared!.screenCount
        if PlaySettings.shared.notch {
            if count == 1 {
                return mainScreenWidth / mainScreenHeight // 1.6 or 1.77777778
            } else {
                if AKInterface.shared!.isMainScreenEqualToFirst {
                    return mainScreenWidth / mainScreenHeight
                }
            }

        }

        let frame = AKInterface.shared!.mainScreenFrame
        return frame.aspectRatio()
    }
}

public class PlayScreen: NSObject {
    @objc public static let shared = PlayScreen()

    func initialize() {
        let centre = NotificationCenter.default
        let main = OperationQueue.main

        centre.addObserver(forName: UIWindow.didBecomeKeyNotification, object: nil, queue: main) { notification in
            Self.refreshCachedWindow()

            guard self.resizable,
                  let window = notification.object as? UIWindow,
                  let windowScene = window.windowScene else {
                return
            }

            // Remove default size restrictions
            windowScene.sizeRestrictions?.minimumSize = CGSize(width: 0, height: 0)
            windowScene.sizeRestrictions?.maximumSize = CGSize(width: .max, height: .max)
        }

        let cacheRefreshNotifications: [NSNotification.Name] = [
            UIWindow.didResignKeyNotification,
            UIScene.didActivateNotification,
            UIScene.willDeactivateNotification,
            UIApplication.didBecomeActiveNotification,
            UIApplication.willResignActiveNotification
        ]
        for name in cacheRefreshNotifications {
            centre.addObserver(forName: name, object: nil, queue: main) { _ in
                Self.refreshCachedWindow()
            }
        }

        Self.refreshCachedWindow()
    }

    @objc public static func frame(_ rect: CGRect) -> CGRect {
        return rect.toAspectRatioReversed()
    }

    @objc public static func bounds(_ rect: CGRect) -> CGRect {
        return rect.toAspectRatio()
    }

    @objc public static func nativeBounds(_ rect: CGRect) -> CGRect {
        return rect.toAspectRatio(CGFloat((customScaler)))
    }

    @objc public static func width(_ size: Int) -> Int {
        return size
    }

    @objc public static func height(_ size: Int) -> Int {
        return Int(size / Int(UIScreen.aspectRatio))
    }

    @objc public static func sizeAspectRatio(_ size: CGSize) -> CGSize {
        return size.toAspectRatio()
    }

    var fullscreen: Bool {
        return AKInterface.shared!.isFullscreen
    }

    var resizable: Bool {
        return PlaySettings.shared.resizableWindow
    }

    @objc public var screenRect: CGRect {
        return UIScreen.main.bounds
    }

    var width: CGFloat {
        screenRect.width
    }

    var height: CGFloat {
        screenRect.height
    }

    var max: CGFloat {
        Swift.max(width, height)
    }

    var percent: CGFloat {
        max / 100.0
    }

    private var allWindowScenes: [UIWindowScene] {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    }

    private func preferredWindow() -> UIWindow? {
        let sceneGroups = [
            allWindowScenes.filter { $0.activationState == .foregroundActive },
            allWindowScenes.filter { $0.activationState == .foregroundInactive },
            allWindowScenes.filter { $0.activationState == .background },
            allWindowScenes.filter { $0.activationState == .unattached }
        ]

        for scenes in sceneGroups {
            let windows = scenes.flatMap { $0.windows }

            if let keyWindow = windows.first(where: \.isKeyWindow) {
                return keyWindow
            }

            if let visibleWindow = windows.first(where: {
                !$0.isHidden && $0.alpha > 0 && $0.bounds.width > 0 && $0.bounds.height > 0
            }) {
                return visibleWindow
            }
        }

        return nil
    }

    var keyWindow: UIWindow? {
        preferredWindow()
    }

    var windowScene: UIWindowScene? {
        window?.windowScene
    }

    var window: UIWindow? {
        preferredWindow()
    }

    var nsWindow: NSObject? {
        window?.nsWindow
    }

    func switchDock(_ visible: Bool) {
        AKInterface.shared!.setMenuBarVisible(visible)
    }

    // Default calculation
    @objc public static func frameReversedDefault(_ rect: CGRect) -> CGRect {
        return rect.toAspectRatioReversedDefault()
    }
    @objc public static func frameDefault(_ rect: CGRect) -> CGRect {
        return rect.toAspectRatioDefault()
    }
    @objc public static func boundsDefault(_ rect: CGRect) -> CGRect {
        return rect.toAspectRatioDefault()
    }

    @objc public static func nativeBoundsDefault(_ rect: CGRect) -> CGRect {
        return rect.toAspectRatioDefault(CGFloat((customScaler)))
    }

    @objc public static func sizeAspectRatioDefault(_ size: CGSize) -> CGSize {
        return size.toAspectRatioDefault()
    }
    @objc public static func frameInternalDefault(_ rect: CGRect) -> CGRect {
            return rect.toAspectRatioDefault()
    }

    private static weak var cachedWindow: UIWindow?
    private static func refreshCachedWindow() {
        cachedWindow = PlayScreen.shared.preferredWindow()
    }

    @objc public static func boundsResizable(_ rect: CGRect) -> CGRect {
        if let activeWindow = PlayScreen.shared.preferredWindow(),
           activeWindow !== cachedWindow {
            cachedWindow = activeWindow
        } else if cachedWindow == nil {
            refreshCachedWindow()
        }
        return cachedWindow?.bounds ?? rect
    }
}

extension CGFloat {
    var relativeY: CGFloat {
        self / screen.height
    }

    var relativeX: CGFloat {
        self / screen.width
    }

    var relativeSize: CGFloat {
        self / screen.percent
    }

    var absoluteSize: CGFloat {
        self * screen.percent
    }

    var absoluteX: CGFloat {
        self * screen.width
    }

    var absoluteY: CGFloat {
        self * screen.height
    }
}

extension UIWindow {
    var nsWindow: NSObject? {
        guard let nsWindows = NSClassFromString("NSApplication")?
            .value(forKeyPath: "sharedApplication.windows") as? [AnyObject] else { return nil }
        for nsWindow in nsWindows {
            let uiWindows = nsWindow.value(forKeyPath: "uiWindows") as? [UIWindow] ?? []
            if uiWindows.contains(self) {
                return nsWindow as? NSObject
            }
        }
        return nil
    }
}
