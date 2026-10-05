// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import IOKit.ps
import SwiftUI

struct NotchNotice: Equatable {
    let event: NotchEvent
    let title: String
    let detail: String
    let symbol: String
    var level: Double? = nil
    var notification: NotchNotificationContent? = nil
    var notificationID: UUID? = nil
    /// The agent an AI notice is about, which tints its mark.
    var agent: AgentProvider? = nil
    /// With the companion on, it takes the symbol's place in the notice and
    /// plays this, so the notice itself is its reaction.
    var mascot: NotchMascotReaction? = nil
    /// A banner that replaces one still on screen keeps at least its wings,
    /// so a burst of messages does not resize the island with each one.
    var minimumWings = NotchNoticeWings.zero

    /// Each side as wide as what it shows, so neither ends in a band of
    /// empty black: the island reaches further toward its wider side.
    var preferredWings: NotchNoticeWings { preferredWings(wrapsMessage: false) }

    /// The sides this notice takes beside a camera, as its strip draws them.
    func wings(in geometry: NotchGeometry) -> NotchNoticeWings {
        geometry.noticeWings(preferredWings(
            wrapsMessage: NotchNotificationBannerLayout.messageLines(stripHeight: geometry.stripHeight) > 1))
    }

    func preferredWings(wrapsMessage: Bool) -> NotchNoticeWings {
        if let notification {
            let fitted = NotchNotificationBannerLayout.wings(for: notification, wrapsMessage: wrapsMessage)
            return NotchNoticeWings(leading: max(minimumWings.leading, fitted.leading),
                                    trailing: max(minimumWings.trailing, fitted.trailing))
        }
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let leading = ((level == nil ? title : detail) as NSString).size(withAttributes: [.font: font]).width
        // A level's wings are as wide as its mark and its reading; the meter
        // takes the same width on the other side.
        if level != nil, event != .accessory {
            let wing = ceil(Self.levelInset + 18 + 8 + leading)
            return NotchNoticeWings(leading: wing, trailing: wing)
        }
        // Long accessory names still use bounded truncation.
        let maximum: CGFloat = event == .accessory && level == nil ? 160 : 240
        func fitted(_ content: CGFloat) -> CGFloat { min(maximum, max(Self.minimumWing, ceil(content) + 16 + cameraGap)) }
        // An empty title leaves the mark alone, without the space after it.
        let mark = fitted(leading > 0 ? leading + 18 + 8 : 18)
        guard level == nil else { return NotchNoticeWings(leading: mark, trailing: mark) }
        return NotchNoticeWings(leading: mark, trailing: fitted((detail as NSString).size(withAttributes: [.font: font]).width))
    }

    /// The wider side, for what still takes one width for both.
    var preferredWingWidth: CGFloat { preferredWings.widest }

    /// The narrowest side a text notice keeps: its curved end and some air.
    static let minimumWing: CGFloat = 36

    /// Room a level keeps inside its curved ends, as wide as its wings had
    /// when they were a fixed 80 pt.
    static let levelInset: CGFloat = 13

    /// Two lines of text sit at the island's two ends, each as far from its
    /// curved edge, so a short one leaves its spare room beside the camera
    /// rather than at one end. Levels and banners keep their own layout.
    var readsFromEnds: Bool { level == nil && notification == nil }

    /// Room text keeps from the camera; battery labels need breathing room
    /// at both the curved edge and the camera.
    var cameraGap: CGFloat { event == .battery ? 16 : readsFromEnds ? 6 : 0 }

    var accessibilityText: String {
        notification?.accessibilityText ?? [title, detail].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// Room a closed notice keeps inside its curved ends, which a side as
    /// narrow as its content still clears; only a display too narrow for a
    /// side's content takes some of it.
    func inset(wing: CGFloat) -> CGFloat {
        level != nil && event != .accessory ? Self.levelInset : min(NotchNotificationBannerLayout.inset, wing / 2)
    }

    /// Where the companion stands in this notice, as an offset of its centre
    /// from the camera's: at the leading end, past the inset, since a notice
    /// that carries it reads from the ends.
    func mascotOffset(in geometry: NotchGeometry) -> CGFloat {
        let wing = wings(in: geometry).leading
        return -(geometry.noticeCameraGap / 2 + wing) + inset(wing: wing) + NotchMascotSupport.noticeSize / 2
    }

    func previewContentHeight(width: CGFloat) -> CGFloat {
        guard let notification else { return 0 }
        return NotchNotificationPreviewLayout.contentHeight(for: notification, width: width)
    }
}

/// Owns presentation only. Clipboard, files, captures, audio and metrics keep
/// their original owners, gates and privacy rules.
final class NotchService: ObservableObject {
    static let shared = NotchService()
    static let fullscreenVisibilityDidChange = Notification.Name("NotchFullscreenVisibilityDidChange")

    @Published private(set) var geometry = NotchGeometry(
        screen: CGRect(x: 0, y: 0, width: 1440, height: 900), safeAreaTop: 0, cameraWidth: 0)
    @Published private(set) var expanded = false
    @Published private(set) var peeking = false
    @Published private(set) var dragPlaceholder = false
    @Published private(set) var choosingFileDropDestination = false
    @Published private(set) var targetsMediaDrop = false
    @Published private(set) var selectedMetric: MetricDetailKind?
    @Published private(set) var captureControls: ScreenCaptureSelectionOptions?
    @Published private(set) var captureControlsCollapsed = false
    @Published private(set) var captureSelectionInProgress = false
    @Published var pinned = false
    @Published private(set) var selected: NotchModule = .controls
    @Published private(set) var showingAppPanel = false
    @Published private(set) var showingSections = false
    @Published private(set) var sectionQuery = ""
    @Published var highlightedSection: NotchModule? { didSet { revealHighlightedSection() } }
    /// The gallery's first visible row; the rows above it have stepped away.
    @Published private(set) var sectionRow = 0
    @Published private(set) var modules: [NotchModule] = []
    @Published private(set) var notice: NotchNotice?
    @Published private(set) var noticeExpanded = false
    /// A compact notice stays drawn while the island closes around it.
    @Published private(set) var departingNotice: NotchNotice?
    @Published private(set) var departingMusic: NotchCompactMusicSnapshot?
    /// The compact track on screen when a new song arrives, kept while the
    /// song's notice waits for playback to settle, so the notice rather than
    /// the strip is where the new song first appears.
    @Published private(set) var heldMusic: NotchCompactMusicSnapshot?
    @Published private(set) var captureActions: AnyView?
    @Published private(set) var captureContent: AnyView?
    /// Bumped when Command-W asks the Scratchpad page to close its selected
    /// pad, so the confirmation stays in the page as it does in the floating pad.
    @Published private(set) var scratchpadCloseSerial = 0
    /// Find runs against the island's own text view, which the page holds;
    /// the key arrives here, so it is passed on the way Command-W already is.
    @Published private(set) var scratchpadFindSerial = 0
    private(set) var scratchpadFindAction = NSTextFinder.Action.showFindInterface
    /// The last ⌘1–⌘9 pressed on the Clipboard page, which the page turns
    /// into a paste of the entry at that place.
    @Published private(set) var clipboardPastePress: NotchClipboardPastePress?
    /// Whether the island panel holds the keyboard. Opened by hover, or left
    /// open while another app is active, it does not, and its shortcuts then
    /// reach the app in front instead.
    @Published private(set) var panelIsKey = false
    @Published private var captureContentHeight: CGFloat?
    /// Kept after closing, so the next Fan Control detail opens at its size.
    @Published private var fanDetailHeight: CGFloat?
    @Published private(set) var power = PowerReading()
    @Published private var musicDetailVisible = false

    private var windowHost: NotchWindowHost?
    private var panel: NotchPanel? { windowHost?.panel }
    private var captureControlsCancel: (() -> Void)?
    private var captureControlsSubscription: AnyCancellable?
    private var captureControlsWork: DispatchWorkItem?
    private var heldDrag = false
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var subscriptions = Set<AnyCancellable>()
    private var eventMonitors: [Any] = []
    private var screenEdgeClickMonitors: [Any] = []
    private var screenEdgePressArea: CGRect?
    private var captureControlsMonitors: [Any] = []
    private var hiddenHoverMonitors: [Any] = []
    private var hoverExitMonitors: [Any] = []
    private var hoverWork: DispatchWorkItem?
    /// Set by a notice that replaces one of its own kind, for the refresh it
    /// triggers, so the island eases to the new width rather than springing.
    private var noticeFitsInPlace = false
    private var noticeWork: DispatchWorkItem?
    private var departureWork: DispatchWorkItem?
    private var musicDepartureWork: DispatchWorkItem?
    private var presentedMusic: NotchCompactMusicSnapshot?
    private var trackWork: DispatchWorkItem?
    /// A new song with no strip song to keep in its place stays out of the
    /// closed island until its notice, as scheduleTrackNotice() explains.
    private var awaitsTrackNotice = false
    private var powerSource: CFRunLoopSource?
    private var powerSampler: PowerSampler?
    private var captureID: UUID?
    private var captureFallback: (() -> Void)?
    private var captureClose: (() -> Void)?
    private var captureHover: ((Bool) -> Void)?
    private var captureClosesOnCollapse = false
    private var inside = false
    private var hoverEmphasized = false
    private var activitySelection = NotchActivitySelection()
    private var activityPickerMenuOpen = false
    private var hoverState = NotchHoverState()
    private var openedByHover = false
    /// A click inside the open island, which may be what brings another app forward.
    private var clickedSinceOpening = false
    /// Whether the open detail was reached from inside the island, so Escape
    /// steps back to its page as the Back button does. A detail the island
    /// opened on, from the menu bar for instance, has nothing behind it and
    /// closes like the menu panel.
    private var detailHasPage = false
    /// What a page shows over its own content, such as the mixer's options or
    /// the month grid, and how to close it; Escape closes it before the page.
    private var pageLayers: [NotchModule: () -> Void] = [:]
    private var trackingMenu = false
    private var fileInteractionActive = false
    /// A section's title follows the sections button unless the same action
    /// floats beside the island. Read with the floating buttons rather than on
    /// every layout pass, which would decode them each time.
    private var headerShowsSectionsButton = false
    private var keepsWorkingSurface: Bool {
        pinned || trackingMenu || NSApp.modalWindow != nil || panel?.attachedSheet != nil
            || NotchLyricsService.shared.isImporting
            // Like the lyrics chooser, these panels stand beside the island
            // instead of hanging from it; a click in them is not a click away.
            || (expanded && MediaWorkspaceView.panelModalActive)
            || (expanded && selected == .downloads && NotchDownloadService.shared.isChoosingFolder)
            || (expanded && selected == .scratchpad && ScratchpadService.shared.modalInteractionActive)
            || (expanded && !showingSections && selected == .calendar && Permissions.shared.keepsCalendarPrompt)
            || (expanded && !showingSections && selected == .files && fileInteractionActive)
            || CameraPreviewService.shared.keepsNotchPermissionPrompt
            || (expanded && !showingSections && selected == .captures && captureContent != nil)
            || (expanded && !showingSections && selected == .tools && (QuickLauncherService.shared.activeUtility != nil || QuickLauncherService.shared.isEditing))
    }
    /// Up and measuring its display. Settings previews read the island's
    /// size only then.
    private(set) var running = false
    private var session = NotchSessionState()
    private var suspended: Bool { !session.canPresent }
    @Published private(set) var hiddenInFullscreen = false {
        didSet {
            guard hiddenInFullscreen != oldValue else { return }
            NotificationCenter.default.post(name: Self.fullscreenVisibilityDidChange, object: self,
                                            userInfo: ["hidden": hiddenInFullscreen])
        }
    }
    private var settingsSignature = ""
    private var gesture = NotchGestureSupport()
    private var sectionScroll = NotchSectionScroll()
    private var volumeBaseline: Double?
    private var muteBaseline: Bool?
    private var volumeDeviceUID: String?
    /// System uptime until which an output change counts as the island's own.
    private var ownVolumeAdjustmentUntil: TimeInterval = 0
    private var notchNeedsMonitor = false
    private var menuSpaceTimer: Timer?
    private var menuSpaceReading = false
    private var menuSpaceGeneration = 0
    private var menuBarMeasurements = NotchMenuBarMeasurements()
    private var screenRefreshWork: DispatchWorkItem?
    private var preferenceSyncWork: DispatchWorkItem?
    private let menuSpaceQueue = DispatchQueue(label: "com.vorssaint.notch-menu-space", qos: .utility)
    /// The display the island is on. The pointer choice keeps it there until
    /// the island rests, so a preference sync never moves an open island.
    private var displayID: CGDirectDisplayID?
    private var followsPointer = false
    /// Every other display shows a copy of the closed island.
    private var showsOnAllDisplays = false
    /// A capsule names a song only for a moment as it starts.
    @Published private(set) var capsuleMusicTitleShown = false
    /// The companion's stroll through the closed island, or its moment out
    /// over what the island shows.
    @Published private(set) var mascotVisit: NotchMascotVisit?
    /// What the island shows steps aside while the companion is out over it,
    /// and comes back as a cameo heads home behind the camera.
    @Published private(set) var mascotStepsAside = false
    private var mascotStepBackWork: DispatchWorkItem?
    private var mascotVisitWork: DispatchWorkItem?
    private var nextMascotVisitWork: DispatchWorkItem?
    /// Visits were on at the last preference sync, so turning them on is greeted.
    private var mascotVisitsWereOn = false
    /// How often it visited as of the last preference sync.
    private var mascotFrequencyAtSync: NotchMascotVisitFrequency?
    /// Whether the companion was on at the last preference sync, nil before the first.
    private var mascotWasEnabled: Bool?
    /// The side it rested on at the last preference sync, nil before the first.
    private var mascotSideAtSync: NotchMascotSide?
    /// The last reaction published for the companion to play where it rests.
    @Published private(set) var mascotReaction: NotchMascotReactionEvent?
    /// A reaction waiting for the companion to show, until its deadline, and
    /// not before its time when it was asked to wait.
    private var pendingMascotReaction: (reaction: NotchMascotReaction, deadline: CFTimeInterval,
                                        notBefore: CFTimeInterval)?
    private var mascotReactionFlushWork: DispatchWorkItem?
    private var mascotReactionGate = NotchMascotReactionGate()
    /// When music last brought it out, on the media clock.
    private var lastMascotGroove: CFTimeInterval = -.infinity
    /// Whether Keep Awake held the Mac up when the companion last looked,
    /// nil before it first did.
    private var mascotSawKeepAwake: Bool?
    /// Whether an AI agent was at work when the companion last looked, nil
    /// before it first did, and when it last handed the island to one.
    private var mascotSawAgents: Bool?
    /// The calendar countdown the island showed when the companion last looked.
    private var mascotSawCountdown: NotchCalendarCountdown?
    private var lastMascotAgentStart: CFTimeInterval = -.infinity
    /// The companion is out in the Command Bar's drop, and the island rests without it.
    @Published private(set) var mascotInBar = false
    /// The companion stands in the window's own layer while the island opens
    /// or closes around it, and the strip and the page leave theirs out.
    @Published private(set) var mascotBridging = false
    private var mascotBridgeWork: DispatchWorkItem?
    /// Where the stand-in is headed: the island at rest, the open island or a notice.
    private enum MascotBridgeTarget: Equatable { case rest, resident, notice(NotchNotice) }
    private var mascotBridgeTarget: MascotBridgeTarget?
    /// How high the stand-in hops for a reaction, as the strip it stands for does.
    private var mascotBridgeLift: CGFloat = 0
    /// The closed island showed the companion at rest as of the last refresh.
    /// Activities arrive on live state before the next one runs, so the
    /// island can still tell the companion was there and crossfade from it.
    private(set) var mascotRestedInView = false {
        didSet {
            if oldValue, !mascotRestedInView { mascotLeftRest = CACurrentMediaTime() }
            if !oldValue, mascotRestedInView {
                mascotBackAtRest = CACurrentMediaTime()
                mascotReturnedToRest()
                // A reaction asked for as it came back waits for it to show.
                if pendingMascotReaction != nil { flushMascotReaction() }
            }
        }
    }
    private var mascotLeftRest: CFTimeInterval = -.infinity
    /// When the island last drew it back at rest, crossfading in.
    private var mascotBackAtRest: CFTimeInterval = -.infinity
    /// At rest in view as of the last refresh, or until a moment ago, since
    /// another refresh can run between an activity arriving and the island
    /// drawing it: what arrives crossfades from the companion, and a reaction
    /// asked for with it plays where the companion stood.
    var mascotJustRested: Bool { mascotRestedInView || CACurrentMediaTime() - mascotLeftRest < 0.35 }

    /// It stays where it rested to react as an activity takes its place.
    var mascotLingers: Bool {
        if case .linger = mascotVisit?.kind { return true }
        return false
    }
    /// The Command Bar open inside the island, in place of its pages.
    @Published private(set) var showingCommandBar = false
    @Published private var commandBarHeight: CGFloat?
    private var musicTitleWork: DispatchWorkItem?
    private static let musicTitleDuration: TimeInterval = 4
    private var mirrors: [CGDirectDisplayID: NotchMirror] = [:]
    /// Displays showing a full-screen Space, read as Spaces change.
    private var fullscreenDisplays: Set<CGDirectDisplayID> = []
    private var pointerMonitors: [Any] = []
    private var pointerFollowWork: DispatchWorkItem?
    /// How long the pointer stays on another display before the island
    /// follows, so passing over a display edge does not move it.
    private static let pointerFollowDelay: TimeInterval = 0.2

    private init() {}

    private var hiddenUntilHover: Bool {
        !hiddenInFullscreen && UserDefaults.standard.bool(forKey: DefaultsKey.notchHideUntilHover)
            && UserDefaults.standard.bool(forKey: DefaultsKey.notchOpenOnHover)
            && !expanded && !peeking && !dragPlaceholder && captureControls == nil
    }

    /// Full screen keeps a clickable black cutout until the user opens it.
    var fullscreenCompact: Bool {
        hiddenInFullscreen && !expanded && !peeking
    }

    /// A simulated cutout covers no camera, so in full screen it stays out
    /// of the picture until a shortcut opens it.
    private var hiddenAtRestInFullscreen: Bool {
        fullscreenCompact && !geometry.isNotched
    }

    /// A Mac without a battery has no charge to show, so a saved battery
    /// choice rests empty there; playing music still shows as before.
    var idleContent: NotchIdleContent {
        let content = NotchSupport.visibleIdleContent(isPlaying: !awaitsTrackNotice && NotchMusicService.shared.playback?.isPlaying == true)
        return content == .battery && !PowerSampler.hasInternalBattery ? .none : content
    }

    /// The companion as the island last synced its preferences. The views
    /// read this rather than the live preference, so switching it off takes
    /// it away only once its farewell is set up, with no frame between where
    /// it is simply gone.
    var mascotOn: Bool { mascotWasEnabled ?? false }

    /// The camera side it rests on, as the island last synced it, so a side
    /// changed in Settings moves it only together with the stroll across.
    var mascotSide: NotchMascotSide { mascotSideAtSync ?? NotchMascotSupport.side() }

    /// The companion rests in the closed island when nothing else is there.
    var mascotAtRest: Bool { mascotOn && idleContent == .none && !mascotInBar }

    /// The face it keeps at rest: wide awake while Keep Awake holds the Mac up.
    var mascotRestingMood: NotchMascotMood { KeepAwakeManager.shared.isActive ? .alert : .idle }

    /// Whether the closed island on `geometry` draws the companion: resting,
    /// or strolling through, where its wings fit beside the camera. A capsule
    /// holds it inside, as it holds the charge.
    func mascotShows(on geometry: NotchGeometry) -> Bool {
        (mascotAtRest || mascotVisit != nil) && (geometry.floats || geometry.restingWingWidth > 0)
    }

    /// The companion needs the menu bar measured to know where its wings fit.
    private var mascotWantsRoom: Bool { NotchMascotSupport.isEnabled() }

    var hasTimerActivity: Bool {
        NotchTimerSupport.showsActivity(hasSession: NotchTimerService.shared.session.hasSession)
    }

    var hasWatchActivity: Bool {
        NotchWatchSupport.isEnabled() && NotchWatchService.shared.isActive
    }

    var hasDownloadActivity: Bool {
        NotchSupport.routes(.download)
            && NotchDownloadService.shared.items.contains { $0.active && !$0.completed }
    }

    var hasMusicActivity: Bool {
        NotchSupport.showsMusicActivity(isPlaying: NotchMusicService.shared.playback?.isPlaying == true)
    }

    var hasAgentActivity: Bool {
        NotchAgentSupport.showsLiveActivity() && !AgentUsageService.shared.snapshot.live.isEmpty
    }

    var hasCalendarActivity: Bool {
        let calendar = NotchCalendarService.shared
        guard let countdown = calendar.countdown,
              countdown.ongoing ? NotchCalendarSupport.showsTimeLeft()
                : NotchCalendarSupport.showsCountdown(chosen: calendar.isChosen(countdown.event))
        else { return false }
        return countdown.isShown(at: Date())
    }

    var hasKeepAwakeActivity: Bool {
        NotchKeepAwakeSupport.showsActivity() && KeepAwakeManager.shared.isActive
    }

    var compactActivity: NotchCompactActivity? {
        // A new song waiting for its notice is not drawn yet.
        activitySelection.current(available: awaitsTrackNotice ? compactActivities.filter { $0 != .music } : compactActivities)
    }

    var compactActivities: [NotchCompactActivity] {
        NotchSupport.compactActivities(timer: hasTimerActivity, watch: hasWatchActivity, downloads: hasDownloadActivity,
                                      agents: hasAgentActivity, calendar: hasCalendarActivity,
                                      music: hasMusicActivity, keepAwake: hasKeepAwakeActivity)
    }

    var showsCompactActivityPicker: Bool {
        (inside || activityPickerMenuOpen) && !hiddenInFullscreen && !hiddenUntilHover && !expanded && !peeking
            && !dragPlaceholder && notice == nil && captureControls == nil
            && compactActivities.count > 1
    }

    var compactActivityPickerLayout: NotchActivityPickerLayout {
        let activities = compactActivities
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let labelWidth = activities.map {
            ($0.title(L10n.shared.language) as NSString).size(withAttributes: [.font: font]).width
        }.max() ?? 0
        let combinations = compactActivityCombinations
        let sizes = activities.map { compactStripSize(for: $0) }
            + combinations.map { compactStripSize(for: $0.primary, companion: $0.companion) }
        // Switching the chosen strip must not move the buttons under the pointer.
        let strip = CGSize(width: sizes.map(\.width).max() ?? geometry.cameraWidth,
                           height: sizes.map(\.height).max() ?? geometry.stripHeight)
        return NotchActivityPickerLayout(count: activities.count, labelWidth: labelWidth,
                                         stripSize: strip, screenWidth: geometry.screen.width,
                                         hasCombinations: !combinations.isEmpty)
    }

    func selectCompactActivity(_ activity: NotchCompactActivity) {
        guard compactActivities.contains(activity) else { return }
        hoverWork?.cancel(); hoverWork = nil
        switchCompactSelection {
            activitySelection.select(activity, available: compactActivities)
        }
    }

    /// The picker keeps its size whatever is chosen, so the choice moves inside
    /// the surface, the highlight sliding and the strip changing in place,
    /// instead of the whole content fading through the host.
    private func switchCompactSelection(_ change: () -> Void) {
        let animation: Animation? = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? nil : .smooth(duration: 0.26)
        withAnimation(animation) {
            objectWillChange.send()
            change()
        }
        // A song chosen away is not music disappearing, which the host would
        // fade out through the whole picker as another activity takes its place.
        presentedMusic = nil
        refreshPresentation()
    }

    func selectCompactCombination(_ combination: NotchActivityCombination) {
        let companions = compactCompanions(of: combination.primary)
        guard companions.contains(combination.companion) else { return }
        hoverWork?.cancel(); hoverWork = nil
        switchCompactSelection {
            activitySelection.select(combination.primary, companion: combination.companion,
                                     available: compactActivities, companions: companions)
        }
    }

    /// The pairs `primary` supports now.
    func compactCompanions(of primary: NotchCompactActivity) -> [NotchCompactActivity] {
        NotchSupport.compactCompanions(of: primary, timer: hasTimerActivity,
                                       running: NotchTimerService.shared.session.isRunning,
                                       downloads: hasDownloadActivity, agents: hasAgentActivity,
                                       calendar: hasCalendarActivity, music: hasMusicActivity)
    }

    /// Every pair the picker offers, in the activities' own order.
    var compactActivityCombinations: [NotchActivityCombination] {
        compactActivities.flatMap { primary in
            compactCompanions(of: primary).map { NotchActivityCombination(primary: primary, companion: $0) }
        }
    }

    /// A single activity never borrows another activity's wing implicitly.
    var compactCompanion: NotchCompactActivity? {
        guard let activity = compactActivity, activity == activitySelection.preferred else { return nil }
        return activitySelection.companion(available: compactCompanions(of: activity))
    }

    private var compactActivityIsVisible: Bool {
        !fullscreenCompact && !expanded && !peeking && !dragPlaceholder && notice == nil && captureControls == nil
            && compactActivity != nil
    }

    private var compactMusicIsVisible: Bool { compactActivityIsVisible && compactActivity == .music }

    /// The song the closed island drew at its last refresh, for the frames
    /// between the music stopping and the refresh that lets it depart. The
    /// view reads playback live, so it kept drawing what rests under the
    /// song for that frame: the companion flashed there.
    var lingeringMusic: NotchCompactMusicSnapshot? {
        guard let presentedMusic, departingMusic == nil, compactActivity == nil, !expanded, !peeking,
              notice == nil, !dragPlaceholder, captureControls == nil else { return nil }
        return heldMusic ?? presentedMusic
    }

    var compactActivityGeometry: NotchGeometry {
        compactGeometry(for: compactActivity, companion: compactCompanion)
    }

    /// On the island's own display unless `base` is another display's.
    private func compactGeometry(for activity: NotchCompactActivity?, companion: NotchCompactActivity? = nil,
                                 base: NotchGeometry? = nil) -> NotchGeometry {
        var geometry = base ?? self.geometry
        if base == nil, showsCompactActivityPicker {
            let room = max(0, (geometry.screen.width - 24 - NotchActivityPickerLayout.horizontalInset * 2
                               - geometry.cameraWidth) / 2)
            geometry.compactSideRoom = min(geometry.compactSideRoom ?? 0, room)
        }
        switch activity {
        case .music: return geometry.compactMusicGeometry
        case .timer:
            return geometry.compactTimerGeometry(showsDownloads: companion == .downloads,
                                                 wing: timerStripWing(for: companion, in: geometry))
        case .downloads:
            let name = NotchDownloadService.shared.items.first { $0.active && !$0.completed }?.name
            return geometry.compactDownloadGeometry(wing: NotchDownloadSupport.compactWing(for: name, in: geometry))
        case .agents: return geometry.compactAgentGeometry(wing: agentStripWing(in: geometry))
        case .watch: return geometry.compactWatchGeometry(wing: watchStripWing(in: geometry))
        case .calendar:
            return geometry.compactCalendarGeometry(wing: calendarStripWing(for: companion, in: geometry),
                                                    paired: companion != nil)
        // Its reading is a countdown like the timer's, so it takes the timer's wings.
        case .keepAwake: return geometry.compactTimerGeometry(showsDownloads: false, wing: keepAwakeStripWing(in: geometry))
        default: return geometry
        }
    }

    /// The wider side: the eye at the left end, or the reading, or the
    /// area's own picture when it has no text, with air beside the camera.
    private func watchStripWing(in geometry: NotchGeometry) -> CGFloat {
        let provisional = geometry.compactWatchGeometry(wing: NotchWatchSupport.stripWingRange.lowerBound)
        let watch = NotchWatchService.shared
        let size = NotchTimerSupport.stripTextSize(height: provisional.compactActivityContentHeight)
        let reading = watch.showsThumbnail ? NotchWatchSupport.thumbnailWidth
            : (watch.headline as NSString).size(withAttributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium)
            ]).width.rounded(.up)
        let inset = provisional.compactActivityEdgeInset(boxHeight: size * 0.72, radius: 0)
        return reading + inset + NotchTimerSupport.stripCameraGap
    }

    private func keepAwakeStripWing(in geometry: NotchGeometry) -> CGFloat {
        NotchKeepAwakeSupport.stripWing(until: KeepAwakeManager.shared.endDate, now: Date(),
                                        locale: Locale(identifier: L10n.shared.language.rawValue), in: geometry)
    }

    /// The wider of the two sides, measured with the strip's fonts and its
    /// clearance from the curve: alone, the event's title or its clock and
    /// the time beside it; paired, the event's dot and clock or the mark of
    /// what shares the island, with air beside the camera.
    private func calendarStripWing(for companion: NotchCompactActivity?, in geometry: NotchGeometry) -> CGFloat {
        guard let countdown = NotchCalendarService.shared.countdown else {
            return NotchGeometry.calendarWingRange.upperBound
        }
        // Measured at the narrowest wing the strip may take.
        let provisional = geometry.compactCalendarGeometry(wing: 0, paired: companion != nil)
        let inset = provisional.compactActivityEdgeInset(boxHeight: 9, radius: 0)
        if let companion {
            let sides = max(inset + calendarClockWidth, companionMarkWidth(companion, in: provisional))
                + NotchTimerSupport.stripCameraGap
            // A download keeps room for its percentage, as beside a timer.
            return companion == .downloads ? max(80, sides) : sides
        }
        func width(_ text: String, _ font: NSFont) -> CGFloat {
            (text as NSString).size(withAttributes: [.font: font]).width.rounded(.up)
        }
        let language = L10n.shared.language
        let trimmed = countdown.event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? FeatureStrings.notchCalendar(language).untitled : trimmed
        let titleSide = NotchCalendarSupport.stripDotWidth + NotchCalendarSupport.stripTitleSpacing
            + width(title, .systemFont(ofSize: 11, weight: .semibold))
        // The widest clock the hour can show, so the island keeps its size
        // while the minutes count down.
        let clockSide = width("00:00", .monospacedDigitSystemFont(ofSize: 13, weight: .medium))
            + NotchCalendarSupport.stripClockSpacing
            + width(NotchCalendarSupport.timeText(countdown, locale: language.formattingLocale()),
                    .monospacedDigitSystemFont(ofSize: 11, weight: .medium))
        return inset + max(titleSide, clockSide)
    }

    /// The wider of the two sides, the timer's reading or what shares the
    /// island with it, drawn as the strip draws them, with the clearance
    /// from the silhouette's curve and air beside the camera.
    private func timerStripWing(for companion: NotchCompactActivity?, in geometry: NotchGeometry) -> CGFloat {
        let provisional = geometry.compactTimerGeometry(showsDownloads: false,
                                                        wing: NotchTimerSupport.stripWingRange.lowerBound)
        let height = provisional.compactActivityContentHeight
        let timer = NotchTimerService.shared
        let size = NotchTimerSupport.stripTextSize(height: height)
        let text = NotchTimerSupport.compactText(for: timer.session, at: timer.now,
                                                 locale: Locale(identifier: L10n.shared.language.rawValue))
        let reading = (NotchAgentSupport.readingShape(text) as NSString).size(withAttributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium)
        ]).width.rounded(.up) + provisional.compactActivityEdgeInset(boxHeight: size * 0.72, radius: 0)
        return max(reading, companionMarkWidth(companion, in: provisional)) + NotchTimerSupport.stripCameraGap
    }

    /// The width of the mark at a strip's left end, the timer's own without a
    /// companion, drawn as `NotchCompanionMark` draws it, with its clearance
    /// from the silhouette's curve.
    private func companionMarkWidth(_ companion: NotchCompactActivity?, in provisional: NotchGeometry) -> CGFloat {
        let height = provisional.compactActivityContentHeight
        switch companion {
        case .music:
            return provisional.compactMusicArtworkSide + provisional.compactMusicArtworkInset
        case .agents:
            let working = Set(AgentUsageService.shared.snapshot.live.map(\.provider)).count
            let side = NotchTimerSupport.stripAgentMarkSize(height: height, working: working)
            return CGFloat(max(1, working)) * (side * 1.45 + 1) + CGFloat(max(0, working - 1))
                + provisional.compactActivityEdgeInset(boxHeight: side + 4, radius: (side + 4) / 2)
        case .calendar:
            return provisional.compactActivityEdgeInset(boxHeight: 9, radius: 0) + calendarClockWidth
        default:
            // Every mark the strip shows is about a square of its point size.
            let side = NotchTimerSupport.stripIconSize(height: height)
            return side + provisional.compactActivityEdgeInset(boxHeight: side, radius: side / 2)
        }
    }

    /// An event's dot and the widest clock its hour can show, so the island
    /// keeps its size while the minutes count down.
    private var calendarClockWidth: CGFloat {
        NotchCalendarSupport.stripDotWidth + NotchCalendarSupport.stripClockSpacing
            + ("00:00" as NSString).size(withAttributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
            ]).width.rounded(.up)
    }

    /// The wider of the two sides, the reading or the working agents' marks,
    /// with the clearance from the silhouette's curve that the strip keeps
    /// and air beside the camera.
    private func agentStripWing(in geometry: NotchGeometry) -> CGFloat {
        let provisional = geometry.compactAgentGeometry(wing: NotchAgentSupport.stripWingRange.lowerBound)
        let size = NotchAgentSupport.stripTextSize(height: provisional.compactActivityContentHeight)
        let shape = NotchAgentSupport.readingShape(NotchAgentSupport.stripReading(
            AgentUsageService.shared.snapshot, readout: NotchAgentSupport.readout(),
            display: NotchAgentSupport.limitDisplay(), focus: NotchAgentSupport.limitFocus(), now: Date()))
        let width = (shape as NSString).size(withAttributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium)
        ]).width
        let reading = width.rounded(.up) + provisional.compactActivityEdgeInset(boxHeight: size * 0.72, radius: 0)
        // The marks on the other side, drawn as the strip draws them: two
        // working agents share a smaller size, each in a frame wider than it.
        let working = Set(AgentUsageService.shared.snapshot.live.map(\.provider)).count
        let mark = CGFloat(working > 1 ? 11 : 14)
        let frame = mark * 1.45 + 1
        let marks = CGFloat(max(1, working)) * frame + CGFloat(max(0, working - 1))
            + provisional.compactActivityEdgeInset(boxHeight: mark + 4, radius: (mark + 4) / 2)
        return max(reading, marks) + NotchAgentSupport.stripCameraGap
    }

    var expandedSize: CGSize {
        if showingSections {
            return geometry.sectionPickerSize(count: filteredSections.count)
        }
        let musicExtras = NotchLyricsSupport.isEnabled() || NotchQueueSupport.isEnabled()
        let launcher = QuickLauncherService.shared
        return pageSize(in: expandedGeometry, module: showingAppPanel ? .tools : selected,
                        detail: selectedMetric != nil, panel: showingAppPanel,
                        detailHeight: selectedMetric == .fan ? fanDetailHeight : nil,
                        musicExtraHeight: musicExtras && musicDetailVisible ? geometry.musicExtrasHeight : 0,
                        fileMediaHeight: !choosingFileDropDestination && AppFeature.mediaTools.isAvailable
                            && NotchFileToolsService.shared.mediaPresented ? NotchFileToolsService.shared.mediaContentHeight : nil,
                        toolCount: launcher.isEditing || launcher.activeUtility != nil ? nil : launcher.visibleItems.count,
                        capturePreviewHeight: captureContent == nil ? nil : captureContentHeight)
    }

    /// The open island as Settings previews a section: at rest, with no
    /// detail, app panel, capture or media editor in front of the page.
    func previewSize(for module: NotchModule) -> CGSize {
        pageSize(in: previewGeometry(for: module), module: module, detail: false, panel: false, detailHeight: nil, musicExtraHeight: 0,
                 fileMediaHeight: nil, toolCount: QuickLauncherService.shared.visibleItems.count, capturePreviewHeight: nil)
    }

    /// The island around a previewed section, whose title sits beside the
    /// camera only where the island's would.
    func previewGeometry(for module: NotchModule) -> NotchGeometry {
        previewGeometry(for: module, sectionsButton: previewShowsSectionsButton)
    }

    private func previewGeometry(for module: NotchModule, sectionsButton: Bool) -> NotchGeometry {
        var result = geometry
        result.headerTitleWidth = NotchLayout.headerTitleWidth(module.title(L10n.shared.language), button: sectionsButton)
        return result
    }

    /// Settings previews the island while it is off too, when the floating
    /// buttons are not read for it, so a preview reads them as it draws.
    private var previewShowsSectionsButton: Bool {
        !NotchQuickAccessConfiguration.current().actions.contains(.explore)
    }

    /// The tallest island a preview can show: a page that fills the budget,
    /// below the row the widest title may need.
    var previewLargestSize: CGSize {
        let sectionsButton = previewShowsSectionsButton
        var tallest = geometry
        tallest.headerTitleWidth = NotchModule.allCases
            .map { previewGeometry(for: $0, sectionsButton: sectionsButton).headerTitleWidth }.max() ?? 0
        return tallest.expandedSize(module: .calendar)
    }

    private func pageSize(in geometry: NotchGeometry, module: NotchModule, detail: Bool, panel: Bool,
                          detailHeight: CGFloat?, musicExtraHeight: CGFloat, fileMediaHeight: CGFloat?, toolCount: Int?,
                          capturePreviewHeight: CGFloat?) -> CGSize {
        let controls = NotchSupport.controls()
        let sliders = controls.filter { $0 == .volume || $0 == .brightness }.count
        let shortcuts = controls.filter { $0 != .volume && $0 != .brightness && $0 != .music }.count
        let musicExtras = NotchLyricsSupport.isEnabled() || NotchQueueSupport.isEnabled()
        return geometry.expandedSize(module: module, detail: detail, panel: panel, detailHeight: detailHeight,
                                     shortcutCount: shortcuts,
                                     sliderCount: sliders, controlsHaveMusic: controls.contains(.music), musicHasContent: NotchMusicService.shared.playback != nil,
                                     musicHasControlsRow: AppFeature.mixer.isAvailable || musicExtras,
                                     musicExtraHeight: musicExtraHeight, fileMediaHeight: fileMediaHeight,
                                     systemCards: NotchSupport.systemCardCount(hasBattery: PowerSampler.hasInternalBattery,
                                                                               fans: SystemMonitor.shared.snapshot.fanSpeeds.count),
                                     toolCount: toolCount, capturePreviewHeight: capturePreviewHeight,
                                     timerHasSession: NotchTimerService.shared.session.hasSession,
                                     timerMode: NotchTimerService.shared.session.hasSession
                                        ? NotchTimerService.shared.session.mode : NotchTimerSupport.savedMode(),
                                     agentsHeight: module == .agents && !detail && !panel
                                        ? agentsContentHeight(width: geometry.contentWidth) : nil)
    }

    /// The AI page is as tall as the cards it shows; nil while the logs are
    /// first read, when the page fills the island with its progress.
    private func agentsContentHeight(width: CGFloat) -> CGFloat? {
        let usage = AgentUsageService.shared.snapshot
        guard usage.loaded else { return nil }
        let providers = NotchAgentSupport.providers().filter(usage.seen.contains)
        guard !providers.isEmpty else { return 0 }
        return NotchAgentSupport.contentHeight(NotchAgentSupport.rows(
            NotchAgentSupport.tiles(cards: NotchAgentSupport.cards(), providers: providers), width: width))
    }
    var expandedGeometry: NotchGeometry {
        var result = geometry
        // Capture editing has a full toolbar whose actions must stay reachable.
        result.requiresFullWidthHeader = selected == .captures && captureActions != nil
            && !showingSections && !showingAppPanel && selectedMetric == nil
        result.headerTitleWidth = headerTitleWidth
        return result
    }
    /// The open header's title and the button before it, as the header draws
    /// them. Choosing a section shows only its search beside the camera, which
    /// takes the room its side leaves.
    private var headerTitleWidth: CGFloat {
        guard !showingSections else { return 0 }
        let detail = showingAppPanel || selectedMetric != nil
        guard detail || modules.isEmpty else {
            return NotchLayout.headerTitleWidth(selected.title(L10n.shared.language), button: headerShowsSectionsButton)
        }
        return NotchLayout.headerTitleWidth(detailTitle, font: NotchLayout.detailTitleFont, button: detail)
    }
    /// A detail's title, the app panel's, or the island's own with no sections.
    var detailTitle: String {
        if showingAppPanel { return "Vorssaint" }
        let language = L10n.shared.language
        guard let metric = selectedMetric else { return FeatureStrings.notch(language).title }
        // The fan card opens Fan Control, so its page shares that title.
        return metric == .fan ? FeatureStrings.fanControl(language).title : metric.title(L10n.shared.s)
    }
    var contentSize: CGSize { expandedGeometry.contentSize(for: expandedSize) }
    var usesGlassSurface: Bool {
        // The Command Bar keeps the island black, as its drop is: it changes
        // height with every keystroke, and the glass is drawn a frame behind
        // the shape, which showed rows outside it for that frame.
        (expanded && !showingCommandBar) || peeking || dragPlaceholder || noticeExpanded
            || (captureControls != nil && !captureControlsCollapsed)
    }

    /// The open capture controls, measured with their title's font.
    var captureControlsLayout: NotchCaptureControlsLayout {
        NotchCaptureControlsLayout(
            geometry: geometry,
            titleWidth: NotchCaptureControlsLayout.titleWidth(FeatureStrings.screenshot(L10n.shared.language).screenCaptureTitle),
            capturesAudio: captureControls?.selectedTool.capturesAudio == true)
    }

    var surfaceSize: CGSize {
        if let capsule = capsuleSurfaceSize { return capsule }
        if fullscreenCompact { return geometry.bareCutout }
        if captureControls != nil {
            if captureControlsCollapsed {
                return CGSize(width: geometry.cameraWidth + 56, height: geometry.stripHeight)
            }
            return captureControlsLayout.size
        }
        if expanded { return showingCommandBar ? commandBarSurfaceSize : expandedSize }
        if dragPlaceholder { return CGSize(width: geometry.peek.width, height: geometry.safeContentTop + 66) }
        if let notice {
            guard noticeExpanded else { return geometry.noticeSize(wings: notice.wings(in: geometry)) }
            return geometry.notificationPreviewSize(
                contentHeight: notice.previewContentHeight(width: geometry.notificationPreviewContentWidth))
        }
        if peeking { return geometry.peek }
        if showsCompactActivityPicker { return compactActivityPickerLayout.size }
        if compactActivity != nil {
            let resting = compactActivityGeometry.compactActivitySize
            return hoverEmphasized ? NotchHoverEmphasis.size(from: resting, geometry: geometry) : resting
        }
        let resting = geometry.restingSize(showsContent: idleContent != .none || mascotShows(on: geometry))
        return hoverEmphasized ? NotchHoverEmphasis.size(from: resting, geometry: geometry) : resting
    }

    /// How far the island's centre sits right of the camera's. Only a closed
    /// notice beside a camera reaches further toward its wider side; a
    /// capsule runs its notices end to end.
    var surfaceShift: CGFloat {
        guard !geometry.floats, !fullscreenCompact, captureControls == nil, !expanded, !dragPlaceholder,
              let notice, !noticeExpanded else { return 0 }
        return geometry.noticeShift(notice.wings(in: geometry))
    }

    /// The open island around the Command Bar: the bar's width within the
    /// island's margins, and its height below the camera.
    var commandBarSurfaceSize: CGSize {
        let width = max(geometry.cameraWidth + 80, CommandBarView.width + NotchLayout.horizontalInset * 2)
        let height = geometry.safeContentTop + (commandBarHeight ?? CommandBarView.fieldHeight) + NotchLayout.bottomInset
        return CGSize(width: min(geometry.screen.width - 24, width), height: min(geometry.screen.height - 48, height))
    }

    /// A floating capsule's closed strips run from one round end to the
    /// other and are as wide as what they show. Open, peeking or choosing an
    /// activity, it takes the island's own sizes. Nil when the island hangs.
    private var capsuleSurfaceSize: CGSize? {
        guard geometry.floats, !fullscreenCompact, !expanded, !dragPlaceholder else { return nil }
        if captureControls != nil { return captureControlsCollapsed ? NotchCapsuleLayout.captureSurface(geometry: geometry) : nil }
        if let notice { return noticeExpanded ? nil : capsuleNoticeSize(notice) }
        if peeking || showsCompactActivityPicker { return nil }
        // At rest the charge or the allowance fits inside the bare capsule.
        let resting = compactActivity.map { capsuleStripSize(for: $0, companion: compactCompanion) }
            ?? geometry.restingSize(showsContent: false)
        return hoverEmphasized ? NotchHoverEmphasis.size(from: resting, geometry: geometry) : resting
    }

    /// The last banner's capsule. A banner replacing it keeps at least its
    /// width, so a burst of messages does not resize the island with each one.
    private var bannerCapsuleWidth: CGFloat = 0

    private func capsuleNoticeSize(_ notice: NotchNotice) -> CGSize {
        var size = capsuleNoticeSurface(notice)
        guard notice.notification != nil else { return size }
        if notice.minimumWings != .zero { size.width = max(size.width, bannerCapsuleWidth) }
        bannerCapsuleWidth = size.width
        return size
    }

    /// A notice's own capsule, which it keeps while the island closes around it.
    func capsuleNoticeSurface(_ notice: NotchNotice) -> CGSize {
        let layout = NotchCapsuleLayout.self
        guard let content = notice.notification else {
            return layout.surface(content: layout.noticeContent(title: notice.title, detail: notice.detail,
                                                                level: notice.level != nil),
                                  maximum: layout.Maximum.notice, geometry: geometry)
        }
        return layout.surface(content: layout.notificationContent(title: content.compactTitle, message: content.compactDetail,
                                                                 geometry: geometry),
                              maximum: layout.Maximum.notification, geometry: geometry)
    }

    /// The closed strip an activity takes on its own: a capsule as wide as
    /// what it shows, or the hanging strip around the camera.
    func compactStripSize(for activity: NotchCompactActivity, companion: NotchCompactActivity? = nil) -> CGSize {
        geometry.floats ? capsuleStripSize(for: activity, companion: companion)
            : compactGeometry(for: activity, companion: companion).compactActivitySize
    }

    /// Measured from what the capsule's views show, with their own measures,
    /// on the island's display unless `geometry` is another display's.
    private func capsuleStripSize(for activity: NotchCompactActivity, companion: NotchCompactActivity?,
                                  geometry: NotchGeometry? = nil) -> CGSize {
        let geometry = geometry ?? self.geometry
        let layout = NotchCapsuleLayout.self
        let language = L10n.shared.language
        let download = NotchDownloadService.shared.items.first { $0.active && !$0.completed }
        let working = Set(AgentUsageService.shared.snapshot.live.map(\.provider)).count
        switch activity {
        case .music:
            let playback = heldMusic?.playback ?? NotchMusicService.shared.playback
            return layout.musicSurface(title: capsuleMusicTitleShown
                                        ? playback?.track.title ?? FeatureStrings.radialMenu(language).mediaNowPlaying : nil,
                                       geometry: geometry)
        case .timer:
            let timer = NotchTimerService.shared
            return layout.timerSurface(reading: NotchTimerSupport.compactText(for: timer.session, at: timer.now,
                                                                              locale: Locale(identifier: language.rawValue)),
                                       companion: companion, workingAgents: working,
                                       downloadPercent: download?.fraction != nil, geometry: geometry, language: language)
        case .downloads:
            return layout.downloadSurface(name: download?.name ?? FeatureStrings.notchFiles(language).downloadsTitle,
                                          hasProgress: download?.fraction != nil, geometry: geometry, language: language)
        case .agents:
            let reading = NotchAgentSupport.stripReading(AgentUsageService.shared.snapshot, readout: NotchAgentSupport.readout(),
                                                         display: NotchAgentSupport.limitDisplay(),
                                                         focus: NotchAgentSupport.limitFocus(), now: Date())
            return layout.agentSurface(reading: reading, working: working, geometry: geometry)
        case .calendar:
            guard let countdown = NotchCalendarService.shared.countdown else { return geometry.restingSize(showsContent: false) }
            if let companion {
                return layout.calendarPairSurface(companion: companion, workingAgents: working,
                                                  downloadPercent: download?.fraction != nil, geometry: geometry,
                                                  language: language)
            }
            return layout.calendarSurface(title: layout.calendarTitle(countdown, language: language),
                                          time: NotchCalendarSupport.timeText(countdown, locale: language.formattingLocale()),
                                          geometry: geometry)
        case .watch:
            let watch = NotchWatchService.shared
            return layout.watchSurface(reading: watch.headline, thumbnail: watch.showsThumbnail, geometry: geometry)
        case .keepAwake:
            let reading = KeepAwakeManager.shared.endDate.map {
                NotchKeepAwakeSupport.compactText(until: $0, now: Date(), locale: Locale(identifier: language.rawValue))
            }
            return layout.keepAwakeSurface(reading: reading, geometry: geometry)
        }
    }

    var presentationWindow: NSPanel? { panel }
    /// User actions can open the island even when automatic full-screen feedback is hidden.
    var acceptsUserInteraction: Bool {
        running && !suspended && panel != nil
            && windowHost?.isConcealedForMissionControl != true
    }
    var acceptsSystemFeedback: Bool {
        acceptsUserInteraction && !hiddenInFullscreen
    }
    var showsSystemFeedback: Bool {
        acceptsSystemFeedback && !hiddenUntilHover
    }

    var protectedWindowIDs: Set<CGWindowID> {
        NotchSupport.showsInCaptures() ? [] : islandWindowIDs
    }

    var captureVisibleWindowIDs: Set<CGWindowID> {
        NotchSupport.showsInCaptures() ? islandWindowIDs : []
    }

    /// The island's window and its copies on other displays, as shown.
    private var islandWindowIDs: Set<CGWindowID> {
        let panels: [NotchPanel?] = [panel] + mirrors.values.map { $0.host.panel }
        return Set(panels.compactMap { panel -> CGWindowID? in
            guard let panel, panel.isVisible, panel.windowNumber > 0 else { return nil }
            return CGWindowID(panel.windowNumber)
        })
    }

    /// While a capture is choosing an area on screen, the notch is part of the
    /// capture interface, so its window is kept out of the pixels no matter
    /// what the everyday "show in captures" preference says. This lets people
    /// grab whatever sits behind the notch cleanly.
    var captureChromeWindowIDs: Set<CGWindowID> {
        running ? islandWindowIDs : []
    }

    func syncWithPreferences() {
        preferenceSyncWork?.cancel(); preferenceSyncWork = nil
        guard NotchSupport.isEnabled() else { stop(); return }
        if !running {
            running = true
            installObservers()
        }
        if !NotchTimerSupport.isEnabled() { NotchTimerService.shared.stop() }
        // A watch keeps reading while the island is away, as on the lock
        // screen, and says so with a notification if it cannot show itself.
        NotchWatchService.shared.syncWithPreferences()
        // Requested file work can continue while locked, but disabling its
        // feature must still cancel it before presentation resumes.
        NotchFileToolsService.shared.syncWithPreferences()
        if !NotchFileToolsService.shared.offersMediaDrop { endFileDrop() }
        // Paused while the island is away, the section still stops at once
        // when it is turned off.
        if !NotchAgentSupport.isEnabled() { AgentUsageService.shared.stop() }
        guard !suspended else {
            if session.canRunTimer { NotchTimerService.shared.syncWithPreferences() }
            else { NotchTimerService.shared.suspend() }
            NotchLockScreenService.shared.sync(session)
            return
        }
        // Checked before any service starts, so each preference change while
        // the lid is closed does not start and stop them all again.
        guard screenIndex(in: NSScreen.screens) != nil else { withdrawFromMissingScreen(); return }
        refreshModules()
        NotchDownloadService.shared.syncWithPreferences()
        NotchCalendarService.shared.syncWithPreferences()
        NotchNotificationService.shared.syncWithPreferences()
        NotchAudioLevelService.shared.syncWithPreferences()
        AgentUsageService.shared.syncWithPreferences()
        followsPointer = displayPreference == .pointer || displayPreference == .all
        showsOnAllDisplays = displayPreference == .all
        updateFullscreenDisplays()
        updateScreen()
        syncPointerFollowing()
        syncGestures()
        NotchTimerService.shared.syncWithPreferences()
        NotchAccessoryService.shared.syncWithPreferences()
        let signature = NotchEvent.allCases.map { String(NotchSupport.routes($0)) }.joined()
            + NotchSupport.idleContent().rawValue + String(NotchSupport.watchesMusicActivity())
            + String(NotchKeepAwakeSupport.showsActivity())
            + modules.map(\.rawValue).joined()
            + String(AppFeature.fanControl.isAvailable)
            + String(NotchSupport.routesShelf()) + String(NotchSupport.revealsShelfDrag())
            + String(NotchSupport.routesCaptureControls())
            + String(NotchMascotSupport.isEnabled())
        if signature != settingsSignature {
            settingsSignature = signature
            bindEvents()
            if AppFeature.shelf.isAvailable { ShelfService.shared.syncWithPreferences() }
        }
        if !NotchSupport.routes(.capture), captureContent != nil {
            let fallback = captureFallback
            clearCapture()
            fallback?()
        }
        if captureControls != nil, !NotchSupport.routesCaptureControls() { cancelCaptureControls() }
        syncNoticeWithPreferences()
        syncVisibleConsumers()
        // Turning the companion on or off grows or folds the wings it rests
        // in, in view, as music arriving does. Other preferences apply at once.
        let mascotEnabled = NotchMascotSupport.isEnabled()
        let mascotToggled = mascotWasEnabled.map { $0 != mascotEnabled } ?? false
        mascotWasEnabled = mascotEnabled
        if mascotToggled, !expanded { stageMascotEntrance(arriving: mascotEnabled) }
        refreshPresentation(animated: mascotToggled && !expanded)
        syncMascotVisits()
        syncMascotSide()
        // Pages read their preferences as they draw, and a change that keeps
        // the island's size publishes nothing else: hiding a control left the
        // open island, and the preview in Settings, as they were. The open
        // island's companion fades in or out where it stands.
        let fade = mascotToggled && expanded && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(fade ? .easeInOut(duration: 0.22) : nil) { objectWillChange.send() }
        if AppFeature.mixer.isAvailable { PreciseVolumeRollerService.shared.syncWithPreferences() }
        if AppFeature.brightness.isAvailable { BrightnessService.shared.syncWithPreferences() }
    }

    private func refreshModules() {
        let updated = NotchSupport.modules()
        if modules != updated { modules = updated }
        let selection = modules.contains(selected) ? selected : modules.first ?? .controls
        if selected != selection { selected = selection }
        if let selectedMetric, !metricIsAvailable(selectedMetric) { self.selectedMetric = nil }
    }

    private func metricIsAvailable(_ metric: MetricDetailKind) -> Bool {
        MenuBarMetric.allCases.contains { $0.detailKind == metric && $0.feature.isAvailable }
    }

    func stop(restoreCapture: Bool = true) {
        preferenceSyncWork?.cancel(); preferenceSyncWork = nil
        NotchLyricsService.shared.stop()
        NotchFileToolsService.shared.stop()
        AgentUsageService.shared.stop()
        guard running else { return }
        running = false
        NotchTimerService.shared.stop()
        NotchAccessoryService.shared.stop()
        NotchWatchService.shared.stop()
        let cancelCapture = captureControlsCancel
        endCaptureControls()
        cancelCapture?()
        let fallback = restoreCapture ? captureFallback : captureClose
        clearCapture()
        tearDownPresentation()
        NotchLockScreenService.shared.close()
        observers.forEach { $0.0.removeObserver($0.1) }
        observers.removeAll()
        session = NotchSessionState()
        if AppFeature.mixer.isAvailable { PreciseVolumeRollerService.shared.syncWithPreferences() }
        if AppFeature.brightness.isAvailable { BrightnessService.shared.syncWithPreferences() }
        if AppFeature.shelf.isAvailable { ShelfService.shared.syncWithPreferences() }
        fallback?()
    }

    private func tearDownPresentation() {
        screenRefreshWork?.cancel(); screenRefreshWork = nil
        nextMascotVisitWork?.cancel(); nextMascotVisitWork = nil
        mascotVisitWork?.cancel(); mascotVisitWork = nil
        mascotStepBackWork?.cancel(); mascotStepBackWork = nil
        mascotVisit = nil
        mascotStepsAside = false
        mascotInBar = false
        commandBarHeight = nil
        if showingCommandBar {
            showingCommandBar = false
            commandBarDidClose()
        }
        captureControlsWork?.cancel(); captureControlsWork = nil
        musicDetailVisible = false
        pageLayers.removeAll()
        panel?.handleScroll = nil
        gesture = NotchGestureSupport()
        sectionScroll = NotchSectionScroll()
        stopMenuSpaceMonitoring()
        geometry.compactSideRoom = nil
        hoverWork?.cancel(); hoverWork = nil
        noticeWork?.cancel(); noticeWork = nil
        endDeparture()
        finishMusicDeparture()
        presentedMusic = nil
        trackWork?.cancel(); trackWork = nil
        heldMusic = nil
        awaitsTrackNotice = false
        subscriptions.removeAll()
        stopPower()
        NotchMusicService.shared.stop()
        NotchAudioLevelService.shared.stop()
        CameraPreviewService.shared.hideEmbedded()
        NotchAccessoryService.shared.suspend()
        NotchDownloadService.shared.stop()
        NotchCalendarService.shared.stop()
        NotchNotificationService.shared.stop()
        AgentUsageService.shared.pause()
        settingsSignature = ""
        expanded = false
        peeking = false
        dragPlaceholder = false
        endFileDrop()
        fileInteractionActive = false
        heldDrag = false
        selectedMetric = nil
        pinned = false
        notice = nil
        noticeExpanded = false
        showingAppPanel = false
        showingSections = false
        sectionQuery = ""
        highlightedSection = nil
        sectionRow = 0
        inside = false
        hoverEmphasized = false
        activitySelection = NotchActivitySelection()
        activityPickerMenuOpen = false
        hoverState = NotchHoverState()
        openedByHover = false
        removeEventMonitors()
        removeScreenEdgeClickMonitors()
        removeCaptureControlsClickThrough()
        removeHiddenHoverMonitors()
        removeHoverExitMonitors()
        removePointerMonitors()
        releaseMonitor()
        musicTitleWork?.cancel(); musicTitleWork = nil
        capsuleMusicTitleShown = false
        closeMirrors()
        windowHost?.close()
        windowHost = nil
        // Shown again, an island that follows the pointer starts on its display.
        displayID = nil
        syncPanelKey()
        hiddenInFullscreen = false
    }

    /// Opening without a page shows what the closed island is already
    /// presenting: a mirrored banner, or an activity unless the user turned
    /// that off. Otherwise the reopening preference decides.
    var reopeningDestination: (module: NotchModule, appPanel: Bool, sections: Bool) {
        if !expanded {
            let opensActivity = UserDefaults.standard.object(forKey: DefaultsKey.notchOpensActivity) as? Bool ?? true
            let activity = notice?.notificationID != nil ? NotchModule.notifications
                : opensActivity ? compactActivity?.module : nil
            if let activity, modules.contains(activity) { return (activity, false, false) }
            if UserDefaults.standard.bool(forKey: DefaultsKey.notchReturnHome) {
                let saved = UserDefaults.standard.string(forKey: DefaultsKey.notchHomeModule) ?? ""
                switch NotchReopeningDestination(rawValue: saved) {
                case .appPanel: return (modules.contains(.controls) ? .controls : modules.first ?? .controls, true, false)
                case .explore: return (selected, false, true)
                case nil:
                    let home = NotchModule(rawValue: saved) ?? .controls
                    return (modules.contains(home) ? home : modules.first ?? .controls, false, false)
                }
            }
        }
        return (selected, false, false)
    }

    var reopeningModule: NotchModule {
        reopeningDestination.module
    }

    /// A compact strip opens its activity's page, as opening the island does:
    /// unless the user turned off opening the visible activity, in which case
    /// the reopening choice decides here too.
    func openActivity(_ module: NotchModule) {
        let opensActivity = UserDefaults.standard.object(forKey: DefaultsKey.notchOpensActivity) as? Bool ?? true
        if opensActivity { open(module) } else { open() }
    }

    /// Opens the Calendar page scrolled to the countdown's event.
    func openCountdownEvent() {
        let calendar = NotchCalendarService.shared
        calendar.revealing = calendar.countdown?.event.id
        openActivity(.calendar)
        // Explore or an app panel opened in the page's place keeps no event
        // for a later visit to Calendar.
        if !expanded || selected != .calendar || showingSections || showingAppPanel { calendar.revealing = nil }
    }

    func open(_ module: NotchModule? = nil, pinned: Bool = false, takeFocus: Bool = true,
              appPanel: Bool = false, metric: MetricDetailKind? = nil, feedback: Bool = true, sections: Bool = false) {
        guard NotchSupport.isEnabled(), !suspended else { return }
        if !running || self.panel == nil { syncWithPreferences() }
        else { refreshModules() }
        guard let panel else { return }
        let reopening = reopeningDestination
        let useReopeningSurface = module == nil && !expanded && !appPanel && !sections && metric == nil
        let destination = module.flatMap { modules.contains($0) ? $0 : nil } ?? reopening.module
        let appPanel = appPanel || (useReopeningSurface && reopening.appPanel)
        let sections = sections || (useReopeningSurface && reopening.sections)
        if useReopeningSurface && reopening.appPanel { MenuPanelFocus.shared.showNormalPanel() }
        if useReopeningSurface && reopening.sections {
            sectionQuery = ""
            sectionRow = 0
            highlightedSection = destination
        }
        let metric = metric.flatMap { metricIsAvailable($0) ? $0 : nil }
        let closesCommandBar = showingCommandBar
        let changesPresentation = !expanded || selected != destination || closesCommandBar
            || showingAppPanel != appPanel || selectedMetric != metric || showingSections != sections
        if changesPresentation, destination == .tools, !appPanel, !sections, metric == nil {
            QuickLauncherService.shared.prepareForPresentation()
        }
        (NSApp.delegate as? AppDelegate)?.closePopover(preservingNotch: true)
        if !expanded, modules.contains(.clipboard) { ClipboardHistoryService.shared.rememberPasteTarget() }
        panel.acceptsKeyFocus = true
        hoverState.open()
        hoverWork?.cancel()
        // Entering a detail decides what lies behind it; switching details or
        // passing through the gallery keeps that answer.
        if !expanded { detailHasPage = false }
        else if appPanel || metric != nil, !showingAppPanel, selectedMetric == nil { detailHasPage = true }
        // Following the closed island ends the moment it opens, before a page
        // or a capture preview under the pointer can be told the pointer left.
        // An open page is followed again only from an exit report.
        if !expanded { removeHoverExitMonitors() }
        let mascotFrom = mascotBridgeStart(opening: true)
        mutatePresentation(transitionContent: changesPresentation ? (expanded ? .replace : .reveal) : .none) {
            showingCommandBar = false
            showingAppPanel = appPanel
            showingSections = sections
            if selected != destination { selected = destination }
            if pinned { self.pinned = true }
            selectedMetric = metric
            peeking = false
            openedByHover = !takeFocus
            expanded = true
            // The open island covers a mirrored banner, and the inbox keeps
            // the message; a held one must not reappear after collapsing.
            if notice?.notificationID != nil { noticeWork?.cancel(); noticeWork = nil; notice = nil; noticeExpanded = false }
        }
        if let mascotFrom { bridgeMascot(from: mascotFrom, opening: true) }
        inside = windowHost?.containsHover(NSEvent.mouseLocation) == true
        installEventMonitors()
        syncVisibleConsumers()
        if takeFocus { panel.makeKey() }
        if feedback, changesPresentation { provideHapticFeedback() }
        if closesCommandBar { commandBarDidClose() }
    }

    func collapse() {
        guard captureControls == nil, !heldDrag else { return }
        let closeCapture = detachCaptureIfClosingOnCollapse()
        let closesCommandBar = showingCommandBar
        hoverState.close(pointerInside: windowHost?.containsHover(NSEvent.mouseLocation) == true)
        pinned = false
        hoverWork?.cancel(); hoverWork = nil
        if noticeExpanded { noticeWork?.cancel(); noticeWork = nil }
        let mascotFrom = mascotBridgeStart(opening: false)
        mutatePresentation(transitionContent: expanded || peeking || noticeExpanded ? .dismiss : .none) {
            if noticeExpanded { notice = nil; noticeExpanded = false }
            expanded = false
            openedByHover = false
            peeking = false
            selectedMetric = nil
            showingAppPanel = false
            showingSections = false
            showingCommandBar = false
            sectionQuery = ""
            highlightedSection = nil
            sectionRow = 0
        }
        if let mascotFrom { bridgeMascot(from: mascotFrom, opening: false) }
        panel?.acceptsKeyFocus = false
        panel?.resignKey()
        if closesCommandBar { commandBarDidClose() }
        removeEventMonitors()
        syncVisibleConsumers()
        closeCapture?()
    }

    func toggle() { expanded ? collapse() : open() }

    func setMusicDetailsVisible(_ visible: Bool) {
        guard visible != musicDetailVisible else { return }
        mutatePresentation { musicDetailVisible = visible }
    }

    @discardableResult
    func showClipboard(toggle: Bool = false) -> Bool {
        guard acceptsUserInteraction, NotchSupport.routesClipboardWindow() else { return false }
        if toggle, expanded, selected == .clipboard, !showingAppPanel, !showingSections, !showingCommandBar { collapse() }
        else { open(.clipboard) }
        return true
    }

    func hover(_ entered: Bool) {
        guard running, !suspended, !hiddenAtRestInFullscreen else { removeHoverExitMonitors(); return }
        let point = NSEvent.mouseLocation
        let wasInside = inside
        let showedPicker = showsCompactActivityPicker
        inside = hiddenUntilHover ? geometry.contains(point, in: geometry.collapsed)
            && windowHost?.isConcealedForMissionControl == false
            : windowHost?.containsHover(point) == true || pointerOverChildWindow(point)
        hoverState.update(pointerInside: inside)
        // A full hover opening goes straight from its resting size to the page.
        // The activity picker replaces that opening and keeps its hover response.
        let opensOnHover = UserDefaults.standard.bool(forKey: DefaultsKey.notchOpenOnHover)
            && UserDefaults.standard.bool(forKey: DefaultsKey.notchHoverExpands) && !showsCompactActivityPicker
        let emphasize = inside && !hiddenInFullscreen && !hiddenUntilHover && !expanded && !peeking && !dragPlaceholder
            && notice == nil && captureControls == nil && !opensOnHover
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if hoverEmphasized != emphasize || showedPicker != showsCompactActivityPicker {
            hoverEmphasized = emphasize
            refreshPresentation()
        }
        defer { syncHoverExitMonitoring(entered: entered, point: point) }
        captureHover?(entered)
        if captureControls != nil {
            updateCaptureControlsHover(wasInside: wasInside)
            return
        }
        guard !pinned, !heldDrag, !keepsWorkingSurface else {
            hoverWork?.cancel(); hoverWork = nil
            // A dialog or menu keeps the island, not a banner the pointer left.
            if !inside { releaseNotification() }
            return
        }
        // Overlapping tracking areas can report the same presence repeatedly.
        // Keep the first deadline until the pointer actually crosses the boundary.
        if inside == wasInside, let hoverWork, !hoverWork.isCancelled { return }
        hoverWork?.cancel(); hoverWork = nil
        // The visible choices replace automatic opening while several
        // activities compete. Clicking the strip still opens its full page.
        if showsCompactActivityPicker { return }
        if inside {
            if holdsNotification, let id = notice?.notificationID { holdNotification(id); return }
            guard !hoverState.suppressed, (notice == nil || hiddenUntilHover), !expanded, !peeking, !dragPlaceholder,
                  UserDefaults.standard.bool(forKey: DefaultsKey.notchOpenOnHover) else { return }
            if !hiddenInFullscreen, compactActivity != nil, compactActivityGeometry.compactActivityWingWidth > 0,
               !UserDefaults.standard.bool(forKey: DefaultsKey.notchHoverExpands) { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.hoverWork = nil
                // An opening that is no longer eligible keeps any following:
                // an emphasis or a picker may still show, and the next move
                // decides whether it is still needed.
                guard self.running, !self.suspended, self.inside, !self.hoverState.suppressed,
                      !self.expanded, !self.peeking, !self.pinned, !self.heldDrag, !self.keepsWorkingSurface,
                      !self.showsCompactActivityPicker,
                      self.captureControls == nil, (self.notice == nil || self.hiddenUntilHover), !self.dragPlaceholder,
                      UserDefaults.standard.bool(forKey: DefaultsKey.notchOpenOnHover),
                      self.windowHost?.blocksHoverReveal() == false,
                      self.geometry.contains(NSEvent.mouseLocation, in: self.hiddenUntilHover ? self.geometry.collapsed : self.surfaceSize) else { return }
                // Following the closed island ends as it opens or peeks.
                self.removeHoverExitMonitors()
                if UserDefaults.standard.bool(forKey: DefaultsKey.notchHoverExpands) {
                    self.open(takeFocus: false)
                } else {
                    self.mutatePresentation(transitionContent: .reveal) { self.peeking = true }
                    self.provideHapticFeedback()
                }
            }
            hoverWork = work
            let delay = NotchSupport.sanitizedHoverDelay(UserDefaults.standard.double(forKey: DefaultsKey.notchHoverDelay))
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        } else if holdsNotification
                    || NotchSupport.closesOnPointerExit(expanded: expanded, peeking: peeking, openedByHover: openedByHover) {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.hoverWork = nil
                guard self.running, !self.suspended, !self.inside,
                      self.windowHost?.containsHover(NSEvent.mouseLocation) != true,
                      !self.pointerOverChildWindow(NSEvent.mouseLocation) else { return }
                self.releaseNotification()
                guard !self.pinned, !self.heldDrag, !self.keepsWorkingSurface, self.captureControls == nil,
                      !AssistiveKeyboard.ownsCocoaPoint(NSEvent.mouseLocation),
                      NotchSupport.closesOnPointerExit(expanded: self.expanded, peeking: self.peeking, openedByHover: self.openedByHover) else { return }
                self.collapse()
            }
            hoverWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + (expanded || noticeExpanded ? NotchQuickAccessLayout.hoverExitDelay : 0.12), execute: work)
        }
    }

    /// AppKit reports hover from the mouse moves it receives, and those can
    /// stop while the pointer crosses the transparent margin around the
    /// floating controls. One can even carry another window's coordinates.
    /// An exit can then arrive with the pointer still in that margin and be
    /// the last report. From such an exit until AppKit reports the pointer
    /// again, every move is checked here, so leaving still closes the island.
    /// The closed island's hover emphasis has the same gap, and worse: a fast
    /// pass up through the top edge to a display above can report its exit
    /// while the pointer still touches the island, or no exit at all. So while
    /// the emphasis shows or hover waits for an opening or reentry after an
    /// explicit close, moves are followed. A pointer at rest costs nothing.
    private func syncHoverExitMonitoring(entered: Bool, point: CGPoint) {
        // A timed capture stays attached to the closed island until its timer
        // ends, and each followed move would tell it the pointer left, which
        // restarts its dismissal under a pointer that came back to reopen it.
        let followsClosedHover = inside && !expanded && !peeking && notice == nil
            && (hoverWork?.isCancelled == false
                || hoverState.suppressed && UserDefaults.standard.bool(forKey: DefaultsKey.notchOpenOnHover))
        let watching = ((hoverEmphasized || followsClosedHover) && captureHover == nil
                || !entered && NotchSupport.closesOnPointerExit(expanded: expanded, peeking: peeking, openedByHover: openedByHover))
            && captureControls == nil && !pinned && !heldDrag && !hiddenUntilHover && !keepsWorkingSurface
            // Once watching, a pointer that leaves and slips back unreported is still seen.
            && (!hoverExitMonitors.isEmpty || windowHost?.containsHover(point) == true)
        guard watching else { removeHoverExitMonitors(); return }
        guard hoverExitMonitors.isEmpty else { return }
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let token = NSEvent.addGlobalMonitorForEvents(matching: moves, handler: { [weak self] _ in
            self?.hover(false)
        }) { hoverExitMonitors.append(token) }
        if let token = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { [weak self] event in
            self?.hover(false)
            return event
        }) { hoverExitMonitors.append(token) }
    }

    private func removeHoverExitMonitors() {
        hoverExitMonitors.forEach(NSEvent.removeMonitor)
        hoverExitMonitors.removeAll()
    }

    /// A mirrored banner the pointer can hold: on screen and not covered.
    /// Hidden mode keeps its notices out of reach, as the surface is not shown.
    private var holdsNotification: Bool {
        notice?.notificationID != nil && noticeCanPresent && !hiddenUntilHover
    }

    /// A mirrored banner waits under the pointer, as the native one does, and
    /// a deliberate hover opens its whole message in place.
    private func holdNotification(_ id: UUID) {
        noticeWork?.cancel(); noticeWork = nil
        guard !noticeExpanded, !hoverState.suppressed,
              UserDefaults.standard.bool(forKey: DefaultsKey.notchOpenOnHover) else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.hoverWork = nil
            guard self.running, !self.suspended, self.inside, !self.hoverState.suppressed, !self.pinned, !self.heldDrag,
                  !self.keepsWorkingSurface, self.holdsNotification, self.notice?.notificationID == id, !self.noticeExpanded,
                  UserDefaults.standard.bool(forKey: DefaultsKey.notchOpenOnHover),
                  self.geometry.contains(NSEvent.mouseLocation, in: self.surfaceSize) else { return }
            self.mutatePresentation(transitionContent: .reveal) { self.peeking = false; self.noticeExpanded = true }
            self.provideHapticFeedback()
        }
        hoverWork = work
        let delay = NotchSupport.sanitizedHoverDelay(UserDefaults.standard.double(forKey: DefaultsKey.notchHoverDelay))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Leaving closes an opened preview; a banner that was only held gets its
    /// full time again, so a quick pass over it never cuts it short.
    private func releaseNotification() {
        guard let notice, notice.notificationID != nil else { return }
        if noticeExpanded { dismissNotice() }
        else if noticeWork == nil { scheduleNoticeDismissal(after: notice.event.duration) }
    }

    private func syncNoticeWithPreferences() {
        guard let notice else { return }
        if !NotchSupport.routes(notice.event) || (notice.notificationID != nil && hiddenUntilHover) {
            dismissNotice()
        }
    }

    private func scheduleNoticeDismissal(after duration: TimeInterval) {
        noticeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismissNotice() }
        noticeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    var filteredSections: [NotchModule] {
        NotchSupport.filteredModules(modules, query: sectionQuery) { module in
            let language = L10n.shared.language
            let music = module == .music ? FeatureStrings.notch(language).music : ""
            return [module.title(language), module.rawValue, music].joined(separator: " ")
        }
    }

    func searchSections(_ query: String) {
        guard sectionQuery != query else { return }
        mutatePresentation {
            sectionQuery = query
            highlightedSection = filteredSections.first
        }
    }

    func toggleSections() {
        guard captureControls == nil, !heldDrag else { return }
        if showingSections {
            open(appPanel: showingAppPanel, metric: selectedMetric)
        } else {
            sectionQuery = ""
            // The gallery opens from its top, stepping only as far as the
            // current section's row.
            sectionRow = 0
            highlightedSection = selected
            open(appPanel: showingAppPanel, metric: selectedMetric, sections: true)
        }
    }

    private var sectionRowLimits: (rows: Int, visible: Int) {
        let count = filteredSections.count
        return (NotchSectionPaging.rows(count: count, columns: geometry.sectionColumns), geometry.sectionRows(count: count))
    }

    /// Keyboard moves and search results keep the highlighted tile's row in
    /// view, moving the gallery no further than that row needs.
    private func revealHighlightedSection() {
        guard let target = highlightedSection, let index = filteredSections.firstIndex(of: target) else { return }
        let limits = sectionRowLimits
        let row = NotchSectionPaging.revealing(row: index / max(1, geometry.sectionColumns), first: sectionRow,
                                               rows: limits.rows, visible: limits.visible)
        if row != sectionRow { sectionRow = row }
    }

    /// Rest the gallery on `row`, within the rows it has.
    func showSectionRow(_ row: Int) {
        let limits = sectionRowLimits
        let next = NotchSectionPaging.clamped(row, rows: limits.rows, visible: limits.visible)
        guard next != sectionRow else { return }
        sectionRow = next
        provideHapticFeedback()
    }

    func scrollSections(by rows: Int) { showSectionRow(sectionRow + rows) }

    private func handleSectionKey(_ event: NSEvent) -> Bool {
        guard showingSections,
              (panel?.firstResponder as? NSTextView)?.hasMarkedText() != true else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if event.keyCode == 48, modifiers.isEmpty || modifiers == .shift {
            highlightedSection = NotchSupport.adjacentModule(to: highlightedSection, modules: filteredSections,
                                                             backwards: modifiers == .shift)
            return true
        }
        guard modifiers.isEmpty else { return false }
        if event.keyCode == 36 || event.keyCode == 76 {
            if let target = highlightedSection, filteredSections.contains(target) { select(target) }
            return true
        }
        let direction: QuickToolsSupport.GridDirection
        switch event.keyCode {
        case 123 where sectionQuery.isEmpty: direction = .left
        case 124 where sectionQuery.isEmpty: direction = .right
        case 125: direction = .down
        case 126: direction = .up
        default: return false
        }
        let sections = filteredSections
        guard !sections.isEmpty else { return true }
        // While typing, the side arrows keep editing the query and the
        // vertical pair steps through the matches in order.
        guard sectionQuery.isEmpty else {
            highlightedSection = NotchSupport.adjacentModule(to: highlightedSection, modules: sections,
                                                             backwards: direction == .up)
            return true
        }
        let index = highlightedSection.flatMap { sections.firstIndex(of: $0) } ?? 0
        highlightedSection = sections[QuickToolsSupport.gridIndex(after: index, count: sections.count,
                                                                   flow: .rows(columns: geometry.sectionColumns),
                                                                   direction: direction)]
        return true
    }

    /// The floating pad's tab shortcuts work on its page too. With one pad
    /// left, Command-W closes the island the way it hides the pad.
    private func handleScratchpadKey(_ event: NSEvent) -> Bool {
        guard selected == .scratchpad, !showingAppPanel, !showingSections, selectedMetric == nil else { return false }
        let pad = ScratchpadService.shared
        let commandOnly = event.modifierFlags.intersection([.command, .control, .option]) == .command
        let shift = event.modifierFlags.contains(.shift)
        guard let action = ScratchpadFocusedShortcut.action(charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                                                               commandOnly: commandOnly,
                                                               shift: shift,
                                                               canCreatePad: pad.canCreatePad,
                                                               canClosePad: pad.canClosePad) else {
            // At the tab limit Command-T still belongs to the pad, not the text.
            return commandOnly && !shift && event.charactersIgnoringModifiers?.lowercased() == "t"
        }
        switch action {
        case .createPad: pad.createPad(defaultName: FeatureStrings.scratchpad(L10n.shared.language).pageTitle)
        case .closeSelectedPad: scratchpadCloseSerial += 1
        case .hidePad: collapse()
        case .find: requestScratchpadFind(.showFindInterface)
        case .findNext: requestScratchpadFind(.nextMatch)
        case .findPrevious: requestScratchpadFind(.previousMatch)
        }
        return true
    }

    /// The editor lives in the view, so the request goes out as a serial and
    /// the view reads which of the finder's actions it was for.
    private func requestScratchpadFind(_ action: NSTextFinder.Action) {
        scratchpadFindAction = action
        scratchpadFindSerial += 1
    }

    private func handleClipboardPasteKey(_ event: NSEvent) -> Bool {
        guard selected == .clipboard, !showingAppPanel, !showingSections, selectedMetric == nil else { return false }
        let commandOnly = event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command
        guard let index = NotchClipboardPastePress.index(keyCode: event.keyCode, commandOnly: commandOnly)
        else { return false }
        clipboardPastePress = NotchClipboardPastePress(serial: (clipboardPastePress?.serial ?? 0) &+ 1, index: index)
        return true
    }

    func activateQuickAction(_ action: NotchQuickAction) {
        guard NotchSupport.isEnabled(), action.isAvailable() else { return }
        switch action {
        case .explore: toggleSections()
        case .settings: openSettings()
        case .pin: pinned.toggle()
        case .module(let module): select(module)
        case .control(let item):
            switch item {
            case .keepAwake: KeepAwakeManager.shared.toggle()
            case .microphone: MicMuteService.shared.toggle()
            case .screenshot: perform { ScreenshotService.shared.capture() }
            case .recording: perform { ScreenRecorderService.shared.toggle() }
            case .speedTest: showMetric(.network)
            case .panel: openAppPanel()
            case .mixer: select(.mixer)
            case .music: select(.music)
            case .timer: select(.timer)
            case .calendar: select(.calendar)
            case .commandBar: perform { CommandBarService.shared.show() }
            case .scratchpad: openScratchpad()
            case .volume, .brightness: select(.controls)
            }
        }
    }

    func select(_ module: NotchModule) {
        guard modules.contains(module) else { return }
        open(module)
    }

    /// The pad lives in the island when its page is on; otherwise the
    /// shortcut opens the floating pad as it always did.
    func openScratchpad() {
        if !showScratchpad() { perform { ScratchpadService.shared.show() } }
    }

    @discardableResult
    func showScratchpad(toggle: Bool = false) -> Bool {
        guard NotchSupport.routesScratchpad(), acceptsUserInteraction else { return false }
        if toggle, expanded, selected == .scratchpad, !showingAppPanel, !showingSections, !showingCommandBar,
           selectedMetric == nil, panel?.isKeyWindow == true { collapse() }
        else { open(.scratchpad) }
        return true
    }

    func openAppPanel(toggle: Bool = false) {
        if toggle, expanded, showingAppPanel, !showingSections, !showingCommandBar { collapse(); return }
        MenuPanelFocus.shared.showNormalPanel()
        open(.controls, appPanel: true)
        // The toggling route is the menu bar's. Opened from there, the panel
        // has nothing behind it and closes on Escape, like the menu panel.
        if toggle { detailHasPage = false }
    }

    func openQuickPanel(toggle: Bool = false) -> Bool {
        guard NotchSupport.routesQuickPanel(), acceptsUserInteraction else { return false }
        if toggle, expanded, selected == .tools, !showingSections, !showingCommandBar { collapse() }
        else { open(.tools) }
        return true
    }

    func openShelf(toggle: Bool = false) -> Bool {
        guard NotchSupport.routesShelf(), acceptsUserInteraction else { return false }
        if toggle, expanded, selected == .files, !showingSections, !showingCommandBar { collapse() }
        else { open(.files) }
        return true
    }

    func showMetric(_ metric: MetricDetailKind, toggle: Bool = false) {
        guard metricIsAvailable(metric) else { return }
        if toggle, expanded, selectedMetric == metric, !showingSections, !showingCommandBar { collapse(); return }
        open(.system, metric: metric)
        // A metric opened from its menu bar item closes on Escape, like the popover.
        if toggle { detailHasPage = false }
    }

    /// Fan Control is a single card, so its detail fits the card instead of
    /// opening a tall, mostly empty page. A taller card still scrolls in it.
    func updateFanDetailHeight(_ height: CGFloat) {
        guard expanded, selectedMetric == .fan, !showingAppPanel, !showingSections,
              height.isFinite, height > 0 else { return }
        let measured = ceil(height)
        guard fanDetailHeight != measured else { return }
        fanDetailHeight = measured
        refreshPresentation()
    }

    func goBack() {
        let changesPresentation = selectedMetric != nil || showingAppPanel
        mutatePresentation(transitionContent: changesPresentation ? .replace : .none) { selectedMetric = nil; showingAppPanel = false }
        syncVisibleConsumers()
        if changesPresentation { provideHapticFeedback() }
    }

    /// Escape steps back one level: a detail returns to its page as the Back
    /// button does, a page closes the layer it shows, and the island closes
    /// once nothing lies behind.
    private func stepBack() {
        guard captureControls == nil, !heldDrag else { return }
        if showingAppPanel || selectedMetric != nil {
            if detailHasPage { goBack() } else { collapse() }
        } else if let close = pageLayers[selected] {
            close()
        } else {
            collapse()
        }
    }

    /// A page reports the layer it shows over its content with how to close
    /// it, and nil once the layer or the page is gone.
    func setPageLayer(_ module: NotchModule, close: (() -> Void)?) {
        pageLayers[module] = close
    }

    func provideHapticFeedback() {
        guard acceptsUserInteraction, panel?.isVisible == true, NotchSupport.usesHapticFeedback() else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }

    func fileDragChanged(_ active: Bool, internalDrag: Bool = false) {
        guard running, !suspended, internalDrag || NotchSupport.routesShelf() else { return }
        heldDrag = active && internalDrag
        if active, !internalDrag, NotchSupport.revealsShelfDrag(), !expanded {
            mutatePresentation { dragPlaceholder = true; peeking = false }
        } else if !active {
            mutatePresentation { dragPlaceholder = false }
            inside = windowHost?.containsHover(NSEvent.mouseLocation) == true
            if !inside, !pinned { hover(false) }
        }
        // The companion in the drop hint watches the file come.
        if active, dragPlaceholder, NotchMascotSupport.isEnabled() {
            NotificationCenter.default.post(name: .notchMascotDragMoved, object: nil)
        }
    }

    func presentCaptureControls(_ options: ScreenCaptureSelectionOptions, cancel: @escaping () -> Void) {
        guard acceptsSystemFeedback else { cancel(); return }
        let closeCapture = detachCaptureIfClosingOnCollapse()
        pinned = false
        captureControlsCancel = cancel
        captureControls = options
        // The controls wait compact around the camera, clear of what is being
        // captured, and open while the pointer rests on them.
        captureControlsCollapsed = true
        captureSelectionInProgress = false
        options.onSelectionProgressChange = { [weak self, weak options] active in
            guard let self, let options, self.captureControls === options else { return }
            self.setCaptureSelectionInProgress(active)
        }
        captureControlsSubscription = options.$selectedTool.dropFirst()
            .receive(on: DispatchQueue.main).sink { [weak self] _ in
                self?.objectWillChange.send()
                self?.refreshPresentation()
                self?.updateCaptureControlsClickThrough()
                self?.scheduleCaptureControlsCollapse()
            }
        // A Command Bar open in the island closes with it, or it would keep
        // the island's keys while the controls are up.
        let closesCommandBar = showingCommandBar
        showingCommandBar = false
        expanded = false
        showingSections = false
        peeking = false
        notice = nil
        noticeExpanded = false
        hoverWork?.cancel()
        if closesCommandBar { commandBarDidClose() }
        removeEventMonitors()
        panel?.acceptsKeyFocus = true
        panel?.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        refreshPresentation()
        // A pointer already resting there has not hovered them; it leaves and
        // comes back before they open.
        hoverState.close(pointerInside: windowHost?.containsHover(NSEvent.mouseLocation) == true)
        panel?.orderFrontRegardless()
        panel?.makeKey()
        installCaptureControlsClickThrough()
        syncVisibleConsumers()
        closeCapture?()
    }

    func collapseCaptureControls() {
        guard captureControls != nil else { return }
        captureControlsWork?.cancel(); captureControlsWork = nil
        hoverWork?.cancel(); hoverWork = nil
        hoverState.close(pointerInside: windowHost?.containsHover(NSEvent.mouseLocation) == true)
        captureControls?.hasFocusedControl = false
        captureControlsCollapsed = true
        refreshPresentation(animated: !captureSelectionInProgress)
        updateCaptureControlsClickThrough()
    }

    func expandCaptureControls() {
        guard captureControls != nil, !captureSelectionInProgress else { return }
        hoverWork?.cancel(); hoverWork = nil
        hoverState.open()
        captureControlsCollapsed = false
        refreshPresentation()
        panel?.makeKey()
        updateCaptureControlsClickThrough()
    }

    private func setCaptureSelectionInProgress(_ active: Bool) {
        guard captureControls != nil else { return }
        captureSelectionInProgress = active
        if active { collapseCaptureControls() }
        else {
            refreshPresentation()
            updateCaptureControlsClickThrough()
        }
    }

    /// Open controls close soon after the pointer leaves them. Opened with the
    /// pointer elsewhere, from the keyboard, they wait long enough for a
    /// control to take focus, which then keeps them open.
    func scheduleCaptureControlsCollapse(after delay: TimeInterval = 3) {
        captureControlsWork?.cancel(); captureControlsWork = nil
        guard let options = captureControls, !captureControlsCollapsed, !captureSelectionInProgress,
              !options.hasFocusedControl, !inside else { return }
        let work = DispatchWorkItem { [weak self, weak options] in
            guard let self, let options, self.captureControls === options else { return }
            self.captureControlsWork = nil
            guard !self.captureControlsCollapsed, !self.captureSelectionInProgress,
                  !options.hasFocusedControl, !self.trackingMenu,
                  self.panel?.attachedSheet == nil,
                  self.windowHost?.containsHover(NSEvent.mouseLocation) != true else { return }
            self.collapseCaptureControls()
        }
        captureControlsWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func updateCaptureControlsHover(wasInside: Bool) {
        guard let options = captureControls, !captureSelectionInProgress else { return }
        if !captureControlsCollapsed {
            if inside {
                captureControlsWork?.cancel(); captureControlsWork = nil
            } else if wasInside {
                // Leaving closes them, as it closes an island opened by hover.
                scheduleCaptureControlsCollapse(after: NotchQuickAccessLayout.hoverExitDelay)
            } else if captureControlsWork == nil {
                scheduleCaptureControlsCollapse()
            }
            return
        }
        if inside == wasInside, let hoverWork, !hoverWork.isCancelled { return }
        hoverWork?.cancel(); hoverWork = nil
        guard inside, !hoverState.suppressed else { return }
        let work = DispatchWorkItem { [weak self, weak options] in
            guard let self, let options, self.captureControls === options else { return }
            self.hoverWork = nil
            guard self.captureControlsCollapsed, !self.captureSelectionInProgress,
                  !self.hoverState.suppressed,
                  self.windowHost?.containsHover(NSEvent.mouseLocation) == true else { return }
            self.expandCaptureControls()
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    /// The capture-controls window covers the top center of the screen, over
    /// the selection surface. Only its visible controls should catch the
    /// mouse; everywhere else the click falls through to the selection beneath,
    /// so a region under the notch can still be dragged or a window clicked.
    private func updateCaptureControlsClickThrough() {
        guard let panel, captureControls != nil else { return }
        let point = NSEvent.mouseLocation
        // A collapsing animation still reserves the old window frame. Only
        // the compact target should own clicks while that space is released.
        let overControls = !captureSelectionInProgress && windowHost?.contains(point) == true
            && (!captureControlsCollapsed || windowHost?.containsHover(point) == true)
        windowHost?.setMouseEventsIgnored(!overControls)
        // While the panel catches the mouse it is the window under the pointer
        // across its whole frame, transparent parts included, so it must be the
        // one reporting the move that leaves the controls; otherwise the next
        // click there would be swallowed. Away from the controls the selection
        // surface reports every move itself, and the panel stays quiet.
        if panel.acceptsMouseMovedEvents != overControls { panel.acceptsMouseMovedEvents = overControls }
        hover(overControls)
    }

    private func installCaptureControlsClickThrough() {
        guard captureControlsMonitors.isEmpty else { return }
        // The selection surface below is this app's own window and already
        // tracks the pointer, so a local monitor sees every move that could
        // reach a control. A global monitor would add a second, system-wide
        // stream of every move at the mouse's full rate, and asking the key
        // panel for moved events on top of that starved the selector: with
        // both installed it received fewer events and trailed the pointer.
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged,
                                            .rightMouseDragged, .otherMouseDragged]
        if let token = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { [weak self] event in
            self?.updateCaptureControlsClickThrough(); return event
        }) { captureControlsMonitors.append(token) }
        updateCaptureControlsClickThrough()
    }

    private func removeCaptureControlsClickThrough() {
        captureControlsMonitors.forEach(NSEvent.removeMonitor)
        captureControlsMonitors.removeAll()
        windowHost?.setMouseEventsIgnored(false)
        panel?.acceptsMouseMovedEvents = false
    }

    private func missionControlDidRestore() {
        if captureControls != nil { updateCaptureControlsClickThrough() }
        else { hover(windowHost?.containsHover(NSEvent.mouseLocation) == true) }
        // A pointer that crossed displays during Mission Control is followed now.
        schedulePointerFollow()
    }

    func endCaptureControls() {
        guard captureControls != nil else { return }
        captureControlsWork?.cancel(); captureControlsWork = nil
        hoverWork?.cancel(); hoverWork = nil
        captureControls?.onSelectionProgressChange = nil
        geometry.compactSideRoom = nil
        captureControls = nil
        captureControlsCollapsed = false
        captureSelectionInProgress = false
        captureControlsSubscription = nil
        captureControlsCancel = nil
        removeCaptureControlsClickThrough()
        panel?.level = NotchPanel.normalLevel
        panel?.acceptsKeyFocus = false
        panel?.resignKey()
        refreshPresentation()
        syncVisibleConsumers()
    }

    func cancelCaptureControls() { captureControlsCancel?() }

    func openSettings() {
        collapse()
        SettingsRouter.shared.request(FeatureSettingsDestination(.notch))
        (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
    }

    /// Opens the Dynamic Island settings on one section's options.
    func openSettings(showing module: NotchModule) {
        SettingsRouter.shared.notchModule = module
        openSettings()
    }

    func perform(_ action: @escaping () -> Void) {
        collapse()
        if let windowHost { windowHost.whenSettled(action) }
        else { DispatchQueue.main.async(execute: action) }
    }

    var canAcceptFileDrop: Bool {
        acceptsUserInteraction && captureControls == nil && modules.contains(.files)
            && AppFeature.shelf.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.shelfEnabled)
    }

    func beginFileDrop(_ pasteboard: NSPasteboard) {
        guard canAcceptFileDrop else { return }
        choosingFileDropDestination = NotchFileToolsService.shared.mediaDropContent(for: pasteboard) != nil
        targetsMediaDrop = false
        open(.files, takeFocus: false)
    }

    @discardableResult
    func updateFileDrop(at point: CGPoint) -> Bool {
        let targeted = choosingFileDropDestination
            && NotchFileToolsSupport.mediaDropArea(in: expandedGeometry, size: surfaceSize).contains(point)
        if targetsMediaDrop != targeted { targetsMediaDrop = targeted }
        return !targeted || NotchFileToolsService.shared.canAcceptMediaDrop
    }

    func endFileDrop() {
        let changed = choosingFileDropDestination
        if changed { choosingFileDropDestination = false }
        if targetsMediaDrop { targetsMediaDrop = false }
        if changed, acceptsUserInteraction { refreshPresentation() }
    }

    func keepFileInteractionOpen(_ active: Bool) {
        fileInteractionActive = active
        hover(false)
    }

    func accept(_ pasteboard: NSPasteboard) -> Bool {
        defer { endFileDrop() }
        guard canAcceptFileDrop else { return false }
        let optimize = choosingFileDropDestination && targetsMediaDrop
        let accepted = optimize
            ? NotchFileToolsService.shared.openMediaDrop(pasteboard)
            : ShelfService.shared.acceptDrop(pasteboard: pasteboard)
        if accepted {
            heldDrag = false
            dragPlaceholder = false
            if !optimize { NotchFileToolsService.shared.hideMedia() }
            open(.files)
            // A little hop for the file it watched come in, once the island rests again.
            reactMascot(.celebrate, patience: 30)
        }
        return accepted
    }

    @discardableResult
    func show(_ incoming: NotchNotice) -> Bool {
        guard showsSystemFeedback, NotchSupport.routes(incoming.event),
              NotchSupport.shouldReplace(notice?.event, with: incoming.event, held: noticeExpanded) else { return false }
        noticeWork?.cancel(); noticeWork = nil
        var incoming = incoming
        if incoming.notification != nil, let shown = notice, shown.notification != nil, noticeCanPresent, !noticeExpanded {
            incoming.minimumWings = shown.wings(in: geometry)
        }
        let keepsPreview = noticeExpanded && incoming.notificationID != nil
            && windowHost?.containsHover(NSEvent.mouseLocation) == true
        // Slider and key bursts only replace the displayed value. They never
        // restart a window resize or enqueue another layout animation.
        let transition: NotchContentTransition = !noticeCanPresent ? .none
            : notice == nil ? .reveal : notice?.event != incoming.event || noticeExpanded ? .replace : .none
        let mascotFrom = mascotNoticeBridgeStart(for: incoming)
        // The same notice with a new reading only fits its width, steadily.
        noticeFitsInPlace = noticeCanPresent && !noticeExpanded && !keepsPreview && notice?.event == incoming.event
        mutatePresentation(transitionContent: transition) {
            notice = incoming
            noticeExpanded = keepsPreview
        }
        if let mascotFrom { bridgeMascotIntoNotice(incoming, from: mascotFrom) }
        // A banner arriving under the pointer is held at once, whether the
        // pointer was already inside or an opening was pending.
        if let id = incoming.notificationID, holdsNotification, windowHost?.containsHover(NSEvent.mouseLocation) == true {
            hoverWork?.cancel(); hoverWork = nil
            inside = true
            holdNotification(id)
        } else {
            scheduleNoticeDismissal(after: incoming.event.duration)
        }
        return true
    }

    func activateNotice(_ selectedNotice: NotchNotice) {
        guard notice == selectedNotice else { return }
        if let id = selectedNotice.notificationID {
            guard NotchNotificationService.shared.openingID == nil else { return }
            // The pointer stays where the banner was; like a click on the
            // island itself, this must not turn into a hover opening.
            settleNotificationHover()
            NotchNotificationService.shared.open(id) { [weak self] result in
                guard let self else { return }
                if self.notice?.notificationID == id { self.dismissNotice() }
                if result == .unavailable || result == .uncertain { self.open(.notifications) }
            }
            return
        }
        open(selectedNotice.event == .download ? .downloads : selectedNotice.event == .timer ? .timer
             : selectedNotice.event == .accessory ? .system : selectedNotice.event == .systemNotification ? .notifications
             : selectedNotice.event == .clipboard ? .clipboard : selectedNotice.event == .agents ? .agents
             : selectedNotice.event == .track ? .music : selectedNotice.event == .microphone ? .mixer
             : selectedNotice.event == .watch ? .watch : .controls)
    }

    /// Skipping through songs, or a title that lands before its artist, shows
    /// one notice for where playback settles. Until then the compact strip
    /// keeps the song it showed.
    private func scheduleTrackNotice() {
        trackWork?.cancel()
        if heldMusic == nil, let presentedMusic { heldMusic = presentedMusic }
        // With no song on the strip, as after a long gap between songs, the
        // new one waits too, so the notice is still where it first appears.
        if heldMusic == nil { awaitsTrackNotice = true }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.trackWork = nil
            // Released once the notice covers the strip, or when none can.
            defer { self.releaseTrackHold() }
            // The open island already shows the song, or holds something else
            // the person is doing.
            guard !self.expanded, !self.peeking, !self.dragPlaceholder, self.captureControls == nil,
                  let playback = NotchMusicService.shared.playback, playback.isPlaying,
                  let title = playback.track.title, !title.isEmpty else { return }
            self.show(NotchNotice(event: .track, title: title, detail: playback.track.artist ?? "",
                                  symbol: "music.note"))
        }
        trackWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// The reading that ends the song names nothing, another player's song or
    /// the next one paused. Held, the strip leaves as the song it showed, and
    /// its hiding ends the hold.
    private func holdEndingTrack() {
        if heldMusic == nil, let presentedMusic { heldMusic = presentedMusic }
    }

    /// The closed island turns to the live song. A song that waited for its
    /// notice appears now, unless a notice covers it, and the menu room is
    /// read again for the strip it brings.
    private func releaseTrackHold() {
        if heldMusic != nil { heldMusic = nil }
        guard awaitsTrackNotice else { return }
        awaitsTrackNotice = false
        syncMenuSpaceMonitoring()
        if notice == nil { refreshPresentation() }
    }

    func showBrightness(_ level: Double) -> Bool {
        let text = FeatureStrings.notch(L10n.shared.language)
        return show(NotchNotice(event: .brightness, title: text.brightness,
                                detail: "\(BrightnessSupport.wholePercent(level))%",
                                symbol: "sun.max.fill", level: level))
    }

    @discardableResult
    func showKeyboardLight(_ level: Double) -> Bool {
        guard level.isFinite, (0...1).contains(level) else { return false }
        return show(NotchNotice(event: .keyboardLight,
                                title: FeatureStrings.brightness(L10n.shared.language).keyboardLight,
                                detail: "\(BrightnessSupport.wholePercent(level))%",
                                symbol: "keyboard", level: level))
    }

    /// The microphone switch reports here the way the volume does: its mark
    /// on one side of the camera, what happened on the other. False leaves
    /// the confirmation to its own panel.
    @discardableResult
    func showMicrophone(muted: Bool) -> Bool {
        // Only the closed island draws this notice. While it is open or busy
        // the floating confirmation keeps the job.
        guard noticeCanPresent else { return false }
        let text = L10n.shared.s
        return show(NotchNotice(event: .microphone, title: "",
                                detail: muted ? text.micMutedHUD : text.micUnmutedHUD,
                                symbol: muted ? "mic.slash.fill" : "mic.fill", mascot: muted ? .hush : .perk))
    }

    /// A partial result is confirmed by the floating panel alone, so the
    /// notice left by the press before it must not contradict the warning.
    func retractMicrophoneNotice() {
        guard notice?.event == .microphone else { return }
        dismissNotice()
    }

    /// The close button of a held preview also takes the message out of the
    /// inbox, like the close button of the inbox row.
    func dismissNotification(_ selectedNotice: NotchNotice) {
        guard notice == selectedNotice, let id = selectedNotice.notificationID else { return }
        settleNotificationHover()
        NotchNotificationService.shared.dismiss(id)
        dismissNotice()
    }

    private func settleNotificationHover() {
        hoverWork?.cancel(); hoverWork = nil
        hoverState.close(pointerInside: windowHost?.containsHover(NSEvent.mouseLocation) == true)
    }

    private func dismissNotice() {
        noticeWork?.cancel(); noticeWork = nil
        endDeparture()
        let transition: NotchContentTransition = notice == nil || !noticeCanPresent ? .none
            : noticeExpanded ? .dismiss : .depart
        let departing = transition == .depart ? notice : nil
        let mascotBack = mascotNoticeBridgeBackStart(from: departing)
        mutatePresentation(transitionContent: transition) {
            departingNotice = departing
            notice = nil
            noticeExpanded = false
        }
        if let mascotBack { bridgeMascotHome(from: mascotBack) }
        guard departingNotice != nil else { return }
        // Without motion the host hides the content at once; so does the view.
        guard windowHost?.departsContent == true else { endDeparture(); return }
        let work = DispatchWorkItem { [weak self] in self?.endDeparture() }
        departureWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + NotchMotion.departureHidden, execute: work)
    }

    private func endDeparture() {
        departureWork?.cancel(); departureWork = nil
        guard departingNotice != nil else { return }
        departingNotice = nil
        windowHost?.finishDeparture()
    }

    private var noticeCanPresent: Bool {
        !expanded && !dragPlaceholder && captureControls == nil
    }

    func presentCapture(id: UUID, content: AnyView, actions: AnyView? = nil, height: CGFloat,
                        takeFocus: Bool, closeOnCollapse: Bool, fallback: @escaping () -> Void,
                        close: @escaping () -> Void, hover: @escaping (Bool) -> Void) -> Bool {
        guard acceptsSystemFeedback, NotchSupport.routes(.capture) else { return false }
        let keepOpen = expanded && pinned
        captureID = id
        captureContentHeight = height
        captureContent = content
        captureActions = actions
        captureFallback = fallback
        captureClose = close
        captureHover = hover
        captureClosesOnCollapse = closeOnCollapse
        open(.captures, pinned: keepOpen,
             takeFocus: takeFocus, feedback: false)
        captureHover?(inside)
        return true
    }

    func updateCaptureHeight(id: UUID, height: CGFloat) {
        guard captureID == id, captureContent != nil, height.isFinite, height > 0,
              captureContentHeight != height else { return }
        captureContentHeight = height
        refreshPresentation()
    }

    func isCaptureVisible(id: UUID) -> Bool {
        acceptsSystemFeedback && expanded && selected == .captures
            && !showingAppPanel && !showingSections && !showingCommandBar && selectedMetric == nil
            && captureControls == nil && captureID == id && captureContent != nil
    }

    func removeCapture(id: UUID) {
        guard captureID == id else { return }
        clearCapture()
        if expanded, selected == .captures, !showingSections, !showingCommandBar {
            if pinned { refreshPresentation() }
            else { collapse() }
        }
    }

    private func clearCapture() {
        captureID = nil
        captureContent = nil
        captureActions = nil
        captureContentHeight = nil
        captureFallback = nil
        captureClose = nil
        captureHover = nil
        captureClosesOnCollapse = false
    }

    /// Persistent captures must detach before their close callback runs so a
    /// replaced island surface cannot be collapsed again by that callback.
    /// Timed captures remain attached to their existing dismissal timer.
    private func detachCaptureIfClosingOnCollapse() -> (() -> Void)? {
        guard captureClosesOnCollapse else { return nil }
        let close = captureClose
        clearCapture()
        return close
    }

    private func mutatePresentation(transitionContent: NotchContentTransition = .none, _ change: () -> Void) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
        refreshPresentation(transitionContent: transitionContent)
    }

    private func finishMusicDeparture() {
        musicDepartureWork?.cancel(); musicDepartureWork = nil
        guard departingMusic != nil else { return }
        departingMusic = nil
        if windowHost?.departsContent == true { windowHost?.finishDeparture() }
    }

    private func compactMusicTransition(_ requested: NotchContentTransition, animated: Bool) -> NotchContentTransition {
        let musicVisible = compactMusicIsVisible
        let canKeepDeparting = !musicVisible && compactActivity == nil && !expanded && !peeking
            && notice == nil && !dragPlaceholder && captureControls == nil
        if departingMusic != nil {
            if canKeepDeparting && requested == .none && animated
                && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { return .none }
            musicDepartureWork?.cancel(); musicDepartureWork = nil
            departingMusic = nil
            // A new presentation must replace the departure's forward-filled mask.
            return requested == .none ? (animated ? .reveal : .replace) : requested
        }
        guard requested == .none, animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              panel?.isVisible == true, let presentedMusic, !musicVisible else { return requested }
        if canKeepDeparting {
            // A held track is the one on screen.
            departingMusic = heldMusic ?? presentedMusic
            return .depart
        }
        // Another compact activity took the same place as the disappearing track.
        return !expanded && !peeking && compactActivity != nil && notice == nil ? .replace : requested
    }

    private func rememberPresentedMusic(playback: NotchPlayback?, artwork: NSImage?, tint: NotchArtworkTint?) {
        guard compactMusicIsVisible, panel?.isVisible == true, let playback else {
            presentedMusic = nil
            // Whatever hid the strip ends the hold; it comes back with the live song.
            if heldMusic != nil { heldMusic = nil }
            return
        }
        presentedMusic = NotchCompactMusicSnapshot(playback: playback, artwork: artwork,
                                                  tint: tint, geometry: compactActivityGeometry)
    }

    func refreshPresentation(animated: Bool = true, transitionContent: NotchContentTransition = .none) {
        let fitsNoticeInPlace = noticeFitsInPlace && notice != nil && !noticeExpanded
        noticeFitsInPlace = false
        syncMascotKeepAwake()
        syncMascotAgents()
        activitySelection.reconcile(available: compactActivities)
        if fullscreenCompact {
            finishMusicDeparture()
            presentedMusic = nil
        }
        syncHiddenHoverMonitoring()
        // Closing, or a notice ending, can leave the island at rest away from
        // a pointer that has not moved since; it follows it then. The copies
        // on other displays follow what it shows closed.
        defer {
            schedulePointerFollow()
            syncMirrors()
            flushMascotReaction()
            mascotRestedInView = mascotRestsInView && !expanded
        }
        if hiddenUntilHover || (captureControls != nil && captureSelectionInProgress) {
            finishMusicDeparture()
            presentedMusic = nil
            // Hiding the strip ends a hold, as rememberPresentedMusic does, so
            // a song held as it ended never comes back over the next one.
            if heldMusic != nil { heldMusic = nil }
            if hiddenUntilHover { windowHost?.hide(animated: animated, transitionContent: transitionContent) }
            else { panel?.orderOut(nil) }
            removeScreenEdgeClickMonitors()
            return
        }
        let open = expanded || peeking || notice != nil || dragPlaceholder || captureControls != nil
        guard open || (!hiddenAtRestInFullscreen && (geometry.isNotched || geometry.compactSideRoom != nil)) else {
            finishMusicDeparture()
            presentedMusic = nil
            if heldMusic != nil { heldMusic = nil }
            windowHost?.hide(animated: animated, transitionContent: transitionContent)
            removeScreenEdgeClickMonitors()
            return
        }
        let access = NotchQuickAccessConfiguration.current()
        let size = surfaceSize
        let contentTransition = compactMusicTransition(transitionContent, animated: animated)
        if captureControls == nil {
            // A simulated cutout yields to the menu bar when it reappears in full screen.
            panel?.level = hiddenInFullscreen && !geometry.isNotched && !NotchSupport.coversMenus()
                ? NotchPanel.fullscreenLevel : NotchPanel.normalLevel
        }
        // Preferences can change computed dimensions without publishing a
        // service property. Update SwiftUI's layout along with the native host.
        if let windowHost, windowHost.targetSize != size { objectWillChange.send() }
        windowHost?.setOutline(enabled: !fullscreenCompact && UserDefaults.standard.bool(forKey: DefaultsKey.notchOutlineEnabled),
                               color: compactActivityIsVisible && compactActivity == .timer ? .systemOrange : .white)
        // Something else took the place the stand-in was headed for, as music
        // arriving while the island closes: it goes now rather than stand
        // over what came instead.
        if mascotBridging, !mascotBridgeTargetShows { endMascotBridgeNow(fading: true) }
        // An activity takes the companion's place at rest: it fades out ahead
        // of the strip coming in, unless it stays to react over the strip.
        if mascotRestedInView, compactActivity != nil, !mascotLingers,
           !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NotificationCenter.default.post(name: .notchMascotRestYields, object: nil)
        }
        var presented = expanded ? expandedGeometry : geometry
        presented.surfaceShift = surfaceShift
        windowHost?.present(size: size, geometry: presented, animated: animated,
                            transitionContent: contentTransition,
                            quickAccess: expanded && captureControls == nil && !showingCommandBar && !access.buttons.isEmpty
                                ? access : nil,
                            revealFromHidden: !hiddenInFullscreen && captureControls == nil
                                && UserDefaults.standard.bool(forKey: DefaultsKey.notchHideUntilHover)
                                && UserDefaults.standard.bool(forKey: DefaultsKey.notchOpenOnHover),
                            usesGlass: !fullscreenCompact && usesGlassSurface,
                            steady: fitsNoticeInPlace)
        // The selector lives in a separate full-screen panel. A floating
        // capsule may sit below the display edge, so publish the island's
        // actual bottom inset as the controls collapse or reopen.
        captureControls?.onCaptureControlsSurfaceChange?(
            geometry.screen, geometry.floatingDrop + size.height)
        // Closing can shrink the island away from a pointer that has not moved,
        // with no boundary crossing to report it. Only a pointer still over the
        // island may keep its next approach from opening it.
        if windowHost?.containsHover(NSEvent.mouseLocation) != true { hoverState.update(pointerInside: false) }
        let activationRect: CGRect
        if captureControls != nil {
            activationRect = captureControlsCollapsed ? CGRect(origin: .zero, size: size) : .zero
        } else if notice != nil || dragPlaceholder {
            activationRect = .zero
        } else if showsCompactActivityPicker {
            let strip = compactActivityGeometry.compactActivitySize
            activationRect = compactActivityGeometry.activationArea(
                in: strip, hasHeader: false, compactActivity: true)
                .offsetBy(dx: (size.width - strip.width) / 2, dy: 0)
        } else {
            activationRect = (expanded ? expandedGeometry : compactActivityIsVisible ? compactActivityGeometry : geometry)
                .activationArea(in: size, hasHeader: expanded || peeking, compactActivity: compactActivityIsVisible, expandedHeader: expanded)
        }
        let text = FeatureStrings.notch(L10n.shared.language)
        windowHost?.setActivationArea(activationRect, title: expanded ? text.collapse : text.open,
            willPress: { [weak self] in
                self?.hoverWork?.cancel()
                self?.hoverState.close(pointerInside: true)
            }, activate: { [weak self] in
                guard let self else { return }
                if self.captureControls != nil { self.expandCaptureControls() }
                else if !self.expanded, self.compactActivity == .calendar {
                    self.openCountdownEvent()
                } else { self.toggle() }
            })
        if panel?.isVisible != true { panel?.orderFrontRegardless() }
        let music = NotchMusicService.shared
        rememberPresentedMusic(playback: music.playback, artwork: music.artwork, tint: music.artworkTint)
        if contentTransition == .depart {
            if windowHost?.departsContent == true {
                let work = DispatchWorkItem { [weak self] in self?.finishMusicDeparture() }
                musicDepartureWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + NotchMotion.departureHidden, execute: work)
            } else { finishMusicDeparture() }
        }
        syncScreenEdgeClicks()
    }

    private func syncHiddenHoverMonitoring() {
        guard running, !suspended, hiddenUntilHover, windowHost != nil else {
            removeHiddenHoverMonitors()
            return
        }
        guard hiddenHoverMonitors.isEmpty else { return }
        // The window is ordered out, so native tracking areas cannot see entry.
        // Observe movement without intercepting the menu bar or polling at rest.
        if let token = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] _ in
            self?.hover(true)
        }) { hiddenHoverMonitors.append(token) }
        if let token = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] event in
            self?.hover(true)
            return event
        }) { hiddenHoverMonitors.append(token) }
    }

    private func removeHiddenHoverMonitors() {
        hiddenHoverMonitors.forEach(NSEvent.removeMonitor)
        hiddenHoverMonitors.removeAll()
    }

    /// Movement is watched only while the island can follow the pointer to
    /// another display, and each event only checks whether it left the
    /// island's display; nothing polls at rest.
    private func syncPointerFollowing() {
        guard running, !suspended, followsPointer, windowHost != nil, NSScreen.screens.count > 1 else {
            removePointerMonitors()
            return
        }
        guard pointerMonitors.isEmpty else { return }
        // A drag moves the pointer without mouse-moved events.
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let token = NSEvent.addGlobalMonitorForEvents(matching: moves, handler: { [weak self] _ in
            self?.schedulePointerFollow()
        }) { pointerMonitors.append(token) }
        if let token = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { [weak self] event in
            self?.schedulePointerFollow()
            return event
        }) { pointerMonitors.append(token) }
    }

    private func removePointerMonitors() {
        pointerMonitors.forEach(NSEvent.removeMonitor)
        pointerMonitors.removeAll()
        pointerFollowWork?.cancel(); pointerFollowWork = nil
    }

    /// Only a closed island moves. A file dragged toward it brings the drop
    /// area along, so the file can land on either display; an open page, a
    /// notice or a drag out of the island stays where it is.
    private var canFollowPointer: Bool {
        // A song held for its New track notice keeps its old display's geometry.
        !expanded && !peeking && notice == nil && captureControls == nil && !heldDrag
            && !choosingFileDropDestination && !keepsWorkingSurface && heldMusic == nil
    }

    private func schedulePointerFollow() {
        guard followsPointer, windowHost != nil else { return }
        guard !NSMouseInRect(NSEvent.mouseLocation, geometry.screen, false) else {
            pointerFollowWork?.cancel(); pointerFollowWork = nil
            return
        }
        guard pointerFollowWork == nil, canFollowPointer else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pointerFollowWork = nil
            // A closing island finishes on the display it closed on.
            self.windowHost?.whenSettled { [weak self] in self?.followPointer() }
        }
        pointerFollowWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pointerFollowDelay, execute: work)
    }

    private func followPointer() {
        // Mission Control spans the displays; the island moves once it is back.
        guard running, !suspended, followsPointer, canFollowPointer,
              windowHost?.isConcealedForMissionControl == false,
              let screen = NSScreen.withMouse, screen.notchDisplayID != displayID else { return }
        move(to: screen)
    }

    private func move(to screen: NSScreen) {
        displayID = screen.notchDisplayID
        updateScreen()
        // The menu space measured so far belongs to the display it left.
        invalidateMenuSpace()
        syncVisibleConsumers()
        refreshPresentation(animated: false)
    }

    /// A new song's title shows in the capsule for a few seconds, then the
    /// capsule keeps only the cover and the bars.
    private func nameCapsuleSong() {
        // The song held for the next one's notice is the one that ended; the
        // next song is named once the notice lets it go.
        guard heldMusic == nil else { return }
        musicTitleWork?.cancel()
        capsuleMusicTitleShown = true
        refreshCapsuleMusic()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.musicTitleWork = nil
            self.capsuleMusicTitleShown = false
            self.refreshCapsuleMusic()
        }
        musicTitleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.musicTitleDuration, execute: work)
    }

    /// A capsule is as wide as what it shows of the song, here or on another display.
    private func refreshCapsuleMusic() {
        guard compactActivity == .music,
              geometry.floats || mirrors.values.contains(where: { $0.model.geometry.floats }) else { return }
        refreshPresentation()
    }

    // MARK: Every display

    /// The closed island as another display draws it, in a window of its own.
    private struct NotchMirror {
        let host: NotchWindowHost
        let model: NotchMirrorModel
    }

    /// With the island on every display, it follows the pointer as it does
    /// when it only follows it, and each other display shows a copy of what
    /// it shows closed. The copies are drawn for their own displays, a
    /// capsule or a notch, and they take no part in hovering or notices.
    private func syncMirrors() {
        guard showsOnAllDisplays, running, !suspended, windowHost != nil else { closeMirrors(); return }
        let screens = NSScreen.screens
        for (id, mirror) in mirrors where !screens.contains(where: { $0.notchDisplayID == id }) {
            mirror.host.close()
            mirrors[id] = nil
        }
        // An island hidden until the pointer reaches it hides its copies as well.
        let hidesAtRest = NotchSupport.hidesUntilHover()
        let outline = UserDefaults.standard.bool(forKey: DefaultsKey.notchOutlineEnabled)
        let activity = compactActivity
        for screen in screens {
            let id = screen.notchDisplayID
            var base: NotchGeometry?
            if id != displayID, !hidesAtRest, !fullscreenDisplays.contains(id) {
                var geometry = baseGeometry(for: screen)
                geometry.compactSideRoom = mirrorSideRoom(on: screen, geometry: geometry)
                // A simulated island needs the menus' room at rest, as the island does.
                if geometry.isNotched || geometry.compactSideRoom != nil { base = geometry }
            }
            guard let base else {
                if let mirror = mirrors[id], mirror.model.shown {
                    mirror.model.shown = false
                    mirror.host.hide(animated: false)
                }
                continue
            }
            let (strip, size) = mirrorSurface(on: base, activity: activity)
            let mirror = mirrors[id] ?? makeMirror(geometry: base, size: size)
            mirrors[id] = mirror
            if mirror.model.outline != outline || mirror.model.timerOutline != (activity == .timer) {
                mirror.model.outline = outline
                mirror.model.timerOutline = activity == .timer
                mirror.host.setOutline(enabled: outline, color: activity == .timer ? .systemOrange : .white)
            }
            let sharing: NSWindow.SharingType = NotchSupport.showsInCaptures() ? .readOnly : .none
            if mirror.host.panel.sharingType != sharing { mirror.host.panel.sharingType = sharing }
            let revealing = !mirror.model.shown
            let previous = mirror.model.activity
            guard mirror.model.update(geometry: base, strip: strip, size: size, activity: activity) || revealing else { continue }
            mirror.model.shown = true
            // Shown at once where the island just left, so the two trade places.
            mirror.host.present(size: size, geometry: base, animated: !revealing,
                                transitionContent: !revealing && previous != activity ? .replace : .none)
            mirror.host.setActivationArea(CGRect(origin: .zero, size: size),
                                          title: FeatureStrings.notch(L10n.shared.language).open,
                                          willPress: {}, activate: { [weak self] in self?.bringIsland(to: id) })
            if !mirror.host.panel.isVisible { mirror.host.panel.orderFrontRegardless() }
        }
    }

    /// A copy's closed surface: the strip of what the island shows, drawn
    /// for that display, or the island at rest there.
    private func mirrorSurface(on base: NotchGeometry, activity: NotchCompactActivity?) -> (strip: NotchGeometry, size: CGSize) {
        guard let activity else {
            return (base, base.restingSize(showsContent: !base.floats && (idleContent != .none || mascotShows(on: base))))
        }
        let companion = compactCompanion
        if base.floats { return (base, capsuleStripSize(for: activity, companion: companion, geometry: base)) }
        let strip = compactGeometry(for: activity, companion: companion, base: base)
        return (strip, strip.compactActivitySize)
    }

    /// Another display's menus are never measured. A copy covers them when
    /// the island may, or where there are none, and otherwise gives way.
    private func mirrorSideRoom(on screen: NSScreen, geometry: NotchGeometry) -> CGFloat? {
        let hasMenuBar = NSScreen.screensHaveSeparateSpaces || NSScreen.withMenuBar == screen
        guard NotchSupport.coversMenus() || !hasMenuBar else { return nil }
        return NotchMenuBarLayout.sideRoom(screen: geometry.screen, cameraWidth: geometry.cameraWidth,
                                           barHeight: geometry.menuBarHeight, occupied: [])
    }

    private func makeMirror(geometry: NotchGeometry, size: CGSize) -> NotchMirror {
        let model = NotchMirrorModel(geometry: geometry, size: size)
        let host = NotchWindowHost(content: AnyView(NotchMirrorView(service: self, mirror: model)),
                                   geometry: geometry, size: size,
                                   background: { AnyView(NotchWindowBackground(presentation: $0)) })
        host.panel.title = FeatureStrings.notch(L10n.shared.language).title
        return NotchMirror(host: host, model: model)
    }

    private func closeMirrors() {
        guard !mirrors.isEmpty else { return }
        mirrors.values.forEach { $0.host.close() }
        mirrors.removeAll()
    }

    /// Whether another display shows a copy of the closed island now.
    private var showsCopies: Bool { mirrors.values.contains { $0.model.shown } }

    /// Only the copies ask which displays are in full screen, and only when
    /// the island hides there; the island asks for its own display.
    private func updateFullscreenDisplays() {
        guard showsOnAllDisplays, UserDefaults.standard.bool(forKey: DefaultsKey.notchHideInFullscreen),
              let topology = SpaceWindowBridge.topology() else { fullscreenDisplays = []; return }
        let separate = NSScreen.screensHaveSeparateSpaces
        fullscreenDisplays = Set(NSScreen.screens.map(\.notchDisplayID).filter {
            topology.isFullscreen(on: $0, separateSpaces: separate)
        })
    }

    /// A click on a copy brings the island to its display, open, closing it
    /// on the display it was open on.
    private func bringIsland(to id: CGDirectDisplayID) {
        guard running, !suspended, showsOnAllDisplays, id != displayID else { return }
        if expanded || peeking { collapse() }
        windowHost?.whenSettled { [weak self] in
            guard let self, self.running, !self.suspended, self.canFollowPointer,
                  let screen = NSScreen.screens.first(where: { $0.notchDisplayID == id }) else { return }
            self.move(to: screen)
            if self.compactActivity == .calendar { self.openCountdownEvent() } else { self.open() }
        }
    }

    private var screenEdgeClickArea: CGRect? {
        guard running, !suspended, !expanded, captureControls == nil, notice == nil,
              !dragPlaceholder, !heldDrag, let panel, panel.isVisible, !panel.ignoresMouseEvents else { return nil }
        let geometry = compactActivityIsVisible ? compactActivityGeometry : self.geometry
        let area = geometry.activationArea(in: surfaceSize, hasHeader: peeking, compactActivity: compactActivityIsVisible)
        guard !area.isEmpty else { return nil }
        let frame = geometry.frame(for: surfaceSize)
        return CGRect(x: frame.minX + area.minX, y: frame.maxY - area.maxY, width: area.width, height: area.height)
    }

    private func syncScreenEdgeClicks() {
        guard screenEdgeClickArea != nil else { removeScreenEdgeClickMonitors(); return }
        guard screenEdgeClickMonitors.isEmpty else { return }
        // The menu bar owns the first screen row even above its window level.
        // Observe only mouse clicks, with no event tap or Accessibility requirement.
        let events: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp, .leftMouseDragged]
        if let token = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] event in
            self?.handleScreenEdgeEvent(event)
        }) { screenEdgeClickMonitors.append(token) }
        if let token = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            self?.handleScreenEdgeEvent(event)
            return event
        }) { screenEdgeClickMonitors.append(token) }
    }

    private func handleScreenEdgeEvent(_ event: NSEvent) {
        guard event.type == .leftMouseDown || screenEdgePressArea != nil else { return }
        guard let location = event.cgEvent?.location, let primary = NSScreen.withMenuBar else {
            screenEdgePressArea = nil
            return
        }
        handleScreenEdgeClick(event.type, at: CGPoint(x: location.x, y: primary.frame.maxY - location.y),
                              isNotchWindow: event.window === panel)
    }

    private func handleScreenEdgeClick(_ type: NSEvent.EventType, at point: CGPoint, isNotchWindow: Bool) {
        guard let area = screenEdgeClickArea else { screenEdgePressArea = nil; return }
        let local = CGPoint(x: point.x - area.minX, y: area.maxY - point.y)
        switch type {
        case .leftMouseDown:
            screenEdgePressArea = nil
            // The menu bar a capsule leaves above itself takes its clicks too.
            guard !isNotchWindow, !keepsWorkingSurface,
                  CGRect(x: 0, y: 0, width: area.width, height: 1 + (geometry.floatingGap ?? 0)).contains(local),
                  windowHost?.containsDestination(point) == true else { return }
            screenEdgePressArea = area
            hoverWork?.cancel(); hoverWork = nil
            hoverState.close(pointerInside: true)
        case .leftMouseUp:
            let pressedArea = screenEdgePressArea
            screenEdgePressArea = nil
            // The hover pulse can settle between press and release; the click
            // stays on the island in either size.
            guard let pressed = pressedArea,
                  NotchSupport.screenEdgeArea(pressed, contains: point) || NotchSupport.screenEdgeArea(area, contains: point),
                  windowHost?.containsDestination(point) == true else { return }
            if compactActivity == .calendar { openCountdownEvent() } else { open() }
        case .leftMouseDragged:
            // A press at the screen's edge reports a drag at once, often without
            // moving. Only a drag that leaves the island cancels the click.
            guard !NotchSupport.screenEdgeArea(area, contains: point),
                  !(screenEdgePressArea.map { NotchSupport.screenEdgeArea($0, contains: point) } ?? false) else { return }
            screenEdgePressArea = nil
        default:
            break
        }
    }

    private func removeScreenEdgeClickMonitors() {
        screenEdgeClickMonitors.forEach(NSEvent.removeMonitor)
        screenEdgeClickMonitors.removeAll()
        screenEdgePressArea = nil
    }

    private func stopMenuSpaceMonitoring() {
        menuSpaceTimer?.invalidate()
        menuSpaceTimer = nil
        menuSpaceGeneration += 1
    }

    /// Displays that share Spaces show the menu bar on the main one only.
    private var displayHasMenuBar: Bool {
        NSScreen.screensHaveSeparateSpaces || NSScreen.withMenuBar?.frame == geometry.screen
    }

    private func syncMenuSpaceMonitoring() {
        guard !hiddenInFullscreen else { stopMenuSpaceMonitoring(); return }
        // The explicit cover-menus choice also keeps a simulated island at
        // rest. Otherwise its visibility follows AX menu measurements, which
        // can change just because focus moves to another app or display.
        // A display without a menu bar, beside the main one when displays
        // share Spaces, has no menus to leave room for either.
        if running, !suspended, NotchSupport.coversMenus() || !displayHasMenuBar {
            // Nothing to measure: the island keeps the room an empty bar
            // would leave it, over whatever menus and status items are there.
            stopMenuSpaceMonitoring()
            applyMenuSpace(NotchMenuBarLayout.sideRoom(screen: geometry.screen, cameraWidth: geometry.cameraWidth,
                                                       barHeight: geometry.menuBarHeight, occupied: []))
            return
        }
        guard AXIsProcessTrusted() else {
            stopMenuSpaceMonitoring()
            if geometry.compactSideRoom != nil {
                geometry.compactSideRoom = nil
                refreshPresentation(animated: false)
            }
            return
        }
        let wanted = running && !suspended && !hiddenUntilHover && !expanded && captureControls == nil
            && (idleContent != .none || compactActivity != nil || !geometry.isNotched || mascotWantsRoom)
        guard wanted else { stopMenuSpaceMonitoring(); return }
        guard menuSpaceTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.readMenuSpace() }
        timer.tolerance = 0.2
        menuSpaceTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        readMenuSpace()
    }

    private func invalidateMenuSpace() {
        menuSpaceGeneration += 1
        // Keep the last measured layout until its replacement arrives, so a
        // switch does not blink; the read that follows withdraws the cutout
        // once the new menu bar reaches the camera.
        readMenuSpace()
    }

    private func screenParametersDidChange() {
        guard running, !suspended else { return }
        screenRefreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.screenRefreshWork = nil
            guard self.running, !self.suspended else { return }
            self.invalidateMenuSpace()
            self.syncWithPreferences()
        }
        screenRefreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    private func readMenuSpace() {
        // The displayed menus belong to the menu bar's owner, which is not the
        // frontmost application while an accessory app such as a launcher has
        // focus; that app's own menu geometry was never laid out. When our own
        // Settings has focus, the menu owner can briefly be nil.
        guard menuSpaceTimer != nil, !menuSpaceReading,
              let pid = NSWorkspace.shared.menuBarOwningApplication?.processIdentifier
                ?? (NSApp.isActive ? getpid() : nil) else { return }
        menuSpaceReading = true
        let generation = menuSpaceGeneration
        let geometry = geometry
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? geometry.screen.maxY
        let window = panel?.windowNumber ?? -1
        menuSpaceQueue.async { [weak self] in
            let room = NotchMenuBarSpace.measure(pid: pid, geometry: geometry,
                                                primaryTop: primaryTop, ownWindow: window)
            DispatchQueue.main.async {
                guard let self else { return }
                self.menuSpaceReading = false
                guard self.menuSpaceTimer != nil else { return }
                guard self.menuSpaceGeneration == generation,
                      (NSWorkspace.shared.menuBarOwningApplication?.processIdentifier
                        ?? (NSApp.isActive ? getpid() : nil)) == pid else {
                    self.readMenuSpace(); return
                }
                self.applyMenuSpace(room)
            }
        }
    }

    private func applyMenuSpace(_ room: CGFloat?) {
        guard geometry.compactSideRoom != room else { return }
        let previousSize = surfaceSize
        let grows = (room ?? 0) > (geometry.compactSideRoom ?? 0)
        geometry.compactSideRoom = room
        // Losing a safe center must also hide an unchanged bare cutout.
        if previousSize != surfaceSize || panel?.isVisible != true || room == nil {
            refreshPresentation(animated: grows)
        }
    }

    /// Only a laptop reports its lid, and only a laptop can lose its
    /// built-in screen while it keeps running.
    private static let hasLid = BrightnessService.lidClosed() != nil

    private var displayPreference: NotchDisplay {
        NotchDisplay(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.notchDisplay) ?? "") ?? .automatic
    }

    private func screenIndex(in screens: [NSScreen]) -> Int? {
        let preference = displayPreference
        var pointer: Int?
        if preference == .pointer || preference == .all {
            // The island stays on its display until it can follow the pointer.
            let mouse = NSEvent.mouseLocation
            pointer = screens.firstIndex { $0.notchDisplayID == displayID }
                ?? screens.firstIndex { NSMouseInRect(mouse, $0.frame, false) }
        }
        return NotchSupport.screenIndex(
            preference: preference,
            builtIn: screens.map { CGDisplayIsBuiltin($0.notchDisplayID) != 0 },
            notched: screens.map { $0.safeAreaInsets.top > 0 },
            main: screens.firstIndex(where: { $0 === NSScreen.withMenuBar }) ?? 0,
            pointer: pointer,
            hasLid: Self.hasLid)
    }

    /// With the chosen display away, as the built-in one with the lid closed,
    /// nothing keeps working for an island that cannot show. The Mac is still
    /// in use elsewhere, so a capture preview moves to its own window, and a
    /// finished timer waits to ring until the island can be dismissed again.
    private func withdrawFromMissingScreen() {
        let cancelCapture = captureControlsCancel
        endCaptureControls()
        cancelCapture?()
        let fallback = captureFallback
        clearCapture()
        tearDownPresentation()
        NotchTimerService.shared.suspend()
        // The keys go back to the system while nothing can show them.
        if AppFeature.mixer.isAvailable { PreciseVolumeRollerService.shared.syncWithPreferences() }
        if AppFeature.brightness.isAvailable { BrightnessService.shared.syncWithPreferences() }
        fallback?()
    }

    private func updateScreen() {
        let screens = NSScreen.screens
        menuBarMeasurements.retainDisplays(screens.map(\.notchDisplayID))
        guard let index = screenIndex(in: screens) else { withdrawFromMissingScreen(); return }
        let screen = screens[index]
        displayID = screen.notchDisplayID
        var next = baseGeometry(for: screen)
        let sameMenuBar = next.hasSameMenuBar(as: geometry)
        if sameMenuBar { next.compactSideRoom = geometry.compactSideRoom }
        let access = NotchQuickAccessConfiguration.current()
        next.quickAccessBottomInset = access.hasBottom ? NotchQuickAccessLayout.gutter : 0
        headerShowsSectionsButton = !access.actions.contains(.explore)
        if next != geometry { menuSpaceGeneration += 1; geometry = next }
        // A new camera or bar, such as a notch fit being adjusted, measures the
        // menus again at once rather than leaving the wings off until the timer.
        if !sameMenuBar { readMenuSpace() }
        if windowHost == nil {
            windowHost = NotchWindowHost(content: AnyView(NotchView(service: self)), geometry: geometry, size: surfaceSize,
                                        background: { AnyView(NotchWindowBackground(presentation: $0)) },
                                        quickAccess: { AnyView(NotchQuickAccessView(service: self, motion: $0, backdrop: $1)) })
            windowHost?.missionControlDidRestore = { [weak self] in self?.missionControlDidRestore() }
            windowHost?.setHoverHandler { [weak self] in self?.hover($0) }
            panel?.title = FeatureStrings.notch(L10n.shared.language).title
        }
        if modules.contains(.files), AppFeature.shelf.isAvailable {
            windowHost?.setFileDropActions(NotchFileDropActions(
                canAccept: { [weak self] pasteboard in
                    self?.canAcceptFileDrop == true && !ShelfService.shared.isInternalDragActive
                        && ShelfService.shared.canAcceptPasteboard(pasteboard)
                },
                enter: { [weak self] in self?.beginFileDrop($0) },
                accept: { [weak self] in self?.accept($0) == true },
                exit: { [weak self] in
                    guard let self else { return }
                    self.endFileDrop()
                    self.hover(self.windowHost?.contains(NSEvent.mouseLocation) == true)
                },
                update: { [weak self] in self?.updateFileDrop(at: $0) == true }))
        } else { windowHost?.setFileDropActions(nil) }
        panel?.sharingType = NotchSupport.showsInCaptures() ? .readOnly : .none
        updateFullscreenVisibility(displayID: screen.notchDisplayID)
    }

    /// The island's geometry on a display, before its menus are measured.
    private func baseGeometry(for screen: NSScreen) -> NotchGeometry {
        let cameraWidth: CGFloat
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            cameraWidth = max(0, right.minX - left.maxX)
        } else { cameraWidth = 0 }
        return NotchGeometry(screen: screen.frame, safeAreaTop: screen.safeAreaInsets.top,
                             cameraWidth: cameraWidth,
                             layout: NotchSize(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.notchSize) ?? "") ?? .spacious,
                             menuBarHeight: menuBarMeasurements.height(
                                displayID: screen.notchDisplayID, frame: screen.frame,
                                visibleTop: screen.visibleFrame.maxY, scale: screen.backingScaleFactor,
                                statusBarThickness: NSStatusBar.system.thickness),
                             customWidth: UserDefaults.standard.double(forKey: DefaultsKey.notchCustomWidth),
                             customHeight: UserDefaults.standard.double(forKey: DefaultsKey.notchCustomHeight),
                             cameraFit: NotchCameraFit.current(), silhouette: NotchSilhouette.current(),
                             capsuleFit: NotchCapsuleFit.current(),
                             outline: UserDefaults.standard.bool(forKey: DefaultsKey.notchOutlineEnabled))
    }

    private func updateFullscreenVisibility(displayID: CGDirectDisplayID) {
        let hidden = UserDefaults.standard.bool(forKey: DefaultsKey.notchHideInFullscreen)
            && SpaceWindowBridge.topology()?.isFullscreen(on: displayID, separateSpaces: NSScreen.screensHaveSeparateSpaces) == true
        guard hidden != hiddenInFullscreen else { return }
        hiddenInFullscreen = hidden
        if hidden {
            hoverWork?.cancel(); hoverWork = nil
            hoverEmphasized = false
            heldDrag = false
            dragPlaceholder = false
            cancelCaptureControls()
            noticeWork?.cancel(); noticeWork = nil
            endDeparture()
            notice = nil
            noticeExpanded = false
            collapse()
        }
        // Space changes do not run a full preference sync. Restore volume
        // and brightness key routing when the island becomes eligible for
        // feedback again, and hand the keys back while it is away.
        if AppFeature.mixer.isAvailable { PreciseVolumeRollerService.shared.syncWithPreferences() }
        if AppFeature.brightness.isAvailable { BrightnessService.shared.syncWithPreferences() }
    }

    private func fullscreenEnvironmentDidChange() {
        // Only the opt-in option depends on Spaces and the active app.
        guard running, !suspended,
              hiddenInFullscreen || UserDefaults.standard.bool(forKey: DefaultsKey.notchHideInFullscreen)
        else { return }
        let wasHidden = hiddenInFullscreen
        updateScreen()
        // Each copy follows full screen on its own display.
        updateFullscreenDisplays()
        syncMirrors()
        // An unchanged state must not cut short a transition on screen, such
        // as the island closing after a click in another app.
        guard hiddenInFullscreen != wasHidden else { return }
        syncVisibleConsumers()
        refreshPresentation(animated: false)
    }

    private func installObservers() {
        observe(.default, NSMenu.didBeginTrackingNotification) { [weak self] in
            guard let self else { return }
            self.activityPickerMenuOpen = self.showsCompactActivityPicker
            self.trackingMenu = true
            self.hoverWork?.cancel()
        }
        observe(.default, NSMenu.didEndTrackingNotification) { [weak self] in
            guard let self else { return }
            self.trackingMenu = false
            self.activityPickerMenuOpen = false
            self.hover(self.windowHost?.contains(NSEvent.mouseLocation) == true)
            self.refreshPresentation()
        }
        observe(.default, NSApplication.didChangeScreenParametersNotification) { [weak self] in
            self?.screenParametersDidChange()
        }
        observe(.default, UserDefaults.didChangeNotification) { [weak self] in
            self?.schedulePreferenceSync()
        }
        observe(.default, .menuPanelWillShow) { [weak self] in self?.collapse() }
        observe(.default, NSWindow.didBecomeKeyNotification) { [weak self] in self?.syncPanelKey() }
        observe(.default, NSWindow.didResignKeyNotification) { [weak self] in self?.syncPanelKey() }
        session.onConsole = SessionActivity.shared.isActive
        session.locked = (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.accessibilityDisplayOptionsDidChangeNotification) { [weak self] in
            self?.schedulePreferenceSync()
        }
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { [weak self] in
            self?.fullscreenEnvironmentDidChange()
        }
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { [weak self] in self?.applicationDidActivate() }
        observe(workspace, NSWorkspace.willSleepNotification) { [weak self] in
            self?.updateSession { $0.sleeping = true }
        }
        observe(workspace, NSWorkspace.didWakeNotification) { [weak self] in
            // Sleep ends a screen saver even when its stop goes unannounced.
            self?.updateSession { $0.sleeping = false; $0.screenSaverRunning = false }
        }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { [weak self] in
            self?.updateSession { $0.displaysSleeping = true }
        }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { [weak self] in
            self?.updateSession { $0.displaysSleeping = false }
        }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { [weak self] in
            self?.updateSession { $0.onConsole = false }
        }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] in
            self?.updateSession { $0.onConsole = true }
        }
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { [weak self] in
            self?.updateSession { $0.locked = true }
        }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { [weak self] in
            // No screen saver outlasts an unlock, whether or not its stop was announced.
            self?.updateSession { $0.locked = false; $0.screenSaverRunning = false }
            // It slept through the lock and wakes up glad to see you.
            self?.reactMascot(.wakeUp)
        }
        observe(distributed, Notification.Name("com.apple.screensaver.didstart")) { [weak self] in
            self?.updateSession { $0.screenSaverRunning = true }
        }
        observe(distributed, Notification.Name("com.apple.screensaver.didstop")) { [weak self] in
            self?.updateSession { $0.screenSaverRunning = false }
        }
    }

    /// AppStorage can notify during drawing. A preference import or a group
    /// of edits only needs one deferred pass over the final saved settings.
    private func schedulePreferenceSync() {
        guard running, preferenceSyncWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.preferenceSyncWork = nil
            guard self.running else { return }
            self.syncWithPreferences()
        }
        preferenceSyncWork = work
        DispatchQueue.main.async(execute: work)
    }

    private func applicationDidActivate() {
        guard !suspended else { return }
        fullscreenEnvironmentDidChange()
        invalidateMenuSpace()
        let identifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard identifier != Bundle.main.bundleIdentifier, identifier != AssistiveKeyboard.bundleID else { return }
        panel?.resignKey()
        if expanded, modules.contains(.clipboard) { ClipboardHistoryService.shared.rememberPasteTarget() }
        if expanded, !pinned, !keepsWorkingSurface, captureControls == nil,
           NotchSupport.closesOnActivation(openedByHover: openedByHover, clicked: clickedSinceOpening,
                                           pointerInside: windowHost?.containsHover(NSEvent.mouseLocation) == true) {
            collapse()
        }
    }

    private func syncPanelKey() {
        let isKey = panel?.isKeyWindow == true
        if panelIsKey != isKey { panelIsKey = isKey }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         action: @escaping () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in action() }
        observers.append((center, token))
    }

    private func updateSession(_ change: (inout NotchSessionState) -> Void) {
        guard running else { return }
        let couldPresent = session.canPresent
        let timerCouldRun = session.canRunTimer
        let wasLocked = session.locked
        change(&session)
        // An unlock is someone at the Mac, even when the display's wake is
        // announced after it.
        if session.locked != wasLocked, session.locked ? session.hearsLockChange : session.onConsole,
           NotchLockScreenSupport.playsSounds() {
            NotchLockScreenService.shared.playSound(locking: session.locked)
        }
        // The lock screen starts leaving before the island comes back, since
        // rebuilding the island holds the main thread for a moment. It stops
        // none of the sources an island that returns takes back.
        if wasLocked, !session.locked { NotchLockScreenService.shared.sync(session) }
        if couldPresent != session.canPresent {
            if session.canPresent {
                syncWithPreferences()
            } else {
                let cancel = captureControlsCancel
                endCaptureControls()
                cancel?()
                captureClose?()
                clearCapture()
                tearDownPresentation()
                // The keys go back to the system while nothing can show them.
                if AppFeature.mixer.isAvailable { PreciseVolumeRollerService.shared.syncWithPreferences() }
                if AppFeature.brightness.isAvailable { BrightnessService.shared.syncWithPreferences() }
            }
        }
        // After the island's own teardown or return: what the lock screen
        // starts is not stopped under it, and what the island takes back is
        // not stopped as the lock screen leaves.
        NotchLockScreenService.shared.sync(session)
        // A dark display does not stop an alarm while the same user and Mac
        // remain awake. Privacy changes still apply when presentation is
        // already suspended by the display.
        guard timerCouldRun != session.canRunTimer, !session.canPresent else { return }
        if session.canRunTimer { NotchTimerService.shared.syncWithPreferences() }
        else { NotchTimerService.shared.suspend() }
    }

    private func installEventMonitors() {
        guard eventMonitors.isEmpty else { return }
        clickedSinceOpening = false
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let token = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            guard let self, !self.keepsWorkingSurface,
                  self.windowHost?.contains(NSEvent.mouseLocation) != true,
                  (NSApp.delegate as? AppDelegate)?.isOverStatusItem(NSEvent.mouseLocation) != true,
                  !AssistiveKeyboard.ownsCocoaPoint(NSEvent.mouseLocation) else { return }
            self.collapse()
        }) { eventMonitors.append(token) }
        if let token = NSEvent.addLocalMonitorForEvents(matching: clicks.union(.keyDown), handler: { [weak self] event in
            guard let self else { return event }
            // While an input method is composing, Esc belongs to it and
            // drops the candidate; the island takes the next one.
            if event.type == .keyDown, event.window === self.panel, event.keyCode == 53,
               (self.panel?.firstResponder as? NSTextView)?.hasMarkedText() == true { return event }
            // The Command Bar inside the island reads its own keys, Escape included.
            if event.type == .keyDown, event.window === self.panel, self.showingCommandBar { return event }
            if event.type == .keyDown, event.window === self.panel, self.captureControls == nil {
                let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
                if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "k" {
                    self.toggleSections()
                    return nil
                }
                if modifiers == [.command, .option],
                   let module = NotchSupport.moduleShortcut(event.charactersIgnoringModifiers ?? "", modules: self.modules) {
                    self.select(module)
                    return nil
                }
                if event.keyCode == 48, modifiers == .control || modifiers == [.control, .shift],
                   let module = NotchSupport.adjacentModule(to: self.selected, modules: self.modules,
                                                           backwards: modifiers.contains(.shift)) {
                    self.select(module)
                    return nil
                }
                if event.keyCode == 53, self.showingSections {
                    self.toggleSections()
                    return nil
                }
                if self.handleSectionKey(event) { return nil }
                if self.handleScratchpadKey(event) { return nil }
                if self.handleClipboardPasteKey(event) { return nil }
            }
            if event.type == .keyDown, event.window === self.panel, self.selected == .tools, !self.showingAppPanel, !self.showingSections {
                let launcher = QuickLauncherService.shared
                // The rail reads across its rows until it scrolls, in the
                // rows the open page leaves it below its header; the editing
                // grid keeps its own rows.
                let flow: QuickToolsSupport.GridFlow = launcher.isEditing
                    ? .rows(columns: NotchSupport.toolColumns)
                    : self.expandedGeometry.toolFlow(count: launcher.visibleItems.count)
                return launcher.handlePanelKey(event, flow: flow)
            }
            if event.type == .keyDown, event.window === self.panel, event.keyCode == 53 {
                // A level being typed in the mixer cancels on Escape by
                // itself, and the scratchpad's find bar closes on it; the
                // next one steps back.
                if let editor = self.panel?.firstResponder as? NSTextView, editor.isFieldEditor,
                   (editor.delegate as AnyObject?) is MixerPercentNativeTextField { return event }
                if PlainTextEditor.findBarHasKeyboard(in: self.panel) { return event }
                self.stepBack()
                return nil
            }
            let click = clicks.contains(NSEvent.EventTypeMask(rawValue: 1 << event.type.rawValue))
            let islandWindow = self.ownsWindow(event.window)
            if click, islandWindow { self.clickedSinceOpening = true }
            if click, !islandWindow, !self.keepsWorkingSurface,
               self.windowHost?.contains(NSEvent.mouseLocation) != true,
               (NSApp.delegate as? AppDelegate)?.isOverStatusItem(NSEvent.mouseLocation) != true,
               !AssistiveKeyboard.ownsCocoaPoint(NSEvent.mouseLocation) { self.collapse() }
            return event
        }) { eventMonitors.append(token) }
    }

    /// The panel and what hangs from it: a SwiftUI popover opened in the
    /// island is a child window, so a click in it is not a click away.
    private func ownsWindow(_ window: NSWindow?) -> Bool {
        guard let window, let panel else { return false }
        return sequence(first: window, next: { $0.parent }).contains { $0 === panel }
    }

    private func pointerOverChildWindow(_ point: CGPoint) -> Bool {
        panel?.childWindows?.contains { $0.isVisible && $0.frame.contains(point) } == true
    }

    private func syncGestures() {
        if !NotchGestureSupport.isEnabled() { gesture = NotchGestureSupport() }
        panel?.handleScroll = { [weak self] event in self?.handleScroll(event) ?? false }
    }

    /// The gallery steps its rows from the wheel; every other scroll over the
    /// island is a gesture candidate.
    private func handleScroll(_ event: NSEvent) -> Bool {
        handleSectionScroll(event) || handleGesture(event)
    }

    private func handleSectionScroll(_ event: NSEvent) -> Bool {
        guard running, !suspended, expanded, showingSections, let panel, !trackingMenu,
              event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else {
            sectionScroll = NotchSectionScroll()
            return false
        }
        let screenPoint = panel.convertPoint(toScreen: event.locationInWindow)
        // The header keeps its own gesture; the tiles and the rest of the body step rows.
        guard windowHost?.containsSurface(screenPoint) == true,
              panel.frame.maxY - screenPoint.y > expandedGeometry.headerTopInset + expandedGeometry.headerRowHeight else {
            sectionScroll = NotchSectionScroll()
            return false
        }
        let steps = sectionScroll.steps(deltaY: Double(event.scrollingDeltaY), timestamp: event.timestamp,
                                        precise: event.hasPreciseScrollingDeltas, hasPhase: !event.phase.isEmpty,
                                        began: event.phase.contains(.began),
                                        ended: !event.phase.intersection([.ended, .cancelled]).isEmpty,
                                        momentum: !event.momentumPhase.isEmpty)
        if steps != 0 { scrollSections(by: steps) }
        return true
    }

    private func handleGesture(_ event: NSEvent) -> Bool {
        guard running, !suspended, NotchGestureSupport.isEnabled(), let panel,
              !trackingMenu, captureControls == nil, !heldDrag,
              event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else {
            gesture = NotchGestureSupport()
            return false
        }
        let screenPoint = panel.convertPoint(toScreen: event.locationInWindow)
        guard windowHost?.contains(screenPoint) == true else { gesture = NotchGestureSupport(); return false }
        let fromTop = panel.frame.maxY - screenPoint.y
        let inHeader = NotchSupport.gestureIsOverHeader(expanded: expanded, peeking: peeking,
                                                       fromTop: fromTop, safeTop: expanded ? expandedGeometry.headerTopInset : geometry.safeContentTop,
                                                       height: expanded ? expandedGeometry.headerRowHeight : NotchLayout.headerHeight)
        let interaction = NotchGestureSupport.nativeInteraction(at: panel.contentView?.hitTest(event.locationInWindow))
        let musicSurface = modules.contains(.music)
            && (compactMusicIsVisible || (expanded && selected == .music && !showingAppPanel && !showingSections
                                          && !showingCommandBar))
        let vertical = NotchGestureSupport.allowsVertical(expanded: expanded, inHeader: inHeader,
                                                          musicSurface: musicSurface,
                                                          control: interaction.control, scroll: interaction.scroll)
        let horizontal = !interaction.control && !interaction.scroll && !inHeader && musicSurface
        let x = NotchGestureSupport.movement(Double(event.scrollingDeltaX), precise: event.hasPreciseScrollingDeltas,
                                             inverted: event.isDirectionInvertedFromDevice)
        let y = NotchGestureSupport.movement(Double(event.scrollingDeltaY), precise: event.hasPreciseScrollingDeltas,
                                             inverted: event.isDirectionInvertedFromDevice)
        guard let action = gesture.handle(x: x, y: y, timestamp: event.timestamp,
                                          began: event.phase.contains(.began),
                                          ended: !event.phase.intersection([.ended, .cancelled]).isEmpty,
                                          momentum: !event.momentumPhase.isEmpty,
                                          precise: event.hasPreciseScrollingDeltas,
                                          hasPhase: !event.phase.isEmpty,
                                          allowVertical: vertical, allowHorizontal: horizontal, expanded: expanded) else { return false }
        switch action {
        case .open: open()
        case .close: collapse()
        case .nextTrack, .previousTrack:
            guard musicSurface else { gesture = NotchGestureSupport(); return false }
            NotchMusicService.shared.skipFromGesture(forward: action == .nextTrack)
        }
        return true
    }

    private func removeEventMonitors() {
        eventMonitors.forEach(NSEvent.removeMonitor)
        eventMonitors.removeAll()
    }

    func showUpdate() {
        guard running, !suspended, expanded, case .available = UpdateService.shared.state else { return }
        collapse()
        appDelegate()?.showUpdatePreview()
    }

    private func bindEvents() {
        subscriptions.removeAll()
        if modules.contains(.timer) {
            NotchTimerService.shared.$session.removeDuplicates().receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.syncMenuSpaceMonitoring()
                    self?.objectWillChange.send()
                    self?.refreshPresentation()
                }.store(in: &subscriptions)
        }
        if modules.contains(.watch) {
            // The strip resizes with its reading, and when the area turns
            // out to hold only a picture.
            let watch = NotchWatchService.shared
            Publishers.CombineLatest3(watch.$state.removeDuplicates(), watch.$headline.removeDuplicates(),
                                      watch.$preview.map { $0 != nil }.removeDuplicates())
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.syncMenuSpaceMonitoring()
                    self?.objectWillChange.send()
                    self?.refreshPresentation()
                }.store(in: &subscriptions)
        }
        if modules.contains(.music) {
            let music = NotchMusicService.shared
            music.$playback.combineLatest(music.$artwork, music.$artworkTint)
                .sink { [weak self] playback, artwork, tint in
                    // @Published sends before storing the new value. Keep the last
                    // visible track and cover before playback disappears.
                    guard playback != nil else { return }
                    self?.rememberPresentedMusic(playback: playback, artwork: artwork, tint: tint)
                }.store(in: &subscriptions)
            // Received at once, before the reading that ends the song is
            // published, so the strip leaves as its own song, cover included.
            music.trackEnds
                .sink { [weak self] in self?.holdEndingTrack() }
                .store(in: &subscriptions)
            music.$playback.map { ($0 != nil, $0?.isPlaying == true) }
                .removeDuplicates { $0 == $1 }.receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.syncMenuSpaceMonitoring()
                    self?.objectWillChange.send()
                    self?.refreshPresentation()
                }.store(in: &subscriptions)
            // Music starting, not music already playing when the island came up.
            music.$playback.map { $0?.isPlaying == true }
                .removeDuplicates().dropFirst().filter { $0 }.receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.mascotHearsMusic() }
                .store(in: &subscriptions)
            // A capsule names each new song for a moment: the song playing,
            // or the next one once the notice releases the song it held.
            music.$playback.map { $0?.track.title }.removeDuplicates().map { _ in () }
                .merge(with: $heldMusic.map { $0?.playback.track.title }.removeDuplicates().map { _ in () })
                .receive(on: DispatchQueue.main)
                .sink { [weak self] in self?.nameCapsuleSong() }
                .store(in: &subscriptions)
        }
        if NotchSupport.routes(.track) {
            // Received at once, on the main thread, while the strip still
            // shows the previous song.
            NotchMusicService.shared.trackChanges
                .sink { [weak self] in self?.scheduleTrackNotice() }
                .store(in: &subscriptions)
        }
        if modules.contains(.tools) {
            // The tools page is a rail sized by its tiles; editing or a
            // hosted utility turns it into a page.
            let launcher = QuickLauncherService.shared
            launcher.$isEditing.map { _ in () }
                .merge(with: launcher.$activeUtility.map { _ in () }, launcher.$hiddenItemsRaw.map { _ in () })
                .dropFirst(3).receive(on: DispatchQueue.main)
                .sink { [weak self] in
                    guard let self, self.expanded, self.selected == .tools, !self.showingAppPanel, !self.showingSections else { return }
                    self.refreshPresentation()
                }.store(in: &subscriptions)
        }
        if modules.contains(.system), AppFeature.fanControl.isAvailable {
            // The fan card only exists once the page's first sample lands; the
            // strip that was sized without it reserves its row again.
            SystemMonitor.shared.$snapshot.map { $0.fanSpeeds.isEmpty }.removeDuplicates().dropFirst()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    guard let self, self.expanded, self.selected == .system, self.selectedMetric == nil,
                          !self.showingAppPanel, !self.showingSections else { return }
                    self.refreshPresentation()
                }.store(in: &subscriptions)
        }
        if NotchSupport.routes(.download) {
            NotchDownloadService.shared.$items.receive(on: DispatchQueue.main).sink { [weak self] _ in
                self?.syncMenuSpaceMonitoring()
                self?.objectWillChange.send()
                self?.refreshPresentation()
            }.store(in: &subscriptions)
            NotchDownloadService.shared.onArrival = { [weak self] item in
                self?.show(NotchNotice(event: .download,
                    title: FeatureStrings.notchFiles(L10n.shared.language).completed,
                    detail: item.name, symbol: "arrow.down.circle.fill", mascot: .celebrate))
                self?.reactMascot(.celebrate)
            }
            NotchDownloadService.shared.onFailure = { [weak self] in self?.reactMascot(.confused) }
        }
        if modules.contains(.agents) {
            // Only what changes the island's size or strip: a turn starting or
            // ending, the first read landing, which agents have cards, and
            // which are working, since each one's mark widens the strip.
            AgentUsageService.shared.$snapshot
                .map { ($0.loaded, $0.live.isEmpty, $0.seen, Set($0.live.map(\.provider))) }
                .removeDuplicates(by: ==)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.syncMenuSpaceMonitoring()
                    self?.objectWillChange.send()
                    self?.refreshPresentation()
                }.store(in: &subscriptions)
        }
        if modules.contains(.calendar) {
            NotchCalendarService.shared.$countdown.removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.syncMascotCalendar()
                    self?.syncMenuSpaceMonitoring()
                    self?.objectWillChange.send()
                    self?.refreshPresentation()
                }.store(in: &subscriptions)
        }
        // The companion is wide awake while Keep Awake holds the Mac up, and
        // yawns as it lets go.
        KeepAwakeManager.shared.$isActive.removeDuplicates().dropFirst().receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncMascotKeepAwake() }
            .store(in: &subscriptions)
        if NotchKeepAwakeSupport.showsActivity() {
            // A session starting or ending, or its end moving, which can
            // change the reading and the wings it needs.
            let awake = KeepAwakeManager.shared
            awake.$isActive.combineLatest(awake.$endDate).removeDuplicates { $0 == $1 }
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.syncMenuSpaceMonitoring()
                    self?.objectWillChange.send()
                    self?.refreshPresentation()
                }.store(in: &subscriptions)
        }
        if NotchSupport.routes(.agents) {
            AgentUsageService.shared.events.receive(on: DispatchQueue.main)
                .sink { [weak self] in self?.showAgentEvent($0) }
                .store(in: &subscriptions)
        }
        stopPower()
        if NotchSupport.routes(.volume) {
            bindVolumeEvents()
        }
        if NotchSupport.routes(.systemNotification) {
            NotchNotificationService.shared.received.sink { [weak self] item in
                guard let self else { return }
                let shown = self.show(NotchNotice(event: .systemNotification, title: item.content.title,
                                                 detail: item.content.body, symbol: "bell.fill", notification: item.content, notificationID: item.id))
                if shown, !self.expanded, self.captureControls == nil, !self.dragPlaceholder {
                    NotchNotificationService.shared.hideNative(item.id)
                }
            }.store(in: &subscriptions)
        }
        if NotchSupport.routes(.clipboard) {
            let history = ClipboardHistoryService.shared
            history.capturedEntry.receive(on: DispatchQueue.main).sink { [weak self] _ in
                guard let self else { return }
                let text = FeatureStrings.clipboard(L10n.shared.language)
                self.show(NotchNotice(event: .clipboard, title: text.copied,
                                      detail: text.title, symbol: "doc.on.clipboard"))
            }.store(in: &subscriptions)
        }
        // The companion loves being plugged in, so it listens for the charger too.
        if NotchSupport.routes(.battery) || idleContent == .battery || NotchMascotSupport.isEnabled() { startPower() }
    }

    private func showAgentEvent(_ event: AgentUsageEvent) {
        let text = FeatureStrings.notchAgents(L10n.shared.language)
        let locale = L10n.shared.language.formattingLocale()
        let remaining = NotchAgentSupport.limitDisplay() == .remaining
        func window(_ window: AgentLimitWindow) -> String {
            switch window.kind {
            case .session: return text.session
            case .weekly: return window.scope.map { "\(text.weekly) · \($0)" } ?? text.weekly
            case .other: return window.minutes.map { AgentFormat.duration(TimeInterval($0) * 60, locale: locale, units: 1) }
                ?? text.readoutLimit
            }
        }
        switch event {
        case .finished(let provider, let duration, let cost, _, _):
            show(NotchNotice(event: .agents, title: text.finished(provider.displayName),
                             detail: [AgentFormat.duration(duration, locale: locale), cost > 0 ? AgentFormat.cost(cost) : ""]
                                .filter { !$0.isEmpty }.joined(separator: " · "),
                             symbol: provider.symbol, agent: provider))
            // After the notice, the companion cheers the finished task.
            reactMascot(.celebrate)
        case .limitWarning(let provider, let limit):
            let share = AgentFormat.percent(remaining ? limit.remainingFraction : limit.usedFraction)
            show(NotchNotice(event: .agents, title: "\(provider.displayName) · \(window(limit))",
                             detail: remaining ? text.left(share) : text.usedShare(share),
                             symbol: "exclamationmark.triangle.fill", agent: provider))
        case .limitReset(let provider, let limit):
            // Work can go on: the companion is glad of it.
            show(NotchNotice(event: .agents, title: "\(provider.displayName) · \(window(limit))",
                             detail: text.limitRenewed, symbol: "arrow.clockwise", agent: provider, mascot: .celebrate))
            reactMascot(.celebrate)
        case .budgetReached(let spent, _):
            show(NotchNotice(event: .agents, title: text.budgetTitle, detail: AgentFormat.cost(spent),
                             symbol: "dollarsign.circle.fill"))
        }
    }

    func showCurrentVolume() {
        let mixer = AppVolumeMixer.shared
        guard let volume = mixer.systemOutputVolume else { return }
        showVolume(volume, muted: mixer.systemOutputMuted)
    }

    /// The island's own output controls already show the level they set.
    /// Their changes, and the device's reading that follows, leave the open
    /// header's title in place instead of covering it with the same level.
    func noteOwnVolumeAdjustment() {
        ownVolumeAdjustmentUntil = ProcessInfo.processInfo.systemUptime + 1
    }

    private func bindVolumeEvents() {
        let mixer = AppVolumeMixer.shared
        volumeDeviceUID = mixer.currentOutputDeviceUID
        volumeBaseline = mixer.systemOutputVolume
        muteBaseline = mixer.systemOutputMuted
        mixer.$systemOutputVolume.combineLatest(mixer.$systemOutputMuted, mixer.$currentOutputDeviceUID)
            .handleEvents(receiveOutput: { [weak self] _, _, deviceUID in
                guard let self, deviceUID != self.volumeDeviceUID else { return }
                self.volumeDeviceUID = deviceUID
                self.volumeBaseline = nil
                self.muteBaseline = nil
            })
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak mixer] _ in
                guard let mixer else { return }
                // Published fields arrive separately and before assignment. Read
                // the settled device and controls together on the main queue.
                self?.volumeChanged(mixer.systemOutputVolume, muted: mixer.systemOutputMuted)
            }
            .store(in: &subscriptions)
    }

    private func volumeChanged(_ volume: Double?, muted: Bool?) {
        defer { volumeBaseline = volume; muteBaseline = muted }
        guard volumeDeviceUID != nil, let volume, volumeBaseline != nil,
              volume != volumeBaseline || (muteBaseline != nil && muted != muteBaseline) else { return }
        // Volume keys still announce themselves through showCurrentVolume.
        guard !expanded || ProcessInfo.processInfo.systemUptime >= ownVolumeAdjustmentUntil else { return }
        showVolume(volume, muted: muted)
    }

    /// Levels set outside the island, like Command Bar's, report here
    /// too. The observer skips a level that matches the current one and a new
    /// output's first reading. False leaves the confirmation to the caller.
    @discardableResult
    func showVolume(_ volume: Double, muted: Bool? = nil) -> Bool {
        guard volume.isFinite else { return false }
        let value = muted == true ? 0 : min(1, max(0, volume))
        return show(NotchNotice(event: .volume, title: FeatureStrings.notch(L10n.shared.language).volume,
                                detail: "\(Int((value * 100).rounded()))%",
                                symbol: value == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill", level: value))
    }

    private func startPower() {
        guard PowerSampler.hasInternalBattery else { return }
        powerSampler = PowerSampler(smc: nil)
        power = powerSampler?.sample() ?? PowerReading()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let owner = Unmanaged<NotchService>.fromOpaque(context).takeUnretainedValue()
            owner.powerChanged()
        }
        if let source = IOPSNotificationCreateRunLoopSource(callback, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue() {
            powerSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    private func stopPower() {
        if let source = powerSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
        powerSource = nil
        powerSampler = nil
    }

    private func powerChanged() {
        guard running, !suspended, let sampler = powerSampler else { return }
        let before = power
        let next = sampler.sample()
        power = next
        let pluggedIn = !before.externalConnected && next.externalConnected
        let low = (next.chargePercent ?? 100) <= 20 && (before.chargePercent ?? 0) > 20
        guard before.externalConnected != next.externalConnected || low
                || (before.isCharging && !next.isCharging && next.chargePercent == 100) else { return }
        let text = FeatureStrings.notch(L10n.shared.language)
        let title = low ? text.lowBattery : next.externalConnected
            ? (next.isCharging ? text.charging : next.chargePercent == 100
                ? text.charged : L10n.shared.s.powerPluggedIn) : text.onBattery
        let charged = next.externalConnected && before.isCharging && !next.isCharging && next.chargePercent == 100
        let reaction = NotchMascotSupport.powerReaction(pluggedIn: pluggedIn, charged: charged, low: low)
        show(NotchNotice(event: .battery, title: title,
                         detail: next.chargePercent.map { "\($0)%" } ?? "",
                         symbol: next.externalConnected ? "battery.100percent.bolt" : "battery.25percent",
                         mascot: reaction))
        if let reaction { reactMascot(reaction) }
    }

    private func syncVisibleConsumers() {
        syncMenuSpaceMonitoring()
        guard running, !suspended else { releaseMonitor(); return }
        if fullscreenCompact {
            CameraPreviewService.shared.hideEmbedded()
            // A copy on another display still shows the song playing.
            let copiesShowMusic = showsCopies && NotchSupport.watchesMusicActivity()
            if copiesShowMusic { NotchMusicService.shared.start() } else { NotchMusicService.shared.stop() }
            releaseMonitor()
            return
        }
        if !NotchCameraSupport.canPresent(expanded: expanded && !showingSections && !showingCommandBar, selected: selected,
            appPanel: showingAppPanel, captureControls: captureControls != nil) {
            CameraPreviewService.shared.hideEmbedded()
        }
        let musicWanted = modules.contains(.music) && ((expanded && (selected == .music || (selected == .controls && NotchSupport.controls().contains(.music)))
            && !showingAppPanel && !showingSections && !showingCommandBar)
            || (!hiddenUntilHover && (NotchSupport.watchesMusicActivity() || NotchSupport.routes(.track))))
        if musicWanted { NotchMusicService.shared.start() } else { NotchMusicService.shared.stop() }
        let needs = expanded && selected == .system && selectedMetric == nil && modules.contains(.system) && !showingAppPanel
            && !showingSections && !showingCommandBar
        var detailNeeds = expanded && !showingSections ? selectedMetric?.monitorNeeds ?? .none : .none
        if needs, AppFeature.monitorDisk.isAvailable { detailNeeds.disk = true }
        if needs, AppFeature.fanControl.isAvailable { detailNeeds.fanSpeed = true }
        SystemMonitor.shared.setNotchDetailNeeds(detailNeeds)
        if needs != notchNeedsMonitor {
            notchNeedsMonitor = needs
            SystemMonitor.shared.setNotchVisible(needs)
        }
    }

    private func releaseMonitor() {
        SystemMonitor.shared.setNotchDetailNeeds(.none)
        guard notchNeedsMonitor else { return }
        notchNeedsMonitor = false
        SystemMonitor.shared.setNotchVisible(false)
    }
}

// MARK: - Companion

extension NotchService {
    /// Visits come every few minutes while the island rests. One is set up at
    /// a time, minutes ahead. Nothing ticks in between, and the stroll itself
    /// is Core Animation's to draw.
    fileprivate func syncMascotVisits() {
        let visits = running && NotchMascotSupport.visits()
        let frequency = NotchMascotSupport.visitFrequency()
        defer { mascotVisitsWereOn = visits; mascotFrequencyAtSync = frequency }
        guard visits else {
            nextMascotVisitWork?.cancel(); nextMascotVisitWork = nil
            // Visits turned off only stop coming: what plays now, a stroll, a
            // reaction or an entrance, plays out, and switched off it says
            // goodbye once back in its place. A stopped island ends everything.
            if let visit = mascotVisit, visit.kind != .farewell, !running { endMascotVisit() }
            return
        }
        // Turned on just now: it says hello almost at once. Coming out from
        // behind the camera as it is switched on is that hello already.
        if !mascotVisitsWereOn {
            if mascotVisit?.kind != .arrive {
                scheduleMascotVisit(after: NotchMascotSupport.welcomeDelay, greeting: .wink)
            }
        } else if mascotVisit == nil, nextMascotVisitWork == nil || mascotFrequencyAtSync != frequency {
            // A new pace takes effect now, not after the visit already planned.
            scheduleMascotVisit(after: NotchMascotSupport.nextVisitDelay(frequency))
        }
    }

    fileprivate func scheduleMascotVisit(after delay: TimeInterval, greeting: NotchMascotMood? = nil) {
        nextMascotVisitWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.beginMascotVisit(greeting: greeting) }
        nextMascotVisitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// `asked` is a hello Settings asked for, which comes whatever the visits.
    private func beginMascotVisit(greeting: NotchMascotMood?, asked: Bool = false) {
        nextMascotVisitWork = nil
        guard asked || NotchMascotSupport.visits() else { return }
        // Busy, hidden or out of room: it tries again on its next visit.
        guard canHostMascotVisit(), mascotVisit == nil else {
            scheduleMascotVisit(after: NotchMascotSupport.nextVisitDelay())
            return
        }
        // Low Power Mode keeps it at rest, and a pending visit simply comes later.
        guard asked || !ProcessInfo.processInfo.isLowPowerModeEnabled else {
            scheduleMascotVisit(after: NotchMascotSupport.nextVisitDelay())
            return
        }
        // Without motion a stroll over an activity hides its strip for
        // seconds: it waits for the island to rest, and a hello asked for
        // plays in its own wing.
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, !mascotRestsInView {
            if asked { beginMascotCameo(.celebrate) } else { scheduleMascotVisit(after: NotchMascotSupport.nextVisitDelay()) }
            return
        }
        let visit = NotchMascotVisit(id: UUID(), kind: mascotRestsInView ? .lap : .pass,
                                     greeting: greeting ?? NotchMascotSupport.greeting(), start: CACurrentMediaTime())
        setMascotVisit(visit)
        // Every stroll ends out of sight or where it rests, so its last frame
        // hands the strip straight back.
        let work = DispatchWorkItem { [weak self] in self?.endMascotVisit() }
        mascotVisitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + visit.duration, execute: work)
    }

    fileprivate func endMascotVisit() {
        mascotVisitWork?.cancel(); mascotVisitWork = nil
        guard let ended = mascotVisit else { return }
        // Gone behind the camera from a reaction over an activity that left
        // meanwhile, it comes back out to its place rather than appear there.
        if ended.kind.reaction != nil, mascotRestsInView, CACurrentMediaTime() >= ended.start + ended.duration - 0.05,
           !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            // From the moment it went behind the camera, which a late timer missed.
            let back = NotchMascotVisit(id: UUID(), kind: .arrive, greeting: .idle,
                                        start: max(ended.start + ended.duration, CACurrentMediaTime() - 0.1))
            setMascotVisit(back)
            let work = DispatchWorkItem { [weak self] in self?.endMascotVisit() }
            mascotVisitWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + back.duration, execute: work)
            return
        }
        // Switched off while it strolled to its place: it says goodbye from
        // there rather than vanish, as it does switched off at rest.
        if running, !NotchMascotSupport.isEnabled(), !ended.kind.endsOutOfSight, ended.kind != .farewell,
           !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, idleContent == .none, compactActivity == nil,
           !mascotInBar, canHostMascotVisit() {
            let farewell = NotchMascotVisit(id: UUID(), kind: .farewell, greeting: .happy, start: CACurrentMediaTime())
            setMascotVisit(farewell)
            let work = DispatchWorkItem { [weak self] in self?.endMascotVisit() }
            mascotVisitWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + farewell.duration, execute: work)
            return
        }
        setMascotVisit(nil)
        // A side chosen while it was out takes effect now.
        if mascotSideAtSync != NotchMascotSupport.side() {
            syncMascotSide()
            if mascotVisit != nil { return }
        }
        if running, NotchMascotSupport.visits() { scheduleMascotVisit(after: NotchMascotSupport.nextVisitDelay()) }
    }

    /// Back at rest in view while it reacted over an activity that has gone
    /// meanwhile: standing in its place, or on its way there, it stays once
    /// its reaction is over instead of going behind the camera.
    fileprivate func mascotReturnedToRest() {
        guard let visit = mascotVisit, let reaction = visit.kind.reaction else { return }
        let landed = visit.start + (visit.kind == .linger(reaction) ? 0 : NotchMascotMotion.cameoArrival)
        let now = CACurrentMediaTime()
        // Already on its way behind the camera, it comes back out once gone.
        guard now < landed + NotchMascotMotion.cameoHold(reaction) - 0.05 else { return }
        // It ends where it landed, its reaction playing on there.
        let wait = max(0, landed + 0.05 - now)
        mascotVisitWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.mascotVisit?.id == visit.id else { return }
            if self.mascotRestsInView { self.endMascotVisit(); return }
            // Something took its place again: it leaves as it came for.
            let leave = DispatchWorkItem { [weak self] in self?.endMascotVisit() }
            self.mascotVisitWork = leave
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0, visit.start + visit.duration - CACurrentMediaTime()),
                                          execute: leave)
        }
        mascotVisitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: work)
    }

    /// Turned on while the closed island rests with nothing else to show, it
    /// hops out from behind the camera as its wings open, or into a capsule
    /// at its near end. Turned off there, it
    /// gives a glad hop and goes behind the camera, and the wings fold once
    /// it is gone, since the farewell keeps it drawn until then.
    fileprivate func stageMascotEntrance(arriving: Bool) {
        // A stroll under way when it is turned off finishes first and says
        // goodbye after. One turned back on mid-farewell comes out from where it went.
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, idleContent == .none,
              compactActivity == nil, !mascotInBar, canHostMascotVisit(),
              arriving ? mascotVisit == nil || mascotVisit?.kind == .farewell : mascotVisit == nil else { return }
        let visit = NotchMascotVisit(id: UUID(), kind: arriving ? .arrive : .farewell,
                                     greeting: arriving ? .wink : .happy, start: CACurrentMediaTime())
        mascotVisitWork?.cancel()
        mascotStepBackWork?.cancel(); mascotStepBackWork = nil
        mascotVisit = visit
        mascotStepsAside = false
        // The wings fold the moment a farewell is out of sight.
        let work = DispatchWorkItem { [weak self] in self?.endMascotVisit() }
        mascotVisitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + visit.duration, execute: work)
    }

    /// Settings asks it to say hello now: a stroll where it rests or over
    /// what the closed island shows, or a glad hop where the open island
    /// keeps it. False when the island has no room for it at the moment.
    @discardableResult
    func greetMascot() -> Bool {
        guard NotchMascotSupport.isEnabled(), mascotVisit == nil else { return false }
        if mascotResidentShows {
            mascotReaction = NotchMascotReactionEvent(id: UUID(), reaction: .celebrate, start: CACurrentMediaTime())
            return true
        }
        guard canHostMascotVisit() else { return false }
        nextMascotVisitWork?.cancel()
        beginMascotVisit(greeting: .wink, asked: true)
        return mascotVisit != nil
    }

    /// A visit needs the closed island on screen with room for the companion,
    /// whatever it shows. The companion coming back from the bar is not out in it.
    private func canHostMascotVisit(returning: Bool = false) -> Bool {
        showsSystemFeedback && (returning || !mascotInBar) && !expanded && !peeking && !dragPlaceholder && notice == nil
            && captureControls == nil && !showsCompactActivityPicker && !fullscreenCompact
            && panel?.isVisible == true && mascotHasRoom
    }

    /// Whether the closed island has room for the companion: a wing beside
    /// the camera wide enough for it, at rest or in the activity's strip,
    /// or a capsule.
    private var mascotHasRoom: Bool {
        guard let activity = compactActivity else { return geometry.floats || geometry.restingWingWidth > 0 }
        return mascotTrack(overActivityStrip: compactStripSize(for: activity, companion: compactCompanion)) != nil
    }

    /// Where the companion comes out over the activity strip of `size` the
    /// island shows, or nil when that strip has no room for it.
    func mascotTrack(overActivityStrip size: CGSize) -> NotchMascotTrack? {
        // Switched off, a visit under way still plays out over the strip.
        guard mascotOn || mascotVisit != nil else { return nil }
        return NotchMascotSupport.track(overActivity: geometry.floats ? geometry : compactActivityGeometry, size: size,
                                        side: mascotSide)
    }

    /// It rests in the closed island now, rather than only visiting it.
    private var mascotRestsInView: Bool { mascotAtRest && compactActivity == nil }

    /// Open beside a camera, the island keeps the companion where it rests
    /// closed, in the top row beside the camera, so the island opens around
    /// it. The row must leave it room: free when the header sits below the
    /// camera, or past the title or the actions on its side of the camera.
    var mascotResidentShows: Bool {
        guard mascotOn, !mascotInBar, expanded, !showingCommandBar, captureControls == nil,
              !dragPlaceholder, !noticeExpanded, geometry.isNotched, !geometry.floats else { return false }
        let header = expandedGeometry
        guard header.headerCameraGap > 0 else { return true }
        let side = (contentSize.width - header.headerCameraGap) / 2
        let lane = NotchMascotSupport.residentLane(stripHeight: geometry.stripHeight)
        switch mascotSide {
        case .left:
            // A level shown in the header, or the sections' search, fills that side.
            guard !showingSections, notice?.level == nil else { return false }
            return header.headerTitleWidth + lane <= side
        case .right:
            return headerActionsWidth + lane <= side
        }
    }

    /// The header's actions beside the camera: its menu, and the update
    /// button while one is offered or under way.
    private var headerActionsWidth: CGFloat {
        switch UpdateService.shared.state {
        case .available, .downloading, .installing: return 28 + 6 + 120
        default: return 28
        }
    }

    /// Where the open island keeps it, in a surface `width` wide: the same
    /// place beside the camera it rests in when the island is closed.
    func mascotResidentTrack(surfaceWidth width: CGFloat) -> NotchMascotTrack {
        let wing = (width - geometry.cameraWidth) / 2
        return NotchMascotSupport.track(stripWidth: width, stripHeight: geometry.stripHeight,
                                        wing: wing, cameraWidth: geometry.cameraWidth, floats: false,
                                        bodyHeight: geometry.stripBodyHeight, side: mascotSide)
    }

    // MARK: Command Bar

    /// Where a drop for the Command Bar leaves the closed island: its visible
    /// shape on screen, a capsule without the margins it floats in, or nil
    /// when the island cannot show one. The bar opens on the display the
    /// pointer is on, so the island must be there.
    func commandBarDropSource() -> CGRect? {
        guard acceptsSystemFeedback, !hiddenUntilHover, !fullscreenCompact, !expanded, captureControls == nil,
              panel?.isVisible == true, let frame = windowHost?.visibleFrame, !frame.isEmpty,
              geometry.screen.contains(NSEvent.mouseLocation) else { return nil }
        let gap = geometry.floatingGap ?? 0
        return frame.insetBy(dx: 0, dy: min(gap, frame.height / 2 - 1))
    }

    /// Opens the island around the Command Bar and hands over its panel,
    /// which then holds the keyboard. Nil when the island cannot open here.
    func presentCommandBar() -> NSPanel? {
        guard NotchSupport.isEnabled(), acceptsUserInteraction, !hiddenInFullscreen, captureControls == nil,
              !heldDrag, geometry.screen.contains(NSEvent.mouseLocation), let panel else { return nil }
        // The keyboard first, before the island changes shape, so keys typed
        // right after the shortcut wait here for the bar's field.
        panel.acceptsKeyFocus = true
        panel.makeKey()
        (NSApp.delegate as? AppDelegate)?.closePopover(preservingNotch: true)
        hoverState.open()
        hoverWork?.cancel()
        if !expanded { removeHoverExitMonitors() }
        mutatePresentation(transitionContent: expanded ? .replace : .reveal) {
            showingCommandBar = true
            showingAppPanel = false
            showingSections = false
            selectedMetric = nil
            peeking = false
            openedByHover = false
            expanded = true
            if notice?.notificationID != nil { noticeWork?.cancel(); noticeWork = nil; notice = nil; noticeExpanded = false }
        }
        inside = windowHost?.containsHover(NSEvent.mouseLocation) == true
        installEventMonitors()
        syncVisibleConsumers()
        panel.makeKey()
        return panel
    }

    /// The companion leaves the island for the Command Bar's drop, and comes
    /// back to rest once the drop has risen into it again. Back from a drop
    /// it saw rise, it hops out from behind the camera to its place,
    /// wearing `homecoming` until it lands.
    func setMascotInBar(_ away: Bool, homecoming: NotchMascotMood? = nil) {
        guard away != mascotInBar else { return }
        if away, mascotVisit != nil { endMascotVisit() }
        let home = homecoming.flatMap { mood -> NotchMascotVisit? in
            guard !away, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, NotchMascotSupport.isEnabled(),
                  idleContent == .none, compactActivity == nil, canHostMascotVisit(returning: true) else { return nil }
            return NotchMascotVisit(id: UUID(), kind: .home, greeting: mood, start: CACurrentMediaTime())
        }
        mutatePresentation {
            mascotInBar = away
            if let home { mascotVisit = home }
        }
        guard let home else { return }
        mascotVisitWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.endMascotVisit() }
        mascotVisitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + home.duration + 0.1, execute: work)
    }

    /// The companion moved to the camera's other side in Settings: from where
    /// it rested it goes behind the camera, across, and out on the new side.
    /// Where the companion stands beside the camera if the island opens or
    /// closes around it now: its centre's offset from the camera's, before
    /// the change. Nil when it is not standing there, as on a visit.
    func mascotBridgeStart(opening: Bool) -> CGFloat? {
        // Only where it shows: a notice, a peek, the drop hint or an island
        // hidden until hover draws no companion to keep.
        guard mascotVisit == nil, geometry.isNotched, !geometry.floats,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              opening ? !expanded && mascotRestsInView && canHostMascotVisit() : expanded && mascotResidentShows
        else { return nil }
        let from = opening ? mascotClosedOffset : mascotOpenOffset
        mascotBridgeLift = opening ? mascotClosedTrack.hop(0.22)
            : mascotResidentTrack(surfaceWidth: expandedSize.width).hop(0.22)
        // In its own layer before the island changes, which redraws the
        // window at once: shown only afterwards, it was gone for two frames.
        endMascotBridgeNow()
        showMascotBridge(from: from, to: from, duration: 0)
        mascotBridgeTarget = opening ? .resident : .rest
        if !mascotBridging { mascotBridging = true }
        return from
    }

    /// Opened or closed around it, it stays in its place, sliding the little
    /// way to where the island keeps it now, while the page or the strip
    /// fades in and settles; then they show it again. Without a place for
    /// it after the change, it goes with the content as before.
    func bridgeMascot(from: CGFloat, opening: Bool) {
        // Closed, it shows again only with nothing over the resting island.
        guard opening ? mascotResidentShows : mascotRestsInView && canHostMascotVisit() else {
            mascotBridging = false
            windowHost?.endMascotBridge()
            return
        }
        // As long as the content takes to arrive: a reveal or a dismissal.
        let duration: TimeInterval = opening ? 0.45 : 0.4
        showMascotBridge(from: from, to: opening ? mascotOpenOffset : mascotClosedOffset, duration: duration)
        scheduleMascotBridgeEnd(after: duration)
    }

    /// A notice that carries the companion arrives while it rests in view:
    /// it stays in sight and steps into the notice, from beside the camera
    /// to the notice's end, a little smaller, as the notice comes in. Its
    /// centre's offset from the camera's before, nil when it is not there.
    func mascotNoticeBridgeStart(for incoming: NotchNotice) -> CGFloat? {
        // Another notice in place of the one it stepped into ends its step.
        if mascotBridging, notice != nil { endMascotBridgeNow() }
        guard incoming.mascot != nil, notice == nil, noticeCanPresent, mascotVisit == nil,
              NotchMascotSupport.isEnabled(), geometry.isNotched, !geometry.floats,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              mascotRestsInView, canHostMascotVisit() else { return nil }
        endMascotBridgeNow()
        let from = mascotClosedOffset
        showMascotBridge(from: from, to: from, duration: 0)
        mascotBridgeTarget = .notice(incoming)
        mascotBridging = true
        return from
    }

    func bridgeMascotIntoNotice(_ shown: NotchNotice, from: CGFloat) {
        guard notice == shown, let reaction = shown.mascot else { endMascotBridgeNow(); return }
        let scale = mascotNoticeScale
        // As long as the notice takes to come in.
        let duration: TimeInterval = 0.45
        showMascotBridge(from: from, to: shown.mascotOffset(in: geometry), duration: duration, scale: (1, scale),
                         trailsGrowth: true)
        // On the way it plays the notice's reaction, in step with the notice's own.
        if NotchMascotSupport.reacts() {
            windowHost?.reactMascotBridge(NotchMascotReactionEvent(id: UUID(), reaction: reaction,
                                                                   start: CACurrentMediaTime()),
                                          lift: NotchMascotSupport.noticeSize * 0.32 / scale)
        }
        scheduleMascotBridgeEnd(after: duration)
    }

    /// The notice it stood in leaves while it rests in view: it steps back
    /// out to its place beside the camera, growing to its size there. Its
    /// centre's offset in the notice, nil when it was not in one.
    func mascotNoticeBridgeBackStart(from ending: NotchNotice?) -> CGFloat? {
        guard let ending, ending.mascot != nil, NotchMascotSupport.isEnabled(), mascotVisit == nil,
              geometry.isNotched, !geometry.floats, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              mascotRestsInView else { return nil }
        // Where the notice draws it, before the notice starts to leave.
        endMascotBridgeNow()
        let from = ending.mascotOffset(in: geometry)
        let scale = mascotNoticeScale
        showMascotBridge(from: from, to: from, duration: 0, scale: (scale, scale))
        mascotBridgeTarget = .rest
        mascotBridging = true
        return from
    }

    func bridgeMascotHome(from: CGFloat) {
        // Only with nothing over the resting island once the notice is gone.
        guard mascotRestsInView, canHostMascotVisit() else { endMascotBridgeNow(); return }
        // The notice fades out, and the resting island back in, meanwhile.
        let duration: TimeInterval = 0.45
        // A little hop home, over the notice's words as they fade.
        showMascotBridge(from: from, to: mascotClosedOffset, duration: duration, scale: (mascotNoticeScale, 1),
                         hop: mascotClosedTrack.hop(0.22))
        scheduleMascotBridgeEnd(after: duration)
    }

    /// How much smaller a notice draws it than its resting place does.
    private var mascotNoticeScale: CGFloat {
        NotchMascotSupport.noticeSize / NotchMascotSupport.size(stripHeight: geometry.stripHeight, floats: false)
    }

    private func showMascotBridge(from: CGFloat, to: CGFloat, duration: TimeInterval,
                                  scale: (from: CGFloat, to: CGFloat) = (1, 1), trailsGrowth: Bool = false,
                                  hop: CGFloat = 0) {
        windowHost?.bridgeMascot(look: NotchMascotSupport.look(),
                                 size: NotchMascotSupport.size(stripHeight: geometry.stripHeight, floats: false),
                                 mood: mascotRestingMood, from: from, to: to,
                                 baseline: geometry.stripHeight / 2 + 0.5, duration: duration, scale: scale,
                                 trailsGrowth: trailsGrowth, hop: hop)
    }

    /// Once the content it stood in for has come in: the strip, page or
    /// notice beneath shows it again, and a frame later the stand-in goes.
    private func scheduleMascotBridgeEnd(after duration: TimeInterval) {
        mascotBridgeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.mascotBridgeWork = nil
            self.mascotBridging = false
            self.mascotBridgeTarget = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self, !self.mascotBridging else { return }
                self.windowHost?.endMascotBridge()
            }
        }
        mascotBridgeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    /// A step under way ends at once, the companion back where it is drawn.
    private func endMascotBridgeNow(fading: Bool = false) {
        mascotBridgeWork?.cancel(); mascotBridgeWork = nil
        mascotBridgeTarget = nil
        if mascotBridging { mascotBridging = false }
        windowHost?.endMascotBridge(fading: fading)
    }

    /// Whether what the stand-in is headed for still draws the companion.
    private var mascotBridgeTargetShows: Bool {
        switch mascotBridgeTarget {
        case .rest: return mascotRestsInView && canHostMascotVisit()
        case .resident: return mascotResidentShows
        case .notice(let shown): return notice == shown && !noticeExpanded && noticeCanPresent
        case nil: return true
        }
    }

    /// Where it rests in the closed island.
    private var mascotClosedTrack: NotchMascotTrack {
        NotchMascotSupport.track(stripWidth: geometry.collapsed.width, stripHeight: geometry.stripHeight,
                                 wing: geometry.restingWingWidth, cameraWidth: geometry.cameraWidth,
                                 floats: false, bodyHeight: geometry.stripBodyHeight, side: mascotSide)
    }

    /// Its centre's offset from the camera's where it rests closed.
    private var mascotClosedOffset: CGFloat { mascotClosedTrack.rest - geometry.collapsed.width / 2 }

    /// ... and where the open island keeps it.
    private var mascotOpenOffset: CGFloat {
        let width = expandedSize.width
        return mascotResidentTrack(surfaceWidth: width).rest - width / 2
    }

    private func syncMascotSide() {
        let side = NotchMascotSupport.side()
        let previous = mascotSideAtSync
        // A visit under way finishes on the side it set out on, or its path
        // would turn around mid-way; the side chosen since follows once it
        // is over.
        guard previous == nil || mascotVisit == nil else { return }
        mascotSideAtSync = side
        // Across, behind the camera, closed or where the open island keeps it.
        guard let previous, previous != side, !geometry.floats,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              mascotResidentShows || (mascotRestsInView && canHostMascotVisit()) else { return }
        let cross = NotchMascotVisit(id: UUID(), kind: .cross, greeting: .wink, start: CACurrentMediaTime())
        mutatePresentation { mascotVisit = cross }
        mascotVisitWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.endMascotVisit() }
        mascotVisitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + cross.duration + 0.1, execute: work)
    }

    /// Keep Awake starting or ending. Checked as the island refreshes too: a
    /// timed session sets its end first, and the refresh for that can draw
    /// the session's strip before word of the session itself arrives, too
    /// late for the companion to stay and react where it rested.
    fileprivate func syncMascotKeepAwake() {
        let active = KeepAwakeManager.shared.isActive
        let saw = mascotSawKeepAwake
        // Noted first: the reaction refreshes the island, which looks again.
        mascotSawKeepAwake = active
        // The value it starts with is no news.
        guard let saw, saw != active, NotchMascotSupport.isEnabled() else { return }
        objectWillChange.send()
        reactMascot(active ? .perk : .yawn)
    }

    /// An AI agent getting to work where the companion rests: it stays in its
    /// wing with a ready face as the agent's strip takes its place, then
    /// goes behind the camera and leaves the agent's mark there. Checked as
    /// the island refreshes, before that strip is drawn, at most once in a
    /// while.
    fileprivate func syncMascotAgents() {
        // Agents already at work when the app opens are no news: their logs
        // are read after the island first shows.
        guard AgentUsageService.shared.snapshot.loaded else { return }
        let working = hasAgentActivity
        let saw = mascotSawAgents
        mascotSawAgents = working
        guard saw == false, working, mascotRestedInView, NotchMascotSupport.reacts() else { return }
        let now = CACurrentMediaTime()
        guard now - lastMascotAgentStart > NotchMascotSupport.agentStartInterval else { return }
        lastMascotAgentStart = now
        reactMascot(.ready, patience: 1)
    }

    /// The event the island counted down to begins: the companion bounces,
    /// beside its time left or where it rests.
    fileprivate func syncMascotCalendar() {
        let countdown = NotchCalendarService.shared.countdown
        defer { mascotSawCountdown = countdown }
        guard NotchMascotSupport.eventBegan(from: mascotSawCountdown, to: countdown, at: Date()) else { return }
        reactMascot(.bounce)
    }

    /// Music started: once the song's strip has settled, the companion comes
    /// out to bob along, if the music still plays, at most once in a while.
    fileprivate func mascotHearsMusic() {
        let now = CACurrentMediaTime()
        guard NotchMascotSupport.reacts(), now - lastMascotGroove > NotchMascotSupport.grooveInterval else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + NotchMascotSupport.grooveDelay) { [weak self] in
            guard NotchMusicService.shared.playback?.isPlaying == true else { return }
            self?.reactMascot(.groove, patience: 3)
        }
    }

    /// Something happened the companion can react to. It plays where it
    /// rests, or out from behind the camera over whatever the closed island
    /// shows, now or as soon as the island closes again, if it does soon
    /// enough, and never twice in a row.
    /// `delay` holds it back a moment, so a reaction asked for right after
    /// takes its place, as a command's own does the Command Bar's cheer.
    func reactMascot(_ reaction: NotchMascotReaction, patience: TimeInterval = NotchMascotReactionGate.patience,
                     after delay: TimeInterval = 0) {
        guard NotchMascotSupport.reacts() else { return }
        // A notice on screen that shows the companion plays it there already.
        if notice?.mascot == reaction, noticeCanPresent {
            _ = mascotReactionGate.admits(reaction, at: CACurrentMediaTime())
            return
        }
        let now = CACurrentMediaTime()
        pendingMascotReaction = (reaction, now + delay + patience, now + delay)
        flushMascotReaction()
    }

    /// Hands a waiting reaction to the companion once the closed island shows
    /// with room for it, and no visit is under way. A countdown it watches
    /// ends once the timer's strip is no longer the one the island shows.
    fileprivate func flushMascotReaction() {
        if mascotVisit?.kind.watchesTimer == true, compactActivity != .timer {
            endMascotCountdown(retreating: false)
        }
        guard let pending = pendingMascotReaction else { return }
        let now = CACurrentMediaTime()
        guard now <= pending.deadline, NotchMascotSupport.reacts() else { pendingMascotReaction = nil; return }
        guard now >= pending.notBefore else {
            mascotReactionFlushWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.mascotReactionFlushWork = nil
                self?.flushMascotReaction()
            }
            mascotReactionFlushWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + (pending.notBefore - now), execute: work)
            return
        }
        guard mascotVisit == nil, mascotResidentShows || canHostMascotVisit() else { return }
        // Back at rest as the activity that held its place leaves, it
        // crossfades in there first, and a hop played at once would be half
        // seen over the strip going away: the reaction waits until the island
        // draws it at rest and the crossfade is over.
        if mascotRestsInView, !mascotResidentShows, !mascotBridging {
            guard mascotRestedInView else { return }
            let shows = mascotBackAtRest + NotchMascotMotion.restCrossfade
            if now < shows {
                pendingMascotReaction = (pending.reaction, max(pending.deadline, shows + 0.5), shows)
                flushMascotReaction()
                return
            }
        }
        pendingMascotReaction = nil
        guard mascotReactionGate.admits(pending.reaction, at: now) else { return }
        // Its wait for the next song counts from a groove it played, not one
        // that never came, as when music started right after another reaction.
        if pending.reaction == .groove { lastMascotGroove = now }
        // Open, it plays where the island keeps it beside the camera. An
        // activity that has just taken its place finds it still there.
        if mascotResidentShows || mascotRestsInView {
            let event = NotchMascotReactionEvent(id: UUID(), reaction: pending.reaction, start: now)
            mascotReaction = event
            // Standing in the window's own layer as the island opens or
            // closes, it plays the reaction there too, in step with the one
            // the page or the strip shows once the island settles.
            if mascotBridging { windowHost?.reactMascotBridge(event, lift: mascotBridgeLift) }
        } else {
            beginMascotCameo(pending.reaction, lingering: mascotJustRested && compactActivity != nil)
        }
    }

    /// The last seconds of a countdown the closed island shows: the companion
    /// comes out over the timer's mark and watches the reading run out. A
    /// capsule has no camera to come from, so it stays as it is.
    func watchMascotCountdown(remaining: TimeInterval) {
        guard NotchMascotSupport.reacts(), remaining > 1, mascotVisit == nil, compactActivity == .timer,
              !geometry.floats, canHostMascotVisit() else { return }
        let watch = NotchMascotVisit(id: UUID(), kind: .countdown(remaining), greeting: .idle,
                                     start: CACurrentMediaTime())
        setMascotVisit(watch)
        mascotVisitWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.endMascotVisit() }
        mascotVisitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + watch.duration, execute: work)
    }

    /// The countdown it watches ran out, stopped or went away. Paused, with
    /// its strip still there, it goes back behind the camera; otherwise the
    /// strip that held it is gone and so is it.
    func endMascotCountdown(retreating: Bool) {
        guard let visit = mascotVisit, case .countdown = visit.kind else { return }
        guard retreating, compactActivity == .timer, !geometry.floats else { endMascotVisit(); return }
        let retreat = NotchMascotVisit(id: UUID(), kind: .retreat, greeting: .idle, start: CACurrentMediaTime())
        setMascotVisit(retreat)
        mascotVisitWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.endMascotVisit() }
        mascotVisitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + retreat.duration, execute: work)
    }

    /// Over what the closed island shows, the companion comes out from behind
    /// the camera, plays `reaction` where it would rest, and goes back.
    private func beginMascotCameo(_ reaction: NotchMascotReaction, lingering: Bool = false) {
        let cameo = NotchMascotVisit(id: UUID(), kind: lingering ? .linger(reaction) : .cameo(reaction), greeting: .idle,
                                     start: CACurrentMediaTime())
        setMascotVisit(cameo)
        mascotVisitWork?.cancel()
        // Its last frame puts it behind the camera, and what it covered comes back.
        let work = DispatchWorkItem { [weak self] in self?.endMascotVisit() }
        mascotVisitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + cameo.duration, execute: work)
    }

    /// A visit starting or ending changes no shape, so what it walks over
    /// steps aside and comes back with its strip's short fade.
    private func setMascotVisit(_ visit: NotchMascotVisit?) {
        mascotStepBackWork?.cancel(); mascotStepBackWork = nil
        mascotVisit = visit
        mascotStepsAside = visit != nil
        refreshPresentation()
        // A cameo hands the strip back on its way home, timed from the
        // visit's own start, which its drawing follows.
        guard let visit, let handBack = NotchMascotMotion.handBack(of: visit.kind, floats: geometry.floats) else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.mascotStepBackWork = nil
            self?.mascotStepsAside = false
        }
        mascotStepBackWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, visit.start + handBack - CACurrentMediaTime()),
                                      execute: work)
    }

    /// Puts `window` just under the island's, so what grows out of its edge
    /// comes from behind it, and what rises into it goes behind it.
    func orderBelowIsland(_ window: NSWindow) {
        guard let panel, panel.isVisible else { window.orderFrontRegardless(); return }
        window.order(.below, relativeTo: panel.windowNumber)
    }

    /// The bar closed itself, and the island closes with it.
    func dismissCommandBar() {
        guard showingCommandBar else { return }
        collapse()
    }

    /// The island closed around the bar, from a click away or a page opened
    /// in its place, and the bar closes too.
    fileprivate func commandBarDidClose() {
        commandBarHeight = nil
        CommandBarService.shared.islandDidClose()
    }

    func updateCommandBarHeight(_ height: CGFloat) {
        guard showingCommandBar, height.isFinite, height > 0 else { return }
        let measured = ceil(height)
        guard commandBarHeight != measured else { return }
        commandBarHeight = measured
        refreshPresentation()
    }
}

extension NSScreen {
    var notchDisplayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
