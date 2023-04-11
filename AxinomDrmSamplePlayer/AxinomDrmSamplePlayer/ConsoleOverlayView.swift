//
//  Copyright © 2023 Axinom. All rights reserved.
//
//  Custom view for Console Overlay that allows player buttons to be clicked under it.

import UIKit


class ConsoleOverlayView: UIView {

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        for subview in subviews {
            if !subview.isHidden && subview.isUserInteractionEnabled && subview.point(inside: convert(point, to: subview), with: event) {
                return true
            }
        }
        return false
    }

}
