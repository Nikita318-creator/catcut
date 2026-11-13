// MARK: - Controllers/ViewController+Delegates.swift

import UIKit
import AVFoundation
import CoreImage
import CoreMedia
import PhotosUI
import Photos
import UniformTypeIdentifiers
import SnapKit

// MARK: - Delegates

extension ViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        EditorTool.allCases.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ToolCell.reuseId, for: indexPath) as? ToolCell else {
            return UICollectionViewCell()
        }
        cell.configure(EditorTool.allCases[indexPath.item])
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        handleTool(EditorTool.allCases[indexPath.item])
    }
}

extension ViewController: UIGestureRecognizerDelegate {
    func isTransformGesture(_ g: UIGestureRecognizer) -> Bool {
        g is UIPanGestureRecognizer || g is UIPinchGestureRecognizer || g is UIRotationGestureRecognizer
    }

    func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        if overlayGestures.contains(where: { $0 === g }) { return overlayGestureShouldBegin(g) }
        if isTransformGesture(g) { return selectedText != nil }
        return true
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        isTransformGesture(g) && isTransformGesture(other)
    }
}

extension ViewController: PHPickerViewControllerDelegate, UIDocumentPickerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        let purpose = pickerPurpose
        pickerPurpose = .clips
        switch purpose {
        case .clips: importVideos(results)
        case .bgPhoto: loadBackgroundPhoto(results)
        case .audioFromVideo: extractAudio(results)
        case .overlay: importOverlayVideo(results)
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        guard let file = DraftStore.shared.importMedia(from: url, defaultExt: "m4a") else {
            showToast("Не удалось загрузить аудио")
            return
        }
        addAudio(importedFile: file, title: url.deletingPathExtension().lastPathComponent)
    }
}
