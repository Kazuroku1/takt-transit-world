import SwiftUI
import UniformTypeIdentifiers
import TaktCore

enum GameTab: String, CaseIterable {
    case city, lines, fleet, world, quests
    var title: String { switch self { case .city: return "Stadt"; case .lines: return "Linien"; case .fleet: return "Flotte"; case .world: return "Welt"; case .quests: return "Aufgaben" } }
    var symbol: String { switch self { case .city: return "map.fill"; case .lines: return "point.topleft.down.to.point.bottomright.curvepath"; case .fleet: return "bus"; case .world: return "globe.europe.africa.fill"; case .quests: return "flag.checkered" } }
}
private enum GameSheet: Identifiable {
    case settings, route(String)
    var id: String { switch self { case .settings: return "settings"; case .route(let id): return id } }
}

struct RootView: View {
    @EnvironmentObject private var game: GameStore
    @State private var tab: GameTab = .city
    @State private var sheet: GameSheet?
    var body: some View {
        TabView(selection: $tab) {
            ForEach(GameTab.allCases, id: \.self) { item in
                NavigationStack {
                    content(for: item)
                        .background(TaktTheme.background)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                HStack(spacing: 2) {
                                    Text("takt").font(.system(size: 28, weight: .heavy, design: .rounded))
                                    Text(".").font(.system(size: 28, weight: .heavy, design: .rounded)).foregroundStyle(TaktTheme.coral)
                                    Text("DEIN NETZ.").font(.system(size: 8, weight: .semibold)).tracking(1.4).foregroundStyle(TaktTheme.muted).padding(.leading, 10)
                                }.foregroundStyle(TaktTheme.ink).accessibilityElement(children: .ignore).accessibilityLabel("Takt. Dein Verkehrsnetz.")
                            }
                            ToolbarItem(placement: .topBarTrailing) {
                                Button { sheet = .settings } label: { Image(systemName: "slider.horizontal.3").frame(width: 36, height: 36) }
                                    .accessibilityLabel("Einstellungen").accessibilityIdentifier("settings")
                            }
                        }
                        .toolbarBackground(TaktTheme.background, for: .navigationBar)
                        .navigationBarTitleDisplayMode(.inline)
                }
                .tabItem { Label(item.title, systemImage: item.symbol) }
                .tag(item)
                .badge(item == .quests ? game.readyCount : 0)
            }
        }
        .foregroundStyle(TaktTheme.ink)
        .overlay(alignment: .top) {
            if let text = game.message {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles").foregroundStyle(TaktTheme.coral)
                    Text(text).font(.subheadline.weight(.medium))
                    Button { withAnimation { game.message = nil } } label: { Image(systemName: "xmark").frame(width: 30, height: 35) }.accessibilityLabel("Meldung schliessen")
                }
                .padding(.leading, 17).padding(.trailing, 7).padding(.vertical, 10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(TaktTheme.border))
                .shadow(color: .black.opacity(0.08), radius: 15, y: 5)
                .padding(.horizontal, 16).padding(.top, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityIdentifier("game-notification")
            }
        }
        .sheet(item: $sheet) { destination in
            switch destination {
            case .settings: SettingsPage()
            case .route(let id):
                if let route = Catalog.route(id) {
                    NavigationStack {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                RouteCard(route: route, onView: nil)
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
                        }.background(TaktTheme.background)
                            .navigationTitle("Linie \(route.number)")
                            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { sheet = nil } } }
                    }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
                }
            }
        }
    }
    @ViewBuilder private func content(for tab: GameTab) -> some View {
        switch tab {
        case .city: CityPage(openLines: { self.tab = .lines }, openWorld: { self.tab = .world }, openQuests: { self.tab = .quests }, inspect: { id in game.selectedRoute = id; sheet = .route(id) })
        case .lines: LinesPage { id in game.selectedRoute = id; self.tab = .city }
        case .fleet: FleetPage()
        case .world: WorldPage { self.tab = .city }
        case .quests: QuestsPage()
        }
    }
}

struct CityPage: View {
    @EnvironmentObject private var game: GameStore
    @State private var cameraCommand = CameraCommand()
    let openLines: () -> Void
    let openWorld: () -> Void
    let openQuests: () -> Void
    let inspect: (String) -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 7) {
                        Eyebrow(text: "Deine kleine grosse Welt")
                        Button(action: openWorld) {
                            HStack(spacing: 8) {
                                Text(game.state.currentCity.name).font(.system(size: 32, weight: .bold, design: .rounded)).minimumScaleFactor(0.65).lineLimit(1)
                                Image(systemName: "chevron.down").font(.caption.weight(.bold))
                            }
                        }.foregroundStyle(TaktTheme.ink).accessibilityIdentifier("current-city")
                        Text("Einsteigen. Verbinden. Weiterdenken.").font(.caption).foregroundStyle(TaktTheme.muted)
                    }
                    Spacer(minLength: 10)
                    VStack(alignment: .trailing, spacing: 6) {
                        Label(game.state.coins.taktNumber, systemImage: "circle.circle.fill")
                            .font(.system(.title3, design: .rounded, weight: .bold)).monospacedDigit().foregroundStyle(Color(hex: 0xB99745))
                            .accessibilityLabel("Guthaben \(game.state.coins) Münzen").accessibilityIdentifier("wallet")
                        Text("+\(game.state.income.taktNumber)/Min.").font(.caption2.weight(.medium)).foregroundStyle(TaktTheme.green)
                    }
                }
                ZStack(alignment: .bottom) {
                    NativeCityView(state: game.state, speed: game.active ? game.speed : 0, cameraCommand: cameraCommand, selectedRoute: game.selectedRoute, onSelect: inspect)
                        .accessibilityLabel("Animierte Stadt. Mit einem Finger drehen, mit zwei Fingern zoomen. Fahrzeuge antippen für Details.")
                        .accessibilityIdentifier("native-city")
                    VStack {
                        HStack {
                            HStack(spacing: 6) { Circle().fill(TaktTheme.green).frame(width: 6, height: 6); Eyebrow(text: game.speed == 0 ? "Zeit zum Durchatmen" : "Deine Stadt lebt", color: game.state.settings.night ? .white.opacity(0.8) : TaktTheme.muted) }
                            Spacer()
                            Label("Tag \(Int(game.state.seconds / 240) + 1)", systemImage: game.state.settings.night ? "moon.stars.fill" : "sun.max.fill")
                                .font(.caption2.weight(.medium)).foregroundStyle(game.state.settings.night ? .white.opacity(0.8) : TaktTheme.muted)
                                .accessibilityLabel(game.state.settings.night ? "Nachtmodus" : "Tagesmodus").accessibilityIdentifier("city-lighting")
                        }
                        if let event = game.state.event {
                            HStack { Image(systemName: "bolt.fill"); Text("\(event.title) +50 % Einnahmen"); Spacer(); Text("\(max(0,Int(event.endsAt-game.state.seconds))) s").monospacedDigit() }
                                .font(.caption2.weight(.medium)).padding(10).background(Color(hex: 0xF6E8BD), in: Capsule())
                        }
                        Spacer()
                        HStack {
                            Spacer()
                            VStack(spacing: 0) {
                                mapButton("plus", "Vergrössern") { cameraCommand = .init(action: .zoomIn) }
                                mapButton("minus", "Verkleinern") { cameraCommand = .init(action: .zoomOut) }
                                Divider().frame(width: 25)
                                mapButton("arrow.up.left.and.arrow.down.right", "Kamera zurücksetzen") { cameraCommand = .init(action: .reset) }
                                mapButton(game.state.settings.night ? "sun.max" : "moon", "Tag oder Nacht wechseln") { game.changeSettings { $0.night.toggle() } }
                            }.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15))
                        }
                        Spacer()
                        HStack {
                            Label(game.state.currentCity.country, systemImage: "location").font(.caption2).foregroundStyle(game.state.settings.night ? .white.opacity(0.7) : TaktTheme.muted)
                            Spacer()
                            Text("\(game.state.currentLines.count) Linien aktiv").font(.caption2).foregroundStyle(game.state.settings.night ? .white.opacity(0.7) : TaktTheme.muted)
                        }
                        Button(action: openLines) { Label("Linie freischalten", systemImage: "plus") }
                            .buttonStyle(TaktButtonStyle()).accessibilityIdentifier("open-lines")
                    }.padding(17)
                }
                .frame(height: 420)
                .clipShape(RoundedRectangle(cornerRadius: 25))
                .overlay(RoundedRectangle(cornerRadius: 25).stroke(TaktTheme.border))

                HStack(spacing: 12) {
                    MetricCard(symbol: "person.2.fill", title: "Fahrgäste", value: game.state.passengers.taktNumber, color: TaktTheme.green)
                    MetricCard(symbol: "sparkles", title: "Netz-Pionier", value: "Level \(game.state.level)", color: TaktTheme.coral)
                }

                if let quest = game.openQuests.first(where: \.ready) ?? game.openQuests.first {
                    QuestSpotlight(quest: quest, openQuests: openQuests)
                }
                VStack(alignment: .leading, spacing: 11) {
                    HStack { Text("Deine Verbindungen").font(.title3.weight(.semibold)); Spacer(); Button("Alle Linien", action: openLines).font(.subheadline) }
                    ForEach(game.state.currentLines) { line in
                        if let route = Catalog.route(line.id) {
                            Button { inspect(line.id) } label: {
                                HStack(spacing: 12) {
                                    SoftIcon(name: route.kind.symbol, color: Color(hex: route.colorHex))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("\(route.number)  \(route.stopNames(in: game.state.cityID).first!)").font(.subheadline.weight(.semibold))
                                        Text("\(route.stopNames(in: game.state.cityID).last!) · \(line.tier) Fzg.").font(.caption).foregroundStyle(TaktTheme.muted)
                                    }
                                    Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(TaktTheme.muted)
                                }.padding(12).background(TaktTheme.paper, in: RoundedRectangle(cornerRadius: 16))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                HStack {
                    Eyebrow(text: "Dein Takt")
                    Spacer()
                    Button { game.speed = game.speed == 0 ? 1 : 0 } label: { Image(systemName: game.speed == 0 ? "play.fill" : "pause.fill").frame(width: 40, height: 44) }.accessibilityLabel(game.speed == 0 ? "Fortsetzen" : "Pausieren")
                    ForEach([1,2,3], id: \.self) { speed in
                        Button("\(speed)×") { game.speed = Double(speed) }
                            .font(.subheadline.weight(.semibold)).frame(width: 37, height: 38)
                            .background(game.speed == Double(speed) ? TaktTheme.pale : .clear, in: RoundedRectangle(cornerRadius: 9))
                            .accessibilityLabel("\(speed)-fache Geschwindigkeit")
                    }
                }
                Text("Kleine Wege. Grosse Geschichten.").font(.caption).foregroundStyle(TaktTheme.muted).frame(maxWidth: .infinity).padding(.bottom, 8)
            }.padding(.horizontal, 20).padding(.top, 12)
        }
    }
    private func mapButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 17, weight: .medium)).frame(width: 42, height: 43) }.accessibilityLabel(label)
    }
}

private struct MetricCard: View {
    let symbol: String; let title: String; let value: String; let color: Color
    var body: some View {
        HStack(spacing: 10) { SoftIcon(name: symbol, color: color); VStack(alignment: .leading, spacing: 4) { Text(title).font(.caption).foregroundStyle(TaktTheme.muted); Text(value).font(.system(.headline, design: .rounded)).monospacedDigit() }; Spacer(minLength: 0) }
            .padding(12).frame(maxWidth: .infinity).background(TaktTheme.paper, in: RoundedRectangle(cornerRadius: 17))
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
    var body: some View { VStack(alignment: .leading, spacing: 10) { Eyebrow(text: eyebrow); Text(title).font(.system(size: 29, weight: .bold, design: .rounded)); Text(detail).font(.subheadline).foregroundStyle(TaktTheme.muted).lineSpacing(3) }.frame(maxWidth: .infinity, alignment: .leading) }
}
struct WalletStrip: View {
    @EnvironmentObject private var game: GameStore
    var body: some View {
        HStack { Label("\(game.state.currentLines.count) aktiv", systemImage: "point.topleft.down.to.point.bottomright.curvepath"); Spacer(); Label(game.state.coins.taktNumber, systemImage: "circle.circle.fill").monospacedDigit().accessibilityIdentifier("wallet-strip") }
            .font(.subheadline.weight(.medium)).foregroundStyle(TaktTheme.green).padding(15).background(TaktTheme.pale, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct LinesPage: View {
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
                        ForEach(VehicleKind.allCases) { filterButton($0) }
                    }
                }
                ForEach(Catalog.routes.filter { filter == nil || $0.kind == filter }) { route in RouteCard(route: route, onView: { onView(route.id) }) }
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
        let locked = game.state.level < route.requiredLevel
        let stops = route.stopNames(in: game.state.cityID)
        Card {
            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 9) {
                    Text(route.number).font(.system(.subheadline, design: .rounded, weight: .bold)).foregroundStyle(.white).padding(.horizontal, 11).frame(height: 30).background(Color(hex: route.colorHex), in: RoundedRectangle(cornerRadius: 8))
                    Label(route.kind.title, systemImage: route.kind.symbol).font(.caption).foregroundStyle(TaktTheme.muted)
                    Spacer()
                    if own != nil {
                        Label("In Betrieb", systemImage: "checkmark.circle.fill").font(.caption2.weight(.medium)).foregroundStyle(TaktTheme.green).accessibilityIdentifier("route-\(route.id)-owned")
                    } else if locked { Label("Level \(route.requiredLevel)", systemImage: "lock.fill").font(.caption2).foregroundStyle(TaktTheme.muted) }
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
                HStack(spacing: 13) {
                    Label("\(stops.count) Stopps", systemImage: "mappin")
                    Label("\(route.capacity * (own?.tier ?? 1))/Fahrt", systemImage: "person.2")
                    Spacer(minLength: 0)
                    Text("\(route.incomePerMinute(tier: own?.tier ?? 1).taktNumber)/Min.")
                }.font(.caption2).foregroundStyle(TaktTheme.muted)
                if let own {
                    HStack(spacing: 10) {
                        if let onView { Button(action: onView) { Image(systemName: "location.fill").frame(width: 45, height: 46).background(TaktTheme.pale, in: RoundedRectangle(cornerRadius: 12)) }.accessibilityLabel("Linie \(route.number) in der Stadt ansehen") }
                        Button { game.perform(.upgrade(route.id)) } label: {
                            HStack { Image(systemName: own.tier == 5 ? "checkmark" : "plus"); Text(own.tier == 5 ? "Voll ausgebaut" : "Fahrzeug"); Spacer(); if own.tier < 5 { Text("\(route.upgradePrice(tier: own.tier).taktNumber) ₮").monospacedDigit() } }.padding(.horizontal, 13)
                        }.buttonStyle(TaktButtonStyle()).disabled(own.tier == 5 || game.state.coins < route.upgradePrice(tier: own.tier)).opacity(own.tier == 5 || game.state.coins < route.upgradePrice(tier: own.tier) ? 0.45 : 1).accessibilityIdentifier("upgrade-\(route.id)")
                    }
                    HStack { Text("\(own.carried.taktNumber) Fahrgäste befördert"); Spacer(); Text("\(own.tier)/5 Fahrzeuge") }.font(.caption2).foregroundStyle(TaktTheme.muted)
                } else {
                    Button { game.perform(.buy(route.id)) } label: { HStack { Image(systemName: locked ? "lock.fill" : "plus"); Text(locked ? "Ab Level \(route.requiredLevel)" : "Freischalten"); Spacer(); Text("\(route.price.taktNumber) ₮").monospacedDigit() }.padding(.horizontal, 13) }
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
                PageHeading(eyebrow: "Dein Fuhrpark", title: "Was bewegt dich?", detail: "Vom Quartierbus bis zum Flugzeug. Neue Level eröffnen neue Wege.")
                LazyVGrid(columns: [GridItem(.flexible()),GridItem(.flexible())], spacing: 14) {
                    ForEach(VehicleKind.allCases) { kind in
                        Button { chosen = kind } label: {
                            VStack(alignment: .leading, spacing: 11) {
                                ZStack {
                                    Circle().fill(Color(hex: kind.colorHex).opacity(0.1)).frame(width: 86, height: 86)
                                    Image(systemName: kind.symbol).font(.system(size: 47, weight: .light)).foregroundStyle(Color(hex: kind.colorHex))
                                }.frame(maxWidth: .infinity).padding(.vertical, 10)
                                Label(game.state.level >= kind.level ? "Verfügbar" : "Level \(kind.level)", systemImage: game.state.level >= kind.level ? "checkmark.circle" : "lock").font(.caption2).foregroundStyle(TaktTheme.muted)
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
                ScrollView { LazyVStack(spacing: 16) { ForEach(Catalog.routes.filter { $0.kind == kind }) { RouteCard(route: $0, onView: nil) } }.padding(20) }
                    .background(TaktTheme.background).navigationTitle(kind.title)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { chosen = nil } } }
            }.presentationDragIndicator(.visible)
        }
    }
}

struct WorldPage: View {
    @EnvironmentObject private var game: GameStore
    let didVisit: () -> Void
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                PageHeading(eyebrow: "Dein Verkehrs-Imperium", title: "Nächster Halt: die Welt.", detail: "Alles beginnt in Zürich. Wohin führt dein Netz als Nächstes?")
                HStack { Label("\(game.state.networks.count) von 8 Städten", systemImage: "globe.europe.africa"); Spacer(); Label(game.state.coins.taktNumber, systemImage: "circle.circle.fill") }.font(.caption.weight(.medium)).foregroundStyle(TaktTheme.green)
                WorldMap(discovered: Set(game.state.networks.keys)).frame(height: 190).clipShape(RoundedRectangle(cornerRadius: 23))
                ForEach(Catalog.cities) { city in
                    let unlocked = game.state.networks[city.id] != nil
                    let current = game.state.cityID == city.id
                    Card {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 12) {
                                Text(city.flag).font(.largeTitle).frame(width: 50, height: 53).background(Color(hex: city.tint).opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
                                VStack(alignment: .leading, spacing: 5) { Text(city.name).font(.system(.title2, design: .rounded, weight: .semibold)); Text(city.country).font(.caption).foregroundStyle(TaktTheme.muted) }
                                Spacer()
                                if current { Text("Du bist hier").font(.caption2.weight(.semibold)).foregroundStyle(TaktTheme.green) }
                                else if unlocked { Image(systemName: "checkmark.circle.fill").foregroundStyle(TaktTheme.green) }
                                else { Label("\(city.requiredLevel)", systemImage: "sparkles").font(.caption).foregroundStyle(TaktTheme.muted) }
                            }
                            Text(city.motto).font(.subheadline).foregroundStyle(TaktTheme.muted)
                            Button { game.perform(.visit(city.id)); if game.state.cityID == city.id { didVisit() } } label: {
                                HStack { Text(current ? "Aktuelle Stadt" : unlocked ? "Stadt besuchen" : game.state.level < city.requiredLevel ? "Ab Level \(city.requiredLevel)" : "Stadt erschliessen"); Spacer(); if !unlocked { Text("\(city.price.taktNumber) ₮") } else if !current { Image(systemName: "arrow.right") } }.padding(.horizontal, 14)
                            }.buttonStyle(TaktButtonStyle(secondary: unlocked)).disabled(current || (!unlocked && (game.state.level < city.requiredLevel || game.state.coins < city.price))).opacity(current || (!unlocked && (game.state.level < city.requiredLevel || game.state.coins < city.price)) ? 0.5 : 1).accessibilityIdentifier("visit-\(city.id)")
                        }
                    }
                }
                Text("Alle erschlossenen Städte verdienen gleichzeitig, solange das Spiel aktiv ist. Jede Stadt beginnt mit einer Buslinie. Die Miniaturwelten sind stilisiert.").font(.footnote).foregroundStyle(TaktTheme.muted)
            }.padding(20)
        }
    }
}

struct WorldMap: View {
    let discovered: Set<String>
    private let continents: [[CGPoint]] = [
        [.init(x:0.08,y:0.2),.init(x:0.17,y:0.08),.init(x:0.31,y:0.21),.init(x:0.27,y:0.38),.init(x:0.21,y:0.48),.init(x:0.13,y:0.33)],
        [.init(x:0.23,y:0.48),.init(x:0.31,y:0.45),.init(x:0.35,y:0.6),.init(x:0.28,y:0.92),.init(x:0.24,y:0.75)],
        [.init(x:0.43,y:0.22),.init(x:0.49,y:0.14),.init(x:0.57,y:0.23),.init(x:0.54,y:0.35),.init(x:0.47,y:0.38)],
        [.init(x:0.46,y:0.39),.init(x:0.53,y:0.36),.init(x:0.58,y:0.48),.init(x:0.53,y:0.72),.init(x:0.48,y:0.65),.init(x:0.45,y:0.51)],
        [.init(x:0.55,y:0.22),.init(x:0.67,y:0.12),.init(x:0.89,y:0.22),.init(x:0.93,y:0.33),.init(x:0.82,y:0.4),.init(x:0.76,y:0.54),.init(x:0.69,y:0.42),.init(x:0.61,y:0.34)],
        [.init(x:0.83,y:0.74),.init(x:0.9,y:0.68),.init(x:0.95,y:0.81),.init(x:0.9,y:0.87),.init(x:0.84,y:0.84)]
    ]
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(TaktTheme.pale))
            for polygon in continents {
                var path = Path(); path.addLines(polygon.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }); path.closeSubpath()
                context.fill(path, with: .color(Color(hex: 0xC3D1B5)))
            }
            for city in Catalog.cities {
                let x = city.x * size.width, y = city.y * size.height
                let radius = discovered.contains(city.id) ? 5.0 : 3.0
                context.fill(Path(ellipseIn: CGRect(x: x-radius, y: y-radius, width: radius*2, height: radius*2)), with: .color(discovered.contains(city.id) ? TaktTheme.coral : TaktTheme.muted.opacity(0.4)))
            }
        }.accessibilityLabel("Weltkarte. \(discovered.count) von acht Städten freigeschaltet.")
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
                    helpRow("3", "Weiter wachsen", "Neue Level eröffnen Verkehrsmittel und Städte. Zusätzliche Fahrzeuge verdienen mehr.")
                    helpRow("4", "Die Stadt entdecken", "Mit einem Finger drehen, mit zwei Fingern zoomen. Tippe ein Fahrzeug für Details an.")
                }
                Section { Button("Spielstand zurücksetzen", role: .destructive) { confirmReset = true }.accessibilityIdentifier("reset-game") }
                Section { HStack { Text("takt.").font(.title.bold()); Spacer(); Text("Swift · Version 0.2.0").font(.caption).foregroundStyle(.secondary) } }
            }
            .navigationTitle("Ganz in deinem Takt.").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
            .confirmationDialog("Deinen gesamten Spielstand löschen?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Neu in Zürich anfangen", role: .destructive) { game.reset(); dismiss() }
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
