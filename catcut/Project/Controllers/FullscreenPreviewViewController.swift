// MARK: - Controllers/FullscreenPreviewViewController.swift

import UIKit
import AVFoundation
import SnapKit

/// Полноэкранный просмотр. Использует тот же AVPlayer, что и редактор,
/// поэтому фильтры, текст, оверлеи и звук выглядят ровно как в превью.
/// Свернуть: кнопка «Свернуть» сверху, свайп вниз.
final class FullscreenPreviewViewController: UIViewController, UIGestureRecognizerDelegate {

    private let player: AVPlayer
    private let playerLayer: AVPlayerLayer
    private let controls = UIView()
    private let topShade = UIView()
    private let bottomShade = UIView()
    private let collapseButton = UIButton(type: .system)
    private let playButton = UIButton(type: .system)
    private let slider = UISlider()
    private let timeLabel = UILabel()
    private var observer: Any?
    private var scrubbing = false
    private var wasPlayingBeforeScrub = false

    init(player: AVPlayer) {
        self.player = player
        self.playerLayer = AVPlayerLayer(player: player)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var prefersStatusBarHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .allButUpsideDown }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        playerLayer.videoGravity = .resizeAspect
        view.layer.addSublayer(playerLayer)

        view.addSubview(controls)
        controls.snp.makeConstraints { $0.edges.equalToSuperview() }

        [topShade, bottomShade].forEach {
            $0.backgroundColor = UIColor.black.withAlphaComponent(0.45)
            $0.isUserInteractionEnabled = false
            controls.addSubview($0)
        }
        topShade.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.top).offset(72)
        }
        bottomShade.snp.makeConstraints { make in
            make.bottom.leading.trailing.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide.snp.bottom).offset(-96)
        }

        // Свернуть
        var cfg = UIButton.Configuration.filled()
        cfg.title = "Свернуть"
        cfg.image = UIImage(systemName: "arrow.down.right.and.arrow.up.left",
                            withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold))
        cfg.imagePadding = 8
        cfg.cornerStyle = .capsule
        cfg.baseBackgroundColor = UIColor(white: 1, alpha: 0.22)
        cfg.baseForegroundColor = .white
        cfg.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 18)
        cfg.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { c in
            var c = c; c.font = .systemFont(ofSize: 17, weight: .semibold); return c
        }
        collapseButton.configuration = cfg
        collapseButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        controls.addSubview(collapseButton)
        collapseButton.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(12)
            make.trailing.equalTo(view.safeAreaLayoutGuide).inset(16)
            make.height.equalTo(44)
        }

        // Низ: play + слайдер + время
        playButton.tintColor = .white
        playButton.addTarget(self, action: #selector(togglePlay), for: .touchUpInside)
        controls.addSubview(playButton)
        playButton.snp.makeConstraints { make in
            make.leading.equalTo(view.safeAreaLayoutGuide).offset(12)
            make.bottom.equalTo(view.safeAreaLayoutGuide).inset(18)
            make.size.equalTo(56)
        }

        timeLabel.textColor = .white
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .medium)
        timeLabel.textAlignment = .right
        timeLabel.text = "00:00 / 00:00"
        controls.addSubview(timeLabel)
        timeLabel.snp.makeConstraints { make in
            make.trailing.equalTo(view.safeAreaLayoutGuide).inset(16)
            make.centerY.equalTo(playButton)
            make.width.equalTo(104)
        }

        slider.minimumTrackTintColor = Theme.accent
        slider.addTarget(self, action: #selector(scrubStart), for: .touchDown)
        slider.addTarget(self, action: #selector(scrubMove), for: .valueChanged)
        slider.addTarget(self, action: #selector(scrubEnd), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        controls.addSubview(slider)
        slider.snp.makeConstraints { make in
            make.leading.equalTo(playButton.snp.trailing).offset(6)
            make.trailing.equalTo(timeLabel.snp.leading).offset(-10)
            make.centerY.equalTo(playButton)
        }

        // Тап — показать/скрыть управление, свайп вниз — свернуть
        let tap = UITapGestureRecognizer(target: self, action: #selector(toggleControls))
        tap.delegate = self
        view.addGestureRecognizer(tap)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        view.addGestureRecognizer(pan)

        observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] t in
            self?.tick(t.secs)
        }
        tick(player.currentTime().secs)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = view.bounds
        CATransaction.commit()
    }

    deinit { if let o = observer { player.removeTimeObserver(o) } }

    // MARK: Helpers

    private var duration: Double {
        max(player.currentItem?.duration.secs ?? 0, 0.1)
    }

    private func fmt(_ s: Double) -> String {
        String(format: "%02d:%02d", Int(s) / 60, Int(s) % 60)
    }

    private func tick(_ t: Double) {
        let d = duration
        timeLabel.text = "\(fmt(t)) / \(fmt(d))"
        if !scrubbing {
            slider.maximumValue = Float(d)
            slider.value = Float(min(t, d))
        }
        updatePlay()
    }

    private func updatePlay() {
        let name = player.rate > 0 ? "pause.fill" : "play.fill"
        playButton.setImage(UIImage(systemName: name,
                                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 30, weight: .medium)), for: .normal)
    }

    // MARK: Actions

    @objc private func togglePlay() {
        if player.rate > 0 {
            player.pause()
        } else {
            if player.currentTime().secs >= duration - 0.05 { player.seek(to: .zero) }
            player.play()
        }
        updatePlay()
    }

    @objc private func toggleControls() {
        let show = controls.alpha < 0.5
        UIView.animate(withDuration: 0.2) { self.controls.alpha = show ? 1 : 0 }
    }

    @objc private func scrubStart() {
        scrubbing = true
        wasPlayingBeforeScrub = player.rate > 0
        player.pause()
    }

    @objc private func scrubMove() {
        let t = Double(slider.value)
        timeLabel.text = "\(fmt(t)) / \(fmt(duration))"
        player.seek(to: ticks(t), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    @objc private func scrubEnd() {
        scrubbing = false
        if wasPlayingBeforeScrub { player.play() }
        updatePlay()
    }

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        let ty = max(0, g.translation(in: view).y)
        switch g.state {
        case .changed:
            view.transform = CGAffineTransform(translationX: 0, y: ty)
            view.alpha = 1 - min(0.5, ty / 600)
        case .ended, .cancelled:
            if ty > 120 || g.velocity(in: view).y > 900 {
                close()
            } else {
                UIView.animate(withDuration: 0.2) {
                    self.view.transform = .identity
                    self.view.alpha = 1
                }
            }
        default: break
        }
    }

    @objc private func close() {
        player.pause()
        dismiss(animated: true)
    }

    // Тапы по кнопкам/слайдеру не должны считаться тапом по видео
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !(touch.view is UIControl)
    }
}
