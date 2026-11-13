import SwiftUI
import Combine
import AudioToolbox
import TaktCore

@MainActor
final class GameStore: ObservableObject {
    @Published private(set) var state: GameState
    @Published var speed: Double = 1
    @Published var selectedRoute: String?
    @Published var message: String?
    @Published private(set) var saveIssue: String?
    @Published var active = true
    private let saveURL: URL
    private let isTesting: Bool
    private var lastTick = Date()
    private var tickCount = 0
    private var timer: AnyCancellable?
    private var messageTask: Task<Void, Never>?
    var day: String { GameRules.localDay(Date()) }
    var quests: [Quest] { GameRules.quests(state, day: day) }
    var openQuests: [Quest] { quests.filter { !state.claimed.contains($0.id) } }
    var readyCount: Int { openQuests.filter(\.ready).count }

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        isTesting = arguments.contains("--ui-testing")
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Takt", isDirectory: true)
        saveURL = folder.appendingPathComponent("native-save-v2.json")
        var restored = GameState()
        var warning: String?
        if !isTesting, FileManager.default.fileExists(atPath: saveURL.path) {
            do { restored = try SaveCodec.decode(Data(contentsOf: saveURL)) }
            catch {
                let backup = folder.appendingPathComponent("native-save-v2.backup.json")
                if let data = try? Data(contentsOf: backup), let safe = try? SaveCodec.decode(data) {
                    restored = safe; warning = "Der letzte sichere Spielstand wurde wiederhergestellt."
                } else {
                    warning = "Der Spielstand ist beschädigt. Eine Kopie wurde zur Wiederherstellung aufbewahrt."
                    let copy = folder.appendingPathComponent("damaged-\(Int(Date().timeIntervalSince1970)).json")
                    try? FileManager.default.copyItem(at: saveURL, to: copy)
                }
            }
        }
        #if DEBUG
        if arguments.contains("--demo-all") {
            restored.coins = 25000; restored.xp = GameState.xpNeeded(for: 7)
            restored.networks["zurich"] = CityNetwork(lines: Catalog.routes.map { OwnedLine(id: $0.id) })
        }
        #endif
        state = restored; saveIssue = warning
        if arguments.contains("--freeze-clock") { speed = 0 }
        timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] date in
            self?.tick(at: date)
        }
    }

    private func tick(at now: Date) {
        let elapsed = now.timeIntervalSince(lastTick); lastTick = now
        guard active, speed > 0 else { return }
        let oldLevel = state.level
        var next = state
        GameRules.advance(&next, by: min(1.5,max(0,elapsed)) * speed, day: day)
        state = next
        tickCount += 1
        if tickCount % 5 == 0 { save() }
        if state.level > oldLevel { notify("Level \(state.level)! Dein Netz wächst.") }
    }

    func setActive(_ value: Bool) {
        active = value; lastTick = Date()
        if !value { save() }
    }
    func perform(_ action: GameAction) {
        let oldLevel = state.level
        do {
            var next = state
            try GameRules.apply(action, to: &next, day: day)
            state = next
            save()
            let text: String
            switch action {
            case .buy(let id): selectedRoute = id; text = "Linie \(Catalog.route(id)!.number) fährt jetzt. Gute Fahrt!"
            case .upgrade(let id): text = "Linie \(Catalog.route(id)!.number) hat Verstärkung bekommen."
            case .claim(let id): text = "Geschafft! +\(quests.first { $0.id == id }?.reward ?? 0) Münzen."
            case .visit(let id): selectedRoute = nil; text = "Willkommen in \(Catalog.city(id).name)."
            }
            notify(text + (state.level > oldLevel ? " Level \(state.level)!" : ""))
        } catch { notify(error.localizedDescription, success: false) }
    }
    func changeSettings(_ update: (inout GameSettings) -> Void) {
        // A Toggle may read its binding synchronously while Combine publishes.
        // Mutate a local value first, then publish one completed snapshot.
        var next = state
        update(&next.settings)
        state = next
        save()
    }
    func reset() {
        state = GameState(); selectedRoute = nil; speed = 1; save()
        notify("Ein frischer Start in Zürich.")
    }
    func notify(_ text: String, success: Bool = true) {
        messageTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { message = text }
        if state.settings.haptics && success { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        if state.settings.sound && success { AudioServicesPlaySystemSound(1057) }
        messageTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled else { return }
            withAnimation { self?.message = nil }
        }
    }
    func save() {
        guard !isTesting else { return }
        do {
            let folder = saveURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if let existing = try? Data(contentsOf: saveURL), (try? SaveCodec.decode(existing)) != nil {
                try existing.write(to: folder.appendingPathComponent("native-save-v2.backup.json"), options: [.atomic, .completeFileProtectionUnlessOpen])
            }
            try SaveCodec.encode(state).write(to: saveURL, options: [.atomic, .completeFileProtectionUnlessOpen])
            saveIssue = nil
        } catch { saveIssue = "Speichern nicht möglich. Bitte prüfe den freien Gerätespeicher." }
    }
    func exportURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Takt-Spielstand.json")
        try SaveCodec.encode(state).write(to: url, options: .atomic)
        return url
    }
    func readImport(_ url: URL) throws -> GameState {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size < 1_000_000 else { throw CocoaError(.fileReadTooLarge) }
        return try SaveCodec.decode(Data(contentsOf: url))
    }
    func acceptImport(_ imported: GameState) {
        guard imported.isValid else { return }
        state = imported; selectedRoute = nil; save(); notify("Dein Verkehrsnetz ist wieder da.")
    }
}

extension Int {
    var taktNumber: String { formatted(.number.locale(Locale(identifier: "de_CH"))) }
}
