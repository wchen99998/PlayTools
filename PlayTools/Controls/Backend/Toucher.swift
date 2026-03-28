//
//  Toucher.swift
//  PlayCoverInject
//

import Foundation
import UIKit

class Toucher {
    static weak var keyWindow: UIWindow?
    static weak var keyView: UIView?
    // For debug only
    static var logEnabled = false
    static var logFilePath =
    NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0] + "/toucher.log"
    static private var logCount = 0
    static var logFile: FileHandle?

    static func resetTargetWindow() {
        keyWindow = nil
        keyView = nil
    }

    private static func beginTarget(for point: CGPoint) -> (window: UIWindow, view: UIView)? {
        guard let window = screen.keyWindow ?? screen.window else {
            return nil
        }
        return (window, window.hitTest(point, with: nil) ?? window)
    }

    private static func currentTarget(for point: CGPoint) -> (window: UIWindow, view: UIView)? {
        guard let window = keyWindow else {
            return nil
        }
        return (window, keyView ?? window.hitTest(point, with: nil) ?? window)
    }
    /**
     on invocations with phase "began", an int id is allocated, which can be used later to refer to this touch point.
     on invocations with phase "ended", id is set to nil representing the touch point is no longer valid.
     */
    static func touchcam(point: CGPoint, phase: UITouch.Phase, tid: inout Int?,
                         // Name info for debug use
                         actionName: String, keyName: String) {
        if phase == UITouch.Phase.began {
            if tid != nil {
                return
            }
            guard let target = beginTarget(for: point) else {
                writeLog(logMessage: "drop began \(actionName)(\(keyName)): missing key window")
                return
            }
            tid = -1
            keyWindow = target.window
            keyView = target.view
        } else if tid == nil {
            return
        }

        guard let target = currentTarget(for: point), let currentID = tid else {
            writeLog(logMessage: "drop \(phase.rawValue) \(actionName)(\(keyName)): missing touch target")
            tid = nil
            resetTargetWindow()
            return
        }

        var recordId = currentID
        let nextTouchID = PTFakeMetaTouch.fakeTouchId(currentID, at: point, with: phase,
                                                      in: target.window, on: target.view)
        tid = nextTouchID
        writeLog(logMessage:
                "\(phase.rawValue.description) \(nextTouchID.description) \(point.debugDescription)")
        if nextTouchID < 0 {
            tid = nil
            resetTargetWindow()
        } else {
            recordId = nextTouchID
            keyWindow = target.window
            keyView = target.view
        }
        DebugModel.instance.record(point: point, phase: phase, tid: recordId,
                                   description: actionName + "(" + keyName + ")")
    }

    static func setupLogfile() {
        if FileManager.default.createFile(atPath: logFilePath, contents: nil, attributes: nil) {
            logFile = FileHandle(forWritingAtPath: logFilePath)
            Toast.showOver(msg: logFilePath)
        } else {
            Toast.showHint(title: "logFile creation failed")
            return
        }
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name(rawValue: "NSApplicationWillTerminateNotification"),
            object: nil,
            queue: OperationQueue.main
        ) { _ in
            try? logFile?.close()
        }
    }

    static func writeLog(logMessage: String) {
        if !logEnabled {
            return
        }
        guard let file = logFile else {
            setupLogfile()
            return
        }
        let message = "\(DispatchTime.now().rawValue) \(logMessage)\n"
        guard let data = message.data(using: .utf8) else {
            Toast.showHint(title: "log message is utf8 uncodable")
            return
        }
        logCount += 1
        // roll over
        if logCount > 60000 {
            file.seek(toFileOffset: 0)
            logCount = 0
        }
        file.write(data)
    }
}
