// MARK: - Views/Components.swift

import UIKit
import AVFoundation
import CoreImage
import CoreMedia
import SnapKit

// =====================================================================
// MARK: - Small UI helpers
// =====================================================================

final class PaddingLabel: UILabel {
    var insets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: insets)) }
    override var intrinsicContentSize: CGSize {
        let s = super.intrinsicContentSize
        return CGSize(width: s.width + insets.left + insets.right, height: s.height + insets.top + insets.bottom)
    }
}

/// Белые «ручки» по краям выбранного элемента — за них тянем, чтобы обрезать/вернуть.
func addTrimHandles(to v: UIView) {
    for left in [true, false] {
        let h = UIView(frame: CGRect(x: left ? 0 : v.bounds.width - 12, y: 0, width: 12, height: v.bounds.height))
        h.backgroundColor = UIColor(white: 0.97, alpha: 1)
        h.autoresizingMask = left ? [.flexibleHeight, .flexibleRightMargin] : [.flexibleHeight, .flexibleLeftMargin]
        h.isUserInteractionEnabled = false
        let grip = UIView(frame: CGRect(x: 4.5, y: max(2, v.bounds.height / 2 - 7), width: 3, height: 14))
        grip.backgroundColor = UIColor(white: 0.25, alpha: 1)
        grip.layer.cornerRadius = 1.5
        grip.autoresizingMask = [.flexibleTopMargin, .flexibleBottomMargin]
        h.addSubview(grip)
        v.addSubview(h)
    }
}
