//
//  TouchscreenMouseEventAdapter.swift
//  PlayTools
//
//  Created by 许沂聪 on 2023/9/16.
//

import Foundation

// Mouse events handler when cursor is free and keyboard mapping is on

public class TouchscreenMouseEventAdapter: MouseEventAdapter {

    static public func cursorPos() -> CGPoint? {
        // IMPROVE: this is expensive (maybe?)
        let pointInWindow = AKInterface.shared!.mousePoint
        let rect = AKInterface.shared!.windowFrame
        let viewRect: CGRect = screen.screenRect
        guard rect.width >= 1, rect.height >= 1, viewRect.width >= 1, viewRect.height >= 1 else {
            return nil
        }

        var point = pointInWindow
        if screen.resizable && !screen.fullscreen {
            // Allow user to resize window by dragging edges
            let margin = CGFloat(10)
            if point.x < margin || point.x > rect.width - margin ||
                point.y < margin || point.y > rect.height - margin {
                return nil
            }
        }

        // Match the fitted gameplay surface inside the Catalyst content rect, then translate
        // from AppKit bottom-left coordinates into UIKit's top-left coordinates.
        let scale = max(viewRect.width / rect.width, viewRect.height / rect.height)
        let fittedWidth = viewRect.width / scale
        let fittedHeight = viewRect.height / scale
        let insetX = max((rect.width - fittedWidth) / 2, 0)
        let insetY = max((rect.height - fittedHeight) / 2, 0)

        point.x -= insetX
        point.y -= insetY

        if point.x < 0 || point.x > fittedWidth || point.y < 0 || point.y > fittedHeight {
            return nil
        }

        point.x *= scale
        point.y *= scale
        point.y = viewRect.height - point.y

        return CGPoint(
            x: min(max(point.x, 0), viewRect.width.nextDown),
            y: min(max(point.y, 0), viewRect.height.nextDown)
        )
    }

    public func handleScrollWheel(deltaX: CGFloat, deltaY: CGFloat) -> Bool {
        _ = ActionDispatcher.dispatch(key: KeyCodeNames.scrollWheelDrag, valueX: deltaX, valueY: deltaY)
        // I dont know why but this is the logic before the refactor.
        // Might be a mistake but keeping it for now
        return false
    }

    public func handleMove(deltaX: CGFloat, deltaY: CGFloat) -> Bool {
        if ActionDispatcher.getDispatchPriority(key: KeyCodeNames.mouseMove) == .DRAGGABLE {
            // condition meets when draggable button pressed
            return ActionDispatcher.dispatch(key: KeyCodeNames.mouseMove, valueX: deltaX, valueY: -deltaY)
        } else if ActionDispatcher.getDispatchPriority(key: KeyCodeNames.fakeMouse) == .DRAGGABLE {
            // condition meets when mouse pressed and draggable button not pressed
            // fake mouse handler priority:
            // default direction pad: press handler
            // draggable direction pad: move handler
            // default button: lift handler
            // kinda hacky but.. IT WORKS!
            guard let pos = TouchscreenMouseEventAdapter.cursorPos() else { return false }
            return ActionDispatcher.dispatch(key: KeyCodeNames.fakeMouse, valueX: pos.x, valueY: pos.y)

        }
        return false
    }

    public func handleLeftButton(pressed: Bool) -> Bool {
        // It is necessary to calculate pos before pushing to dispatch queue
        // Otherwise, we don't know whether to return false or true
        guard let pos = TouchscreenMouseEventAdapter.cursorPos() else { return false }
        if pressed {
            return ActionDispatcher.dispatch(key: KeyCodeNames.fakeMouse, valueX: pos.x, valueY: pos.y)
        } else {
            return ActionDispatcher.dispatch(key: KeyCodeNames.fakeMouse, pressed: pressed)
        }
    }

    public func handleOtherButton(id: Int, pressed: Bool) -> Bool {
        ActionDispatcher.dispatch(key: EditorMouseEventAdapter.getMouseButtonName(id),
                                  pressed: pressed)
    }

    public func cursorHidden() -> Bool {
        false
    }

}
