// MARK: - Controllers/ViewController.swift

import UIKit
import AVFoundation
import CoreImage
import CoreMedia
import PhotosUI
import Photos
import UniformTypeIdentifiers
import SnapKit

// =====================================================================
// MARK: - Main ViewController
// =====================================================================

final class ViewController: UIViewController {

    enum PanelKind { case speed, filter, adjust, transition, animation, effects, frame, background, text, audio }
    enum PickerPurpose { case clips, bgPhoto, audioFromVideo }

    enum TextTab: Int, CaseIterable {
        case text, styles, font, fill, stroke, shadow, shadowColor, glow, box, format, animIn, animOut
        var title: String {
            switch self {
            case .text: return "Текст"
            case .styles: return "Стили"
            case .font: return "Шрифт"
            case .fill: return "Цвет"
            case .stroke: return "Обводка"
            case .shadow: return "Тень"
            case .shadowColor: return "Цвет тени"
            case .glow: return "Свечение"
            case .box: return "Фон"
            case .format: return "Формат"
            case .animIn: return "Появление"
            case .animOut: return "Исчезание"
            }
        }
    }

    struct Snapshot { var clips: [VideoClip]; var texts: [TextOverlay]; var audios: [AudioClip]; var project: ProjectSettings }

    // UI
    let topBar = UIView()
    let playerContainer = UIView()
    let controlBar = UIView()
    let timeLabel = UILabel()
    let playButton = UIButton(type: .system)
    let undoButton = UIButton(type: .system)
    let redoButton = UIButton(type: .system)
    let timelineView = TimelineView()
    let bottomContainer = UIView()
    let panel = EditPanelView()
    let textBox = UIView()
    let emptyLabel = UILabel()
    let loader = UIActivityIndicatorView(style: .large)
    let textInput = TextInputView()
    var toolCollection: UICollectionView!
    var bottomHeightConstraint: NSLayoutConstraint!
    var timelineHeightConstraint: NSLayoutConstraint!
    var playerLayer: AVPlayerLayer!
    var toastLabel: PaddingLabel?
    var exportOverlay: ExportOverlay?

    // State
    var clips: [VideoClip] = []
    var texts: [TextOverlay] = []
    var audios: [AudioClip] = []
    var project = ProjectSettings()
    var focusLane: TimelineLane = .video
    var pickerPurpose: PickerPurpose = .clips
    var selectedClipIndex: Int?
    var selectedTextID: UUID?
    var selectedAudioID: UUID?
    var undoStack: [Snapshot] = []
    var redoStack: [Snapshot] = []
    var currentDraftID: UUID?

    var build: EditorBuild?
    var renderSize = CGSize(width: 1080, height: 1920)
    var displayTime: Double = 0

    let player = AVPlayer()
    var timeObserver: Any?
    var isSeeking = false
    var pendingSeek: CMTime?
    var previewToken = 0

    var activePanel: PanelKind?
    var textTab: TextTab = .text
    var transitionBoundary = 0
    var transitionCategory: TransitionCategory = .all
    var previewPairKey: String?
    var filterPreviews: [Int: UIImage] = [:]
    var filterCategory: FilterCategory = .all
    var adjustTab = 0
    var hslChannel = 0
    var frameTab = 0
    var fxTab = 0
    var audioTab = 0
    var animTab = 0
    var processingKeys = Set<String>()
    var filterPreviewClipID: UUID?
    var textPreviewCache: [String: UIImage] = [:]

    let exporter = VideoExporter()

    let speeds: [Float] = [0.25, 0.5, 1, 1.5, 2, 3, 4]
    let toolBarHeight: CGFloat = 76

    var totalSeconds: Double { build?.layout.total.secs ?? 0 }
    var selectedText: TextOverlay? { texts.first { $0.id == selectedTextID } }
    var selectedAudio: AudioClip? { audios.first { $0.id == selectedAudioID } }

    // Добавить в свойства ViewController:
    var autoSaveTimer: Timer?
    
    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        // Звук должен играть даже при беззвучном режиме
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
        setupLayout()
        setupPlayer()
        setupCallbacks()
        updateUndoRedoButtons()
        updateEmptyState()
        reloadTimeline()
        NotificationCenter.default.addObserver(self, selector: #selector(appWillResign),
                                               name: UIApplication.willResignActiveNotification, object: nil)
        
        if currentDraftID == nil {
            let allDrafts = DraftStore.shared.list()
            if let autoDraft = allDrafts.first(where: { $0.isAutoSaved == true }) {
                loadDraft(autoDraft)
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = playerContainer.bounds
        CATransaction.commit()
        updateTextBox()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startAutoSaveTimer()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopAutoSaveTimer()
        pausePlayback()
        if presentedViewController == nil { saveDraft(silent: true, isAuto: false) }
    }

    func startAutoSaveTimer() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.performAutoSave()
        }
    }

    func stopAutoSaveTimer() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil
    }

    @objc func performAutoSave() {
        guard !clips.isEmpty else { return }
        // Автосейв сохраняем с фиксированным ID для автосохранения или обновляем текущий автосейв
        saveDraft(silent: true, isAuto: true)
    }

    deinit {
        if let t = timeObserver { player.removeTimeObserver(t) }
        NotificationCenter.default.removeObserver(self)
    }

    @objc func appWillResign() {
        saveDraft(silent: true)   // авто-сохранение, чтобы прогресс не терялся
    }

    // MARK: Layout

    func setupLayout() {
        view.backgroundColor = Theme.background
        [topBar, playerContainer, controlBar, timelineView, bottomContainer].forEach { view.addSubview($0) }

        topBar.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(52) // Чуем увеличение высоты для иконки с текстом
        }

        // 1. Создаем эффект стекла (Liquid Glass / Material)
        let blurEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        let glassBackground = UIVisualEffectView(effect: blurEffect)
        glassBackground.isUserInteractionEnabled = false // чтобы тапы проходили сквозь саму подложку на кнопку
        glassBackground.layer.cornerRadius = 20
        glassBackground.clipsToBounds = true
        
        // 2. Сама кнопка меню со стрелочкой
        let menuButton = UIButton(type: .system)
        var menuConfig = UIButton.Configuration.plain()
        menuConfig.image = UIImage(systemName: "chevron.down")
        menuConfig.imagePadding = 0
        menuButton.configuration = menuConfig
        menuButton.tintColor = .white
        
        let saveAction = UIAction(title: "Сохранить", image: UIImage(systemName: "square.and.arrow.down.fill")) { [weak self] _ in
            self?.didTapSaveDraft()
        }
        let draftsAction = UIAction(title: "Черновики", image: UIImage(systemName: "folder.fill")) { [weak self] _ in
            self?.didTapDrafts()
        }
        let newProjectAction = UIAction(title: "Новый проект", image: UIImage(systemName: "plus.circle.fill"), attributes: .destructive) { [weak self] _ in
            self?.newProject()
        }
        
        menuButton.menu = UIMenu(title: "Управление проектом", children: [saveAction, draftsAction, newProjectAction])
        menuButton.showsMenuAsPrimaryAction = true
        
        // 3. Собираем и верстаем через SnapKit
        topBar.addSubview(glassBackground)
        topBar.addSubview(menuButton)
        
        glassBackground.snp.makeConstraints { $0.edges.equalTo(menuButton) }
        
        menuButton.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.centerY.equalToSuperview()
            make.size.equalTo(40)
        }

        // Кнопка Экспорт (сохраняет позицию справа)
        let exportButton = UIButton(type: .system)
        exportButton.setTitle("Экспорт", for: .normal)
        exportButton.titleLabel?.font = .boldSystemFont(ofSize: 14)
        exportButton.setTitleColor(.black, for: .normal)
        exportButton.backgroundColor = .white
        exportButton.layer.cornerRadius = 16
        exportButton.contentEdgeInsets = UIEdgeInsets(top: 7, left: 16, bottom: 7, right: 16)
        exportButton.addTarget(self, action: #selector(didTapExport), for: .touchUpInside)
        topBar.addSubview(exportButton)
        exportButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(16)
            make.centerY.equalToSuperview()
        }

        // Кнопка Отмена (Undo)
        undoButton.setImage(UIImage(systemName: "arrow.uturn.backward"), for: .normal)
        undoButton.tintColor = .white
        undoButton.addTarget(self, action: #selector(didTapUndo), for: .touchUpInside)
        topBar.addSubview(undoButton)
        undoButton.snp.makeConstraints { make in
            make.trailing.equalTo(exportButton.snp.leading).offset(-12)
            make.centerY.equalToSuperview()
            make.size.equalTo(44)
        }

        // Кнопка Повтор (Redo) — стрелка вперед
        redoButton.setImage(UIImage(systemName: "arrow.uturn.forward"), for: .normal)
        redoButton.tintColor = .white
        redoButton.addTarget(self, action: #selector(didTapRedo), for: .touchUpInside)
        topBar.addSubview(redoButton)
        redoButton.snp.makeConstraints { make in
            make.trailing.equalTo(undoButton.snp.leading).offset(-4)
            make.centerY.equalToSuperview()
            make.size.equalTo(44)
        }

        // Player
        playerContainer.backgroundColor = .black
        playerContainer.layer.cornerRadius = 10
        playerContainer.clipsToBounds = true
        playerContainer.snp.makeConstraints { make in
            make.top.equalTo(topBar.snp.bottom).offset(4)
            make.leading.trailing.equalToSuperview().inset(16)
            make.bottom.equalTo(controlBar.snp.top).offset(-2)
        }

        emptyLabel.text = "Нажмите «+» на таймлайне\nили «Добавить», чтобы выбрать видео"
        emptyLabel.numberOfLines = 0
        emptyLabel.textAlignment = .center
        emptyLabel.textColor = .gray
        emptyLabel.font = .systemFont(ofSize: 14)
        playerContainer.addSubview(emptyLabel)
        emptyLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.leading.trailing.equalToSuperview().inset(20)
        }

        textBox.layer.borderColor = UIColor.white.cgColor
        textBox.layer.borderWidth = 1.5
        textBox.layer.cornerRadius = 4
        textBox.isUserInteractionEnabled = false
        textBox.isHidden = true
        playerContainer.addSubview(textBox)

        loader.color = .white
        loader.hidesWhenStopped = true
        playerContainer.addSubview(loader)
        loader.snp.makeConstraints { $0.center.equalToSuperview() }

        let tap = UITapGestureRecognizer(target: self, action: #selector(handlePlayerTap(_:)))
        tap.delegate = self
        playerContainer.addGestureRecognizer(tap)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePlayerPan(_:)))
        pan.delegate = self
        playerContainer.addGestureRecognizer(pan)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePlayerPinch(_:)))
        pinch.delegate = self
        playerContainer.addGestureRecognizer(pinch)
        let rotate = UIRotationGestureRecognizer(target: self, action: #selector(handlePlayerRotate(_:)))
        rotate.delegate = self
        playerContainer.addGestureRecognizer(rotate)

        // Control bar
        controlBar.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(40)
            make.bottom.equalTo(timelineView.snp.top)
        }
        timeLabel.textColor = .lightGray
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        timeLabel.text = "00:00.0 / 00:00.0"
        controlBar.addSubview(timeLabel)
        timeLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.centerY.equalToSuperview()
        }
        playButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        playButton.tintColor = .white
        playButton.addTarget(self, action: #selector(togglePlay), for: .touchUpInside)
        controlBar.addSubview(playButton)
        playButton.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(40)
        }

        // Timeline
        timelineView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(bottomContainer.snp.top)
        }
        timelineHeightConstraint = timelineView.heightAnchor.constraint(equalToConstant: TimelineView.minHeight)
        timelineHeightConstraint.isActive = true

        // Bottom container
        bottomContainer.backgroundColor = Theme.panel
        bottomContainer.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide)
        }
        bottomHeightConstraint = bottomContainer.heightAnchor.constraint(equalToConstant: toolBarHeight)
        bottomHeightConstraint.isActive = true

        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 68, height: 62)
        layout.minimumLineSpacing = 4
        layout.sectionInset = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        toolCollection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        toolCollection.backgroundColor = .clear
        toolCollection.showsHorizontalScrollIndicator = false
        toolCollection.dataSource = self
        toolCollection.delegate = self
        toolCollection.register(ToolCell.self, forCellWithReuseIdentifier: ToolCell.reuseId)
        bottomContainer.addSubview(toolCollection)
        toolCollection.snp.makeConstraints { $0.edges.equalToSuperview() }

        panel.isHidden = true
        bottomContainer.addSubview(panel)
        panel.snp.makeConstraints { $0.edges.equalToSuperview() }
    }

    func setupPlayer() {
        player.actionAtItemEnd = .pause
        playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspect
        playerContainer.layer.insertSublayer(playerLayer, at: 0)

        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] t in
            self?.playerTick(t)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(playerDidFinish),
                                               name: .AVPlayerItemDidPlayToEndTime, object: nil)
    }

    func setupCallbacks() {
        timelineView.onScrubBegan = { [weak self] in
            self?.previewToken += 1
            self?.pausePlayback()
        }
        timelineView.onScrub = { [weak self] seconds in self?.scrub(to: seconds) }
        timelineView.onSelectClip = { [weak self] index in self?.selectClip(index) }
        timelineView.onSelectText = { [weak self] id in self?.selectText(id) }
        timelineView.onSelectAudio = { [weak self] id in self?.selectAudio(id) }
        timelineView.onDeselectAll = { [weak self] in self?.deselectAll() }
        timelineView.onFocusLane = { [weak self] lane in self?.setFocus(lane) }
        timelineView.onTapAdd = { [weak self] in self?.didTapAddVideo() }
        timelineView.onTapTransition = { [weak self] j in
            guard let self = self else { return }
            self.transitionBoundary = j
            self.clearSelection()
            self.selectedClipIndex = j
            self.reloadTimeline()
            self.openPanel(.transition)
        }
        // Фикс 1: Живой предпросмотр кадра в реальном времени при перетягивании края обрезки
        timelineView.onClipTrimming = { [weak self] seconds in
            self?.seekTo(ticks(seconds))
            self?.updateTimeLabel(seconds)
            self?.updateTextBox()
        }
        timelineView.onClipTrimmed = { [weak self] i, range in self?.commitClipTrim(i, range) }
        timelineView.onTextTimeChanged = { [weak self] id, s, d in self?.commitTextTime(id, start: s, duration: d) }
        timelineView.onAudioTimeChanged = { [weak self] id, s, off, d in self?.commitAudioTime(id, start: s, offset: off, duration: d) }
        timelineView.onNeedHeight = { [weak self] h in self?.setTimelineHeight(h) }
        timelineView.onOpenTextEditor = { [weak self] id in
            guard let self = self else { return }
            self.selectedTextID = id
            if let text = self.texts.first(where: { $0.id == id }) {
                self.presentTextInput(editing: text)
            }
        }
        timelineView.onOpenAudioEditor = { [weak self] id in
            guard let self = self else { return }
            self.selectedAudioID = id
            self.focusLane = .audio
            self.audioTab = 0 // или нужный индекс вкладки редактора аудио
            self.openPanel(.audio)
        }
        timelineView.onClipsReordered = { [weak self] newClips in
            guard let self = self else { return }
            self.pushUndo()
            self.clips = newClips
            self.clearSelection()
            self.filterPreviewClipID = nil
            self.rebuild()
        }
        
        panel.onClose = { [weak self] in self?.closePanel() }
        panel.onSelect = { [weak self] index in self?.handlePanelSelect(index) }
        panel.onChip = { [weak self] index in
            guard let self = self else { return }
            switch self.activePanel {
            case .transition?: self.transitionCategory = TransitionCategory.allCases[index]
            case .text?: if let tab = TextTab(rawValue: index) { self.textTab = tab }
            case .filter?: self.filterCategory = FilterCategory.allCases[index]
            case .adjust?: self.adjustTab = index
            case .frame?: self.frameTab = index
            case .effects?: self.fxTab = index
            case .audio?: self.audioTab = index
            case .animation?: self.animTab = index
            default: break
            }
            self.refreshActivePanel(keepScroll: false)
        }
        panel.onExtra = { [weak self] in self?.handlePanelExtra() }
        panel.onFavorite = { [weak self] index in self?.toggleFavorite(index) }
        panel.previewProvider = { [weak self] key, isValid, completion in
            if key.hasPrefix("t") {
                TransitionPreviewStore.shared.image(for: key, isValid: isValid, completion: completion)
            } else if key.hasPrefix("anim-") {
                // Здесь отдаем превью для анимации (например, на основе первого клипа)
                self?.animationPreviewImage(for: key, completion: completion)
            } else {
                completion(nil)
            }
        }
        panel.onSliderChanged = { [weak self] value in
            guard let self = self else { return }
            if self.activePanel == .audio {
                if self.audioTab == 1 {
                    // Громкость
                    self.setAudioParam { v, _, _, _ in v = value }
                } else if self.audioTab == 2 {
                    // Мощность аудиоэффекта
                    self.setAudioIntensity(value)
                } else if self.audioTab == 3 {
                    // Появление (Fade In)
                    self.setAudioParam { _, _, fi, _ in fi = Double(value) }
                } else if self.audioTab == 4 {
                    // Затухание (Fade Out)
                    self.setAudioParam { _, _, _, fo in fo = Double(value) }
                }
            } else {
                self.sliderChanged(value)
            }
        }
        
        ThumbnailStore.shared.onUpdate = { [weak self] in self?.reloadTimelineWhenIdle() }
        WaveformStore.shared.onUpdate = { [weak self] in self?.reloadTimelineWhenIdle() }
    }

    func setAudioIntensity(_ intensity: Float) {
        guard let target = audioTarget() else { return }
        pushUndo()
        switch target {
        case .audio(let i):
            audios[i].effectIntensity = intensity
            audios[i].processed = nil // Сбрасываем кэш для пересчета волны и звука
        case .clip(let i):
            clips[i].audioEffectIntensity = intensity
            clips[i].processedAudio = nil // Сбрасываем кэш
        }
        rebuild()
        refreshActivePanel(keepScroll: true)//Missing argument label 'keepScroll:' in call
    }
    
    func animationPreviewImage(for key: String, completion: @escaping (UIImage?) -> Void) {
        // Извлекаем id анимации из ключа вида "anim-1"
        let components = key.split(separator: "-")
        guard components.count == 2, let animID = Int(components[1]), animID > 0 else {
            completion(nil)
            return
        }
        
        // Берем первый клип для превью анимации появления/затухания
        guard let clip = clips.first else {
            completion(nil)
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let gen = AVAssetImageGenerator(asset: clip.asset)
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 240, height: 240)
            gen.requestedTimeToleranceBefore = .positiveInfinity
            gen.requestedTimeToleranceAfter = .positiveInfinity
            
            let time = clip.sourceRange.start + CMTimeMultiplyByFloat64(clip.sourceRange.duration, multiplier: 0.1)
            let cgImage = try? gen.copyCGImage(at: time, actualTime: nil)
            let image = cgImage.map { UIImage(cgImage: $0) }
            
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }
    
    func setTimelineHeight(_ h: CGFloat) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, abs(self.timelineHeightConstraint.constant - h) > 0.5 else { return }
            self.timelineHeightConstraint.constant = h
            UIView.animate(withDuration: 0.2) { self.view.layoutIfNeeded() }
        }
    }

    // MARK: Player ticks / seeking

    func playerTick(_ t: CMTime) {
        // ИСПРАВЛЕНИЕ: не даем таймеру плеера сбрасывать скролл в 0 во время пересборки/поиска
        guard !isSeeking else { return }
        
        let cur = max(0, min(t.secs, totalSeconds))
        timelineView.setPlayhead(time: cur)
        updateTimeLabel(cur)
        updatePlayButton()
        updateTextBox()
    }

    @objc func playerDidFinish() { updatePlayButton() }

    func scrub(to seconds: Double) {
        previewToken += 1
        let s = max(0, min(seconds, totalSeconds))
        seekTo(ticks(s))
        updateTimeLabel(s)
        updateTextBox()
    }

    /// «Догоняющий» seek: не заваливаем плеер запросами, пока он ещё ищет предыдущий кадр.
    func seekTo(_ time: CMTime) {
        pendingSeek = time
        guard !isSeeking else { return }
        performSeek()
    }

    func performSeek() {
        guard let t = pendingSeek else { return }
        pendingSeek = nil
        isSeeking = true
        player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isSeeking = false
                if self.pendingSeek != nil { self.performSeek() }
            }
        }
    }

    func updateTimeLabel(_ cur: Double) {
        displayTime = cur
        let total = totalSeconds
        timeLabel.text = String(format: "%02d:%04.1f / %02d:%04.1f",
                                Int(cur) / 60, cur.truncatingRemainder(dividingBy: 60),
                                Int(total) / 60, total.truncatingRemainder(dividingBy: 60))
    }

    func updatePlayButton() {
        let name = player.rate > 0 ? "pause.fill" : "play.fill"
        playButton.setImage(UIImage(systemName: name), for: .normal)
    }

    func pausePlayback() {
        player.pause()
        updatePlayButton()
    }

    @objc func togglePlay() {
        guard build != nil else { return }
        previewToken += 1
        if player.rate > 0 { pausePlayback(); return }
        if displayTime >= totalSeconds - 0.05 {
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                DispatchQueue.main.async { self?.player.play(); self?.updatePlayButton() }
            }
        } else {
            player.play()
            updatePlayButton()
        }
    }

    /// Проиграть кусок таймлайна (для предпросмотра перехода / анимации текста).
    func playRange(from: Double, until: Double) {
        previewToken += 1
        let token = previewToken
        player.seek(to: ticks(max(0, from)), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self, token == self.previewToken else { return }
                self.player.play()
                self.updatePlayButton()
                DispatchQueue.main.asyncAfter(deadline: .now() + max(0.2, until - from)) { [weak self] in
                    guard let self = self, token == self.previewToken else { return }
                    self.pausePlayback()
                }
            }
        }
    }

    // MARK: Rebuild engine

    /// Всё, что живёт «под видео», обязано укладываться в длину видео.
    func clampOverlays(total: Double) {
        guard !clips.isEmpty else { texts = []; audios = []; return }
        texts = texts.map { o in
            var o = o
            o.start = max(0, min(o.start, total - 0.3))
            o.duration = max(0.1, min(o.duration, total - o.start))
            return o
        }
        audios = audios.compactMap { a in
            var a = a
            a.start = max(0, min(a.start, total - 0.3))
            let maxDur = min(total - a.start, a.sourceDuration - a.sourceOffset)
            guard maxDur >= 0.1 else { return nil }
            a.duration = min(a.duration, maxDur)
            return a
        }
        if let id = selectedTextID, !texts.contains(where: { $0.id == id }) { selectedTextID = nil }
        if let id = selectedAudioID, !audios.contains(where: { $0.id == id }) { selectedAudioID = nil }
    }

    /// Полная пересборка (меняется структура: клипы, скорость, переходы, звук).
    func rebuild(seekTo target: CMTime? = nil) {
        let activeSecs = player.currentTime().secs > 0 ? player.currentTime().secs : timelineView.currentTime
        let oldTime = target ?? ticks(activeSecs)
        
        previewToken += 1
        isSeeking = true // <-- Взводим флаг, чтобы playerTick молчал при смене item
        pendingSeek = nil
        if let s = selectedClipIndex, s >= clips.count { selectedClipIndex = nil }
        clampOverlays(total: TimelineLayout(clips: clips).total.secs)
        clips.forEach { ThumbnailStore.shared.prepare($0.asset) }
        updateEmptyState()
        
        guard !clips.isEmpty else {
            player.pause()
            player.replaceCurrentItem(with: nil)
            build = nil
            isSeeking = false
            updatePlayButton()
            updateTimeLabel(0)
            reloadTimeline()
            timelineView.setPlayhead(time: 0, force: true)
            updateTextBox()
            return
        }
        
        guard let b = EditorBuild.make(clips: clips, audios: audios, project: project) else {
            showToast("Не удалось собрать видео")
            isSeeking = false
            return
        }
        build = b
        renderSize = b.renderSize
        
        let item = AVPlayerItem(asset: b.composition)
        item.videoComposition = b.makeVideoComposition(clips: clips, texts: texts, project: project)
        item.audioMix = b.audioMix
        item.audioTimePitchAlgorithm = .spectral
        player.pause()
        player.replaceCurrentItem(with: item)
        
        let t = CMTimeMinimum(CMTimeMaximum(oldTime, .zero), b.layout.total)
        player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            DispatchQueue.main.async {
                self?.isSeeking = false // <-- Снимаем флаг только после успешного seek нового айтема
            }
        }
        
        updateTimeLabel(t.secs)
        updatePlayButton()
        reloadTimeline()
        timelineView.setPlayhead(time: t.secs, force: true)
        updateTextBox()
        ensureProcessedAudio()
    }
    
    /// Лёгкое обновление (фильтры, текст): композиция та же, меняем только инструкции.
    func refreshVideoComposition() {
        guard let b = build, let item = player.currentItem else { return }
        item.videoComposition = b.makeVideoComposition(clips: clips, texts: texts, project: project)
        if player.rate == 0 { seekTo(ticks(displayTime)) }
    }

    func reloadTimeline() {
        timelineView.reload(clips: clips,
                            layout: build?.layout ?? TimelineLayout(clips: []),
                            texts: texts,
                            audios: audios,
                            selectedClip: selectedClipIndex,
                            selectedText: selectedTextID,
                            selectedAudio: selectedAudioID,
                            focus: focusLane)
    }

    /// Миниатюры и волны догружаются в фоне — не трогаем ленту, пока человек её крутит.
    func reloadTimelineWhenIdle() {
        if timelineView.isUserScrolling {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.reloadTimelineWhenIdle() }
        } else {
            reloadTimeline()
        }
    }

    func updateEmptyState() {
        emptyLabel.isHidden = !clips.isEmpty
    }

    // MARK: - Undo / Redo

    func pushUndo() {
        undoStack.append(Snapshot(clips: clips, texts: texts, audios: audios, project: project))
        if undoStack.count > 50 { undoStack.removeFirst() }
        
        // Новое действие прерывает цепочку redo
        redoStack.removeAll()
        updateUndoRedoButtons()
    }

    func updateUndoRedoButtons() {
        undoButton.alpha = undoStack.isEmpty ? 0.35 : 1
        undoButton.isEnabled = !undoStack.isEmpty
        
        redoButton.alpha = redoStack.isEmpty ? 0.35 : 1
        redoButton.isEnabled = !redoStack.isEmpty
    }

    @objc func didTapUndo() {
        guard let s = undoStack.popLast() else { showToast("Нечего отменять"); return }
        // Текущее состояние отправляем в стек redo перед откатом
        redoStack.append(Snapshot(clips: clips, texts: texts, audios: audios, project: project))
        
        clips = s.clips
        texts = s.texts
        audios = s.audios
        project = s.project
        clearSelection()
        filterPreviewClipID = nil
        rebuild()
        refreshActivePanel()
        updateUndoRedoButtons()
    }

    @objc func didTapRedo() {
        guard let s = redoStack.popLast() else { showToast("Нечего возвращать"); return }
        // Текущее состояние отправляем обратно в стек undo
        undoStack.append(Snapshot(clips: clips, texts: texts, audios: audios, project: project))
        
        clips = s.clips
        texts = s.texts
        audios = s.audios
        project = s.project
        clearSelection()
        filterPreviewClipID = nil
        rebuild()
        refreshActivePanel()
        updateUndoRedoButtons()
    }

    // MARK: Selection

    func clearSelection() {
        selectedClipIndex = nil
        selectedTextID = nil
        selectedAudioID = nil
    }

    func currentClipIndex() -> Int? {
        if let i = selectedClipIndex, i < clips.count { return i }
        return build?.layout.index(at: ticks(displayTime))
    }

    func selectClip(_ index: Int) {
        clearSelection()
        focusLane = .video
        selectedClipIndex = index
        if clips.count > 1 { transitionBoundary = min(index, clips.count - 2) }
        reloadTimeline()
        updateTextBox()
        refreshActivePanel()
    }

    func selectText(_ id: UUID) {
        guard let o = texts.first(where: { $0.id == id }) else { return }
        clearSelection()
        focusLane = .text
        selectedTextID = id
        if displayTime < o.start || displayTime >= o.start + o.duration {
            let s = min(o.start + 0.01, totalSeconds)
            seekTo(ticks(s))
            updateTimeLabel(s)
            timelineView.setPlayhead(time: s, force: true)
        }
        reloadTimeline()
        updateTextBox()
        refreshActivePanel()
    }

    func selectAudio(_ id: UUID) {
        guard audios.contains(where: { $0.id == id }) else { return }
        clearSelection()
        focusLane = .audio
        selectedAudioID = id
        reloadTimeline()
        updateTextBox()
        refreshActivePanel()
    }

    func setFocus(_ lane: TimelineLane) {
        let keepSelection: Bool
        switch lane {
        case .video: keepSelection = selectedClipIndex != nil
        case .text: keepSelection = selectedTextID != nil
        case .audio: keepSelection = selectedAudioID != nil
        }
        if !keepSelection { clearSelection() }
        focusLane = lane
        reloadTimeline()
        updateTextBox()
        refreshActivePanel()
    }

    func deselectAll() {
        clearSelection()
        reloadTimeline()
        updateTextBox()
        refreshActivePanel()
    }

    func ensureSelection() {
        if selectedClipIndex == nil, selectedTextID == nil, selectedAudioID == nil, let i = currentClipIndex() {
            selectedClipIndex = i
            if clips.count > 1 { transitionBoundary = min(i, clips.count - 2) }
            reloadTimeline()
        }
    }
}
