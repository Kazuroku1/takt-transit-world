import SwiftUI
import UniformTypeIdentifiers
import TaktCore

private enum GameSheet: Identifiable {
    case settings, lines, fleet, world, quests, route(String)
    var id: String {
        switch self {
        case .settings: return "settings"
        case .lines: return "lines"
        case .fleet: return "fleet"
        case .world: return "world"
        case .quests: return "quests"
        case .route(let id): return "route-" + id
        }
    }
    var title: String {
        switch self {
        case .settings: return "Einstellungen"
        case .lines: return "Dein Liniennetz"
        case .fleet: return "Deine Flotte"
        case .world: return "Deine Schweiz"
        case .quests: return "Deine Aufgaben"
        case .route(let id): return "Linie \(Catalog.route(id)?.number ?? id)"
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var game: GameStore
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var sheet: GameSheet?
    @State private var cameraCommand = CameraCommand()
    @State private var sheetDetent: PresentationDetent = .large
    @State private var proposedRegion: String?

    private var compact: Bool { verticalSizeClass == .compact }
    private var cameraLayout: AnyLayout {
        compact ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
    }

    var body: some View {
        ZStack {
            NativeCityView(state: game.state, speed: game.active ? game.speed : 0,
                           cameraCommand: cameraCommand, selectedRoute: game.selectedRoute,
                           onSelect: { id in game.selectedRoute = id; sheet = .route(id) },
                           onRegionSelect: { id in proposedRegion = id; sheet = .world })
                .ignoresSafeArea()
            VStack(spacing: 10) {
                topControls
                Spacer(minLength: 0)
                bottomControls
            }
            .padding(.horizontal, compact ? 18 : 16)
            .padding(.top, 10).padding(.bottom, 10)
        }
        .foregroundStyle(TaktTheme.ink)
        .tint(TaktTheme.green)
        .overlay(alignment: .trailing) {
            cameraLayout {
                hudIcon("plus", "Vergrössern", "zoom-in") { cameraCommand = .init(action: .zoomIn) }
                if !compact { Divider().frame(width: 24) }
                hudIcon("minus", "Verkleinern", "zoom-out") { cameraCommand = .init(action: .zoomOut) }
                if !compact { Divider().frame(width: 24) }
                hudIcon("map", "Ganze Schweiz", "city-overview") { cameraCommand = .init(action: .reset) }
                hudIcon("location.fill", "Aktuelle Region", "region-focus") { cameraCommand = .init(action: .region) }
            }.hudSurface().padding(.trailing, compact ? 18 : 16)
        }
        .sheet(item: $sheet) { destination in
            if case .settings = destination {
                SettingsPage().presentationDetents([.large]).presentationDragIndicator(.visible)
            } else {
                NavigationStack {
                    sheetContent(destination)
                        .background(TaktTheme.background)
                        .navigationTitle(destination.title).navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Fertig") { sheet = nil }.accessibilityIdentifier("close-sheet")
                            }
                        }
                }
                .presentationDetents([.medium, .large], selection: $sheetDetent)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
                .tint(TaktTheme.green)
            }
        }
    }

    private var topControls: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                Button { proposedRegion = nil; sheet = .world } label: {
                    HStack(spacing: 7) {
                        Text(game.state.currentCity.name).font(.system(.headline, design: .rounded, weight: .bold))
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Image(systemName: "chevron.down").font(.caption2.bold())
                    }
                    .frame(minHeight: 44)
                }.accessibilityIdentifier("current-city").accessibilityHint("Die Schweiz Region für Region erschliessen")
                HStack(spacing: 6) {
                    Image(systemName: "circle.circle.fill").foregroundStyle(TaktTheme.gold)
                    Text(game.state.coins.taktNumber).monospacedDigit().fontWeight(.bold)
                    if !dynamicTypeSize.isAccessibilitySize {
                        Text("+\(game.state.income.taktNumber)/Min.").foregroundStyle(TaktTheme.muted)
                    }
                }.font(.caption)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Guthaben \(game.state.coins) Münzen, \(game.state.income) pro Minute")
                    .accessibilityIdentifier("wallet")
            }.padding(.horizontal, 14).padding(.vertical, 8).hudSurface()
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Button { sheet = .quests } label: {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 48, height: 48).hudSurface()
                        .overlay(alignment: .topTrailing) {
                        if game.readyCount > 0 {
                            Text("\(game.readyCount)").font(.caption2.bold()).foregroundStyle(.white)
                                .padding(5).background(TaktTheme.coral, in: Circle()).offset(x: 4, y: -4)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityLabel("Aufgaben").accessibilityIdentifier("open-quests")
                    .accessibilityValue("\(game.readyCount) Belohnungen bereit")
                hudIcon("slider.horizontal.3", "Einstellungen", "settings") { sheet = .settings }.hudSurface()
            }
        }
    }

    private var bottomControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let text = game.message {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").foregroundStyle(TaktTheme.coral)
                    Text(text).font(.caption.weight(.medium))
                    Button { game.message = nil } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                        .accessibilityLabel("Meldung schliessen")
                }.padding(.leading, 12).hudSurface().accessibilityIdentifier("game-notification")
            }
            if let event = game.state.event {
                Label("\(event.title) · +50 % · \(max(0, Int(event.endsAt - game.state.seconds))) s", systemImage: "bolt.fill")
                    .font(.caption.weight(.semibold)).padding(10).hudSurface()
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Button { sheet = .fleet } label: {
                        Label("Flotte", systemImage: "bus.fill").font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).frame(minHeight: 48)
                    }.hudSurface().accessibilityIdentifier("open-fleet")
                    HStack(spacing: 0) {
                        hudIcon(game.speed == 0 ? "play.fill" : "pause.fill", game.speed == 0 ? "Fortsetzen" : "Pausieren", "toggle-speed") {
                            game.speed = game.speed == 0 ? 1 : 0
                        }
                        Button { game.speed = game.speed >= 3 ? 1 : max(1, game.speed + 1) } label: {
                            Text("\(Int(max(1, game.speed)))×").font(.subheadline.bold()).monospacedDigit().frame(width: 44, height: 48)
                        }.accessibilityLabel("Geschwindigkeit ändern").accessibilityValue("\(Int(game.speed))-fach")
                            .accessibilityIdentifier("cycle-speed")
                    }.hudSurface()
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 8) {
                    Button { game.changeSettings { $0.night.toggle() } } label: {
                        Image(systemName: game.state.settings.night ? "moon.stars.fill" : "sun.max.fill")
                            .font(.system(size: 18, weight: .medium)).frame(width: 48, height: 48)
                    }.hudSurface().accessibilityLabel(game.state.settings.night ? "Nachtmodus" : "Tagesmodus")
                        .accessibilityHint("Tag oder Nacht wechseln").accessibilityIdentifier("city-lighting")
                    Button { sheet = .lines } label: {
                        Label(dynamicTypeSize.isAccessibilitySize ? "Linie" : "Linie freischalten", systemImage: "plus")
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .padding(.horizontal, 18).frame(minHeight: 56)
                            .foregroundStyle(.white).background(TaktTheme.green, in: RoundedRectangle(cornerRadius: 20))
                            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.25)))
                            .shadow(color: TaktTheme.ink.opacity(0.18), radius: 14, y: 5)
                    }.accessibilityLabel("Linie freischalten").accessibilityIdentifier("open-lines")
                }
            }
            if !compact && !dynamicTypeSize.isAccessibilitySize {
                Text("Wischen zum Erkunden · Zwei Finger zum Zoomen")
                    .font(.caption2).foregroundStyle(TaktTheme.ink)
                    .padding(.horizontal, 10).padding(.vertical, 6).hudSurface()
                    .frame(maxWidth: .infinity).allowsHitTesting(false)
            }
        }
    }

    private func hudIcon(_ symbol: String, _ label: String, _ identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
                .frame(width: 48, height: 48).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(label).accessibilityIdentifier(identifier)
    }

    @ViewBuilder private func sheetContent(_ destination: GameSheet) -> some View {
        switch destination {
        case .lines:
            LinesPage { id in game.selectedRoute = id; cameraCommand = .init(action: .focusRoute(id)); sheet = nil }
        case .fleet: FleetPage()
        case .world: WorldPage(initialRegion: proposedRegion) { cameraCommand = .init(action: .region); sheet = nil }
        case .quests: QuestsPage()
        case .settings: EmptyView()
        case .route(let id):
            if let route = Catalog.route(id) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        RouteCard(route: route, onView: { cameraCommand = .init(action: .focusRoute(id)); sheet = nil })
                        Card {
                            VStack(alignment: .leading, spacing: 18) {
                                Eyebrow(text: "Deine feste Strecke")
                                ForEach(Array(route.stopNames(in: game.state.cityID).enumerated()), id: \.offset) { _, name in
                                    Label(name, systemImage: "circle.inset.filled").foregroundStyle(Color(hex: route.colorHex))
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if route.kind == .metro {
                            Text("Die Metro wird als transparente Untergrundansicht dargestellt, damit du ihre Bewegung sehen kannst.")
                                .font(.footnote).foregroundStyle(TaktTheme.muted)
                        }
                    }.padding(20)
                }
            }
        }
    }
}

struct QuestSpotlight: View {
    @EnvironmentObject private var game: GameStore
    let quest: Quest
    let openQuests: () -> Void
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack { Eyebrow(text: "Dein nächster Meilenstein"); Spacer(); Image(systemName: "flag.checkered").font(.title2).foregroundStyle(TaktTheme.coral) }
                Text(quest.title).font(.system(.title2, design: .rounded, weight: .semibold))
                Text(quest.detail).font(.subheadline).foregroundStyle(TaktTheme.muted)
                HStack { ProgressView(value: quest.fraction).tint(TaktTheme.green); Text("\(quest.progress)/\(quest.target)").font(.caption).monospacedDigit() }
                HStack { Label("+\(quest.reward.taktNumber)", systemImage: "circle.circle.fill").foregroundStyle(Color(hex: 0xB99745)); Label("+\(quest.xp) XP", systemImage: "sparkles").foregroundStyle(TaktTheme.muted); Spacer() }.font(.caption.weight(.semibold))
                Button { quest.ready ? game.perform(.claim(quest.id)) : openQuests() } label: { HStack { Text(quest.ready ? "Belohnung abholen" : "Alle Aufgaben ansehen"); Spacer(); Image(systemName: quest.ready ? "checkmark" : "arrow.right") }.padding(.horizontal, 15) }.buttonStyle(TaktButtonStyle(secondary: !quest.ready))
            }
        }
    }
}

struct PageHeading: View {
    let eyebrow: String; let title: String; let detail: String
    var body: some View { VStack(alignment: .leading, spacing: 10) { Eyebrow(text: eyebrow); Text(title).font(.system(.title, design: .rounded, weight: .bold)); Text(detail).font(.subheadline).foregroundStyle(TaktTheme.muted).lineSpacing(3) }.frame(maxWidth: .infinity, alignment: .leading) }
}
struct WalletStrip: View {
    @EnvironmentObject private var game: GameStore
    var body: some View {
        HStack { Label("\(game.state.currentLines.count) aktiv", systemImage: "point.topleft.down.to.point.bottomright.curvepath"); Spacer(); Label(game.state.coins.taktNumber, systemImage: "circle.circle.fill").monospacedDigit().accessibilityIdentifier("wallet-strip") }
            .font(.subheadline.weight(.medium)).foregroundStyle(TaktTheme.green).padding(15).background(TaktTheme.pale, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct LinesPage: View {
    @EnvironmentObject private var game: GameStore
    @State private var filter: VehicleKind?
    let onView: (String) -> Void
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 17) {
                PageHeading(eyebrow: "Dein Liniennetz", title: "Jede Linie verbindet.", detail: "Feste Strecken. Neue Möglichkeiten. Entscheide, welche Verbindung als Nächstes fährt.")
                WalletStrip()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterButton(nil)
                        ForEach(game.state.currentCity.allowedKinds) { filterButton($0) }
                    }
                }
                ForEach(Catalog.routes(in: game.state.cityID).filter { filter == nil || $0.kind == filter }) { route in RouteCard(route: route, onView: { onView(route.id) }) }
                Text("Alle Strecken und Haltestellen stehen fest. Zusätzliche Fahrzeuge erhöhen Kapazität und Einnahmen.").font(.footnote).foregroundStyle(TaktTheme.muted).padding(.vertical, 8)
            }.padding(20)
        }
    }
    private func filterButton(_ kind: VehicleKind?) -> some View {
        Button { filter = kind } label: { HStack(spacing: 6) { if let kind { Image(systemName: kind.symbol) }; Text(kind?.title ?? "Alle") }.font(.subheadline.weight(.medium)).padding(.horizontal, 14).frame(height: 43).background(filter == kind ? TaktTheme.pale : TaktTheme.paper, in: Capsule()) }.buttonStyle(.plain)
    }
}

struct RouteCard: View {
    @EnvironmentObject private var game: GameStore
    let route: TransitRoute
    let onView: (() -> Void)?
    var body: some View {
        let own = game.state.owned(route.id)
        let unlockReason = GameRules.unlockReason(route: route, state: game.state)
        let locked = own == nil && unlockReason != nil
        let stops = route.stopNames(in: game.state.cityID)
        Card {
            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 9) {
                    Text(route.number).font(.system(.subheadline, design: .rounded, weight: .bold)).foregroundStyle(.white).padding(.horizontal, 11).frame(height: 30).background(Color(hex: route.colorHex), in: RoundedRectangle(cornerRadius: 8))
                    Label(route.kind.title, systemImage: route.kind.symbol).font(.caption).foregroundStyle(TaktTheme.muted)
                    Spacer()
                    if own != nil {
                        Label("In Betrieb", systemImage: "checkmark.circle.fill").font(.caption2.weight(.medium)).foregroundStyle(TaktTheme.green).accessibilityIdentifier("route-\(route.id)-owned")
                    } else if locked { Image(systemName: "lock.fill").font(.caption).foregroundStyle(TaktTheme.muted) }
                }
                Text(route.name).font(.system(.title3, design: .rounded, weight: .semibold))
                HStack(spacing: 7) {
                    Circle().stroke(Color(hex: route.colorHex), lineWidth: 2).frame(width: 7, height: 7)
                    Text(stops.first!).font(.subheadline.weight(.medium)).lineLimit(1).minimumScaleFactor(0.7)
                    Rectangle().fill(TaktTheme.border).frame(height: 1).frame(minWidth: 8)
                    Text(stops.last!).font(.subheadline.weight(.medium)).lineLimit(1).minimumScaleFactor(0.7)
                    Circle().fill(Color(hex: route.colorHex)).frame(width: 7, height: 7)
                }
                Text(stops.joined(separator: " · ")).font(.caption).foregroundStyle(TaktTheme.muted)
                Text(route.spatialNote(in: game.state.cityID)).font(.caption2).foregroundStyle(TaktTheme.muted)
                if locked, let unlockReason {
                    Label(unlockReason, systemImage: "lock.fill").font(.caption.weight(.medium)).foregroundStyle(TaktTheme.green)
                }
                HStack(spacing: 13) {
                    Label("\(stops.count) Stopps", systemImage: "mappin")
                    Label("\(route.capacity * (own?.tier ?? 1))/Fahrt", systemImage: "person.2")
                    Spacer(minLength: 0)
                    Text("\(route.incomePerMinute(tier: own?.tier ?? 1).taktNumber)/Min.")
                }.font(.caption2).foregroundStyle(TaktTheme.muted)
                if let own {
                    HStack(spacing: 10) {
                        if let onView { Button(action: onView) { Image(systemName: "location.fill").frame(width: 45, height: 46).background(TaktTheme.pale, in: RoundedRectangle(cornerRadius: 12)) }.accessibilityLabel("Linie \(route.number) in der Stadt ansehen").accessibilityIdentifier("view-\(route.id)") }
                        Button { game.perform(.upgrade(route.id)) } label: {
                            HStack { Image(systemName: own.tier == 5 ? "checkmark" : "plus"); Text(own.tier == 5 ? "Voll ausgebaut" : "Fahrzeug"); Spacer(); if own.tier < 5 { Text("\(route.upgradePrice(tier: own.tier).taktNumber) ₮").monospacedDigit() } }.padding(.horizontal, 13)
                        }.buttonStyle(TaktButtonStyle()).disabled(own.tier == 5 || game.state.coins < route.upgradePrice(tier: own.tier)).opacity(own.tier == 5 || game.state.coins < route.upgradePrice(tier: own.tier) ? 0.45 : 1).accessibilityIdentifier("upgrade-\(route.id)")
                    }
                    HStack { Text("\(own.carried.taktNumber) Fahrgäste befördert"); Spacer(); Text("\(own.tier)/5 Fahrzeuge") }.font(.caption2).foregroundStyle(TaktTheme.muted)
                } else {
                    Button { game.perform(.buy(route.id)) } label: { HStack { Image(systemName: locked ? "lock.fill" : "plus"); Text(locked ? "Noch gesperrt" : "Freischalten"); Spacer(); Text("\(route.price.taktNumber) ₮").monospacedDigit() }.padding(.horizontal, 13) }
                        .buttonStyle(TaktButtonStyle(secondary: locked)).disabled(locked || game.state.coins < route.price).opacity(!locked && game.state.coins < route.price ? 0.45 : 1).accessibilityIdentifier("buy-\(route.id)")
                }
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("route-\(route.id)")
    }
}

struct QuestsPage: View {
    @EnvironmentObject private var game: GameStore
    @State private var done = false
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                PageHeading(eyebrow: "Der Weg ist das Ziel", title: "Ein Ziel vor Augen.", detail: "Bewege etwas. Jede Aufgabe bringt dein Verkehrsnetz einen Schritt weiter.")
                Card {
                    HStack(spacing: 16) {
                        SoftIcon(name: "trophy.fill", color: Color(hex: 0xB99D58))
                        VStack(alignment: .leading, spacing: 9) {
                            HStack { Text("Level \(game.state.level)").font(.headline); Spacer(); Text("\(game.state.xp.taktNumber) XP").font(.caption).monospacedDigit() }
                            ProgressView(value: game.state.levelProgress)
                            Text("Noch \((GameState.xpNeeded(for: game.state.level + 1)-game.state.xp).taktNumber) XP bis zum nächsten Level.").font(.caption2).foregroundStyle(TaktTheme.muted)
                        }
                    }
                }
                Label("\(game.state.passengers.taktNumber) Fahrgäste befördert", systemImage: "person.2.fill").font(.subheadline).foregroundStyle(TaktTheme.green)
                Picker("Aufgaben", selection: $done) { Text("In Arbeit").tag(false); Text("Geschafft").tag(true) }.pickerStyle(.segmented)
                ForEach(game.quests.filter { game.state.claimed.contains($0.id) == done }) { quest in
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack { Eyebrow(text: quest.id.hasPrefix("daily-") ? "Tagesaufgabe" : "Meilenstein"); Spacer(); Image(systemName: done ? "checkmark.seal.fill" : "flag").foregroundStyle(TaktTheme.coral) }
                            Text(quest.title).font(.headline)
                            Text(quest.detail).font(.subheadline).foregroundStyle(TaktTheme.muted)
                            if !done { HStack { ProgressView(value: quest.fraction); Text("\(quest.progress)/\(quest.target)").font(.caption).monospacedDigit() } }
                            HStack {
                                Label("+\(quest.reward.taktNumber)", systemImage: "circle.circle.fill").foregroundStyle(Color(hex: 0xB99745))
                                Text("+\(quest.xp) XP").foregroundStyle(TaktTheme.muted)
                                Spacer()
                                if done { Text("Abgeholt").foregroundStyle(TaktTheme.green) }
                            }.font(.caption.weight(.medium))
                            if !done {
                                Button { game.perform(.claim(quest.id)) } label: { Text(quest.ready ? "Belohnung abholen" : "In Arbeit") }
                                    .buttonStyle(TaktButtonStyle(secondary: !quest.ready)).disabled(!quest.ready).accessibilityIdentifier("claim-\(quest.id)")
                            }
                        }
                    }
                }
                if done && !game.quests.contains(where: { game.state.claimed.contains($0.id) }) {
                    ContentUnavailableView("Deine erste Geschichte wartet", systemImage: "flag", description: Text("Hole eine Quest-Belohnung ab. Danach findest du sie hier."))
                }
            }.padding(20)
        }
    }
}

struct FleetPage: View {
    @EnvironmentObject private var game: GameStore
    @State private var chosen: VehicleKind?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeading(eyebrow: "Dein Fuhrpark", title: "Vom Bergbus zum Fernverkehr.", detail: "Busse → Trams → S-Bahnen → Fernzüge → Flugzeuge. Dein Netz wächst mit jeder Region.")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145))], spacing: 14) {
                    ForEach(Catalog.playableKinds) { kind in
                        Button { chosen = kind } label: {
                            VStack(alignment: .leading, spacing: 11) {
                                ZStack {
                                    Circle().fill(Color(hex: kind.colorHex).opacity(0.1)).frame(width: 86, height: 86)
                                    Image(systemName: kind.symbol).font(.system(size: 47, weight: .light)).foregroundStyle(Color(hex: kind.colorHex))
                                }.frame(maxWidth: .infinity).padding(.vertical, 10)
                                Label(game.state.currentCity.allowedKinds.contains(kind) ? "In dieser Region" : "Spätere Region", systemImage: game.state.currentCity.allowedKinds.contains(kind) ? "mappin" : "lock").font(.caption2).foregroundStyle(TaktTheme.muted)
                                Text(kind.title).font(.system(.title3, design: .rounded, weight: .semibold))
                                Text(kind.motto).font(.caption).foregroundStyle(TaktTheme.muted).frame(minHeight: 42, alignment: .top)
                            }.padding(17).background(TaktTheme.paper, in: RoundedRectangle(cornerRadius: 21))
                                .overlay(RoundedRectangle(cornerRadius: 21).stroke(TaktTheme.border))
                        }.buttonStyle(.plain).accessibilityIdentifier("vehicle-\(kind.rawValue)")
                    }
                }
            }.padding(20)
        }
        .sheet(item: $chosen) { kind in
            NavigationStack {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        let routes = Catalog.routes(in: game.state.cityID).filter { $0.kind == kind }
                        if routes.isEmpty {
                            ContentUnavailableView("Dein Netz wächst weiter", systemImage: kind.symbol,
                                description: Text("Dieses Verkehrsmittel kommt in einer späteren Region hinzu. Beginne hier mit Bussen und erschliesse die Schweiz Schritt für Schritt."))
                        }
                        ForEach(routes) { RouteCard(route: $0, onView: nil) }
                    }.padding(20)
                }
                    .background(TaktTheme.background).navigationTitle(kind.title)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { chosen = nil }.accessibilityIdentifier("close-vehicle-detail") } }
            }.presentationDragIndicator(.visible)
        }
    }
}

struct WorldPage: View {
    @EnvironmentObject private var game: GameStore
    var initialRegion: String? = nil
    let didVisit: () -> Void
    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    PageHeading(eyebrow: "Dein Schweizer Verkehrsnetz", title: "Vom Bergdorf zur Schweiz.", detail: "Alles beginnt mit einem Bergbus in Andermatt. Erschliesse Täler, kleinere Orte und schliesslich die grossen Städte.")
                    HStack {
                        Label("\(game.state.networks.count) von \(Catalog.cities.count) Regionen", systemImage: "map")
                        Spacer()
                        Label(game.state.coins.taktNumber, systemImage: "circle.circle.fill")
                    }.font(.caption.weight(.medium)).foregroundStyle(TaktTheme.green)
                    WorldMap(discovered: Set(game.state.networks.keys)).frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 23))
                    ForEach(Array(Catalog.cities.enumerated()), id: \.element.id) { index, city in
                        let unlocked = game.state.networks[city.id] != nil
                        let current = game.state.cityID == city.id
                        let reason = game.state.regionUnlockReason(cityID: city.id)
                        let blocked = reason != nil || game.state.coins < city.price
                        Card {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack(spacing: 12) {
                                    Text(String(format: "%02d", index + 1))
                                        .font(.system(.title2, design: .rounded, weight: .bold))
                                        .foregroundStyle(unlocked ? TaktTheme.green : TaktTheme.muted)
                                        .frame(width: 50, height: 53).background(Color(hex: city.tint).opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(city.name).font(.system(.title2, design: .rounded, weight: .semibold))
                                        Text(city.country).font(.caption).foregroundStyle(TaktTheme.muted)
                                    }
                                    Spacer()
                                    Image(systemName: current ? "location.fill" : unlocked ? "checkmark.circle.fill" : "lock.fill").foregroundStyle(unlocked ? TaktTheme.green : TaktTheme.muted)
                                }
                                Text(city.motto).font(.subheadline).foregroundStyle(TaktTheme.muted)
                                HStack(spacing: 12) {
                                    ForEach(city.allowedKinds) { kind in
                                        Image(systemName: kind.symbol).accessibilityLabel(kind.title)
                                    }
                                }.foregroundStyle(TaktTheme.green)
                                if !unlocked, let reason {
                                    Label(reason, systemImage: "lock.fill").font(.caption.weight(.medium)).foregroundStyle(TaktTheme.muted)
                                }
                                Button {
                                    game.perform(.visit(city.id))
                                    if game.state.cityID == city.id { didVisit() }
                                } label: {
                                    HStack {
                                        Text(current ? "Aktuelle Region" : unlocked ? "Zum Verkehrsnetz" : "Region erschliessen")
                                        Spacer()
                                        if !unlocked { Text("\(city.price.taktNumber) ₮") }
                                        else if !current { Image(systemName: "arrow.right") }
                                    }.padding(.horizontal, 14)
                                }.buttonStyle(TaktButtonStyle(secondary: unlocked))
                                    .disabled(current || (!unlocked && blocked))
                                    .opacity(current || (!unlocked && blocked) ? 0.5 : 1)
                                    .accessibilityIdentifier("visit-\(city.id)")
                            }
                        }.id(city.id)
                    }
                    Text("Jede neue Region beginnt mit Bussen. Alle erschlossenen Netze verdienen gleichzeitig, solange du spielst. Die ganze Schweiz bleibt auf derselben Karte.")
                        .font(.footnote).foregroundStyle(TaktTheme.muted)
                }.padding(20)
            }
            .onAppear {
                if let initialRegion { reader.scrollTo(initialRegion, anchor: .top) }
            }
        }
    }
}

struct WorldMap: View {
    let discovered: Set<String>
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(TaktTheme.pale))
            let bounds = SwissGeography.bounds
            let scale = min((size.width-24)/(bounds[2]-bounds[0]), (size.height-24)/(bounds[3]-bounds[1]))
            let width = (bounds[2]-bounds[0])*scale, height = (bounds[3]-bounds[1])*scale
            func screen(_ point: MapPoint) -> CGPoint {
                CGPoint(x: (size.width-width)/2+(point.x-bounds[0])*scale,
                        y: (size.height-height)/2+(point.z-bounds[1])*scale)
            }
            for ring in SwissGeography.outline {
                var path = Path(); path.addLines(ring.map(screen)); path.closeSubpath()
                context.fill(path, with: .color(Color(hex: 0xBFCEAE)))
                context.stroke(path, with: .color(TaktTheme.green.opacity(0.25)), lineWidth: 1)
            }
            for city in Catalog.cities {
                let center = screen(city.mapCenter)
                if let previousID = city.predecessorID {
                    let previous = screen(Catalog.city(previousID).mapCenter)
                    var path = Path(); path.move(to: previous); path.addLine(to: center)
                    context.stroke(path, with: .color(discovered.contains(city.id) ? TaktTheme.green : TaktTheme.muted.opacity(0.35)), style: StrokeStyle(lineWidth: 1.5, dash: discovered.contains(city.id) ? [] : [3,3]))
                }
                let radius = discovered.contains(city.id) ? 5.0 : 3.0
                context.fill(Path(ellipseIn: CGRect(x: center.x-radius,y: center.y-radius,width: radius*2,height: radius*2)),
                             with: .color(discovered.contains(city.id) ? TaktTheme.coral : TaktTheme.muted))
            }
        }.accessibilityLabel("Schweizkarte. \(discovered.count) von \(Catalog.cities.count) Regionen erschlossen.")
    }
}

struct SettingsPage: View {
    @EnvironmentObject private var game: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false
    @State private var importing = false
    @State private var pendingImport: GameState?
    @State private var share: ShareFile?
    var body: some View {
        NavigationStack {
            Form {
                Section("Dein Spielgefühl") {
                    Toggle("Abendstimmung", isOn: setting(\.night))
                    Toggle("Erfolgstöne", isOn: setting(\.sound))
                    Toggle("Haptisches Feedback", isOn: setting(\.haptics))
                    Toggle("Ruhigere Animationen", isOn: setting(\.reducedMotion))
                }
                Section {
                    Label(game.saveIssue ?? "Automatisch auf diesem Gerät gespeichert", systemImage: game.saveIssue == nil ? "checkmark.shield" : "exclamationmark.triangle").font(.subheadline)
                    Button { do { share = ShareFile(url: try game.exportURL()) } catch { game.notify(error.localizedDescription, success: false) } } label: { Label("Spielstand exportieren", systemImage: "square.and.arrow.up") }
                    Button { importing = true } label: { Label("Spielstand importieren", systemImage: "square.and.arrow.down") }
                } header: { Text("Dein Verkehrsnetz") } footer: { Text("Der native Swift-Spielstand ist unabhängig vom bisherigen Browser-Spielstand. Die Simulation pausiert, sobald du die App verlässt.") }
                Section("So geht’s") {
                    helpRow("1", "Linien kaufen", "Dein erster Bus fährt schon. Kaufe weitere feste Strecken im Liniennetz.")
                    helpRow("2", "Aufgaben abholen", "Für Meilensteine erhältst du Münzen und XP. Hole sie unter Aufgaben ab.")
                    helpRow("3", "Weiter wachsen", "Erschliesse vom Bergdorf aus eine Region nach der anderen. Busse, Trams, S-Bahnen, Fernzüge und Flugzeuge bauen aufeinander auf.")
                    helpRow("4", "Die Schweiz entdecken", "Mit einem Finger verschieben, mit zwei Fingern zoomen oder drehen. Ganze Schweiz zeigt das Land; Aktuelle Region bringt dich zurück. Tippe ein Fahrzeug für Details an.")
                }
                Section("Karte und Daten") {
                    Text("Schweiz-Übersicht: Natural Earth (Public Domain). Andermatt: © OpenStreetMap-Mitwirkende (ODbL). Zürich: Stadt Zürich, amtliche Vermessung (CCZero). Höhen und Berge sind gestalterisch angenähert. Weitere Regionen und viele Linienverläufe sind für das Spiel stilisiert.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Link("OpenStreetMap: Mitwirkende und Lizenz", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
                    Link("Natural Earth", destination: URL(string: "https://www.naturalearthdata.com/about/terms-of-use/")!)
                    Link("Geodaten der Stadt Zürich", destination: URL(string: "https://data.stadt-zuerich.ch/dataset/geo_amtliche_vermessung_stadt_zuerich")!)
                }
                Section { Button("Spielstand zurücksetzen", role: .destructive) { confirmReset = true }.accessibilityIdentifier("reset-game") }
                Section { HStack { Text("takt.").font(.title.bold()); Spacer(); Text("Swift · Version 0.4.0").font(.caption).foregroundStyle(.secondary) } }
            }
            .navigationTitle("Ganz in deinem Takt.").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() }.accessibilityIdentifier("close-sheet") } }
            .confirmationDialog("Deinen gesamten Spielstand löschen?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Neu in Andermatt anfangen", role: .destructive) { game.reset(); dismiss() }
                Button("Behalten", role: .cancel) {}
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do { pendingImport = try game.readImport(result.get()) } catch { game.notify("Dieser Spielstand konnte nicht gelesen werden.", success: false) }
            }
            .alert("Spielstand ersetzen?", isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }), presenting: pendingImport) { imported in
                Button("Abbrechen", role: .cancel) { pendingImport = nil }
                Button("Importieren", role: .destructive) { game.acceptImport(imported); pendingImport = nil }
            } message: { _ in Text("Dein aktuelles Verkehrsnetz wird durch den ausgewählten Swift-Spielstand ersetzt.") }
            .sheet(item: $share) { ShareView(url: $0.url) }
        }
    }
    private func setting(_ key: WritableKeyPath<GameSettings,Bool>) -> Binding<Bool> { Binding(get: { game.state.settings[keyPath: key] }, set: { value in game.changeSettings { $0[keyPath: key] = value } }) }
    private func helpRow(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 13) { Text(number).font(.headline).foregroundStyle(TaktTheme.coral).frame(width: 20); VStack(alignment: .leading, spacing: 5) { Text(title).font(.subheadline.weight(.semibold)); Text(detail).font(.caption).foregroundStyle(.secondary) } }.padding(.vertical, 5)
    }
}
private struct ShareFile: Identifiable { let url: URL; var id: URL { url } }
private struct ShareView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
