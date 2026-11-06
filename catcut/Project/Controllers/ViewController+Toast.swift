// MARK: - Controllers/ViewController+Toast.swift

import UIKit
import AVFoundation
import CoreImage
import CoreMedia
import PhotosUI
import Photos
import UniformTypeIdentifiers
import SnapKit

extension ViewController {

    // MARK: Toast

    func showToast(_ text: String) {
        toastLabel?.removeFromSuperview()
        let l = PaddingLabel()
        l.text = text
        l.numberOfLines = 0
        l.textAlignment = .center
        l.textColor = .white
        l.font = .systemFont(ofSize: 13, weight: .medium)
        l.backgroundColor = UIColor(white: 0.2, alpha: 0.95)
        l.layer.cornerRadius = 14
        l.clipsToBounds = true
        view.addSubview(l)
        l.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalTo(timelineView.snp.top).offset(-8)
            make.leading.greaterThanOrEqualToSuperview().offset(24)
            make.trailing.lessThanOrEqualToSuperview().offset(-24)
        }
        toastLabel = l
        l.alpha = 0
        UIView.animate(withDuration: 0.2, animations: { l.alpha = 1 }) { _ in
            UIView.animate(withDuration: 0.3, delay: 2.0, options: [], animations: { l.alpha = 0 }) { _ in
                l.removeFromSuperview()
            }
        }
    }
}
