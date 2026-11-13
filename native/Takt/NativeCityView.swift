import SwiftUI
import RealityKit
import UIKit
import TaktCore

struct CameraCommand: Equatable {
    enum Action: Equatable { case reset, zoomIn, zoomOut, focusRoute(String) }
    let id = UUID()
    var action: Action = .reset
}

@MainActor
struct NativeCityView: UIViewRepresentable {
    let state: GameState
    let speed: Double
    let cameraCommand: CameraCommand
    let selectedRoute: String?
    let onSelect: (String) -> Void

    func makeCoordinator() -> CityRenderer { CityRenderer() }
    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.accessibilityIdentifier = "native-city"
        view.accessibilityLabel = "Stadtkarte"
        view.accessibilityHint = "Mit einem Finger verschieben, mit zwei Fingern zoomen und drehen."
        view.isAccessibilityElement = true
        context.coordinator.attach(view)
        context.coordinator.update(state: state, speed: speed, command: cameraCommand, selected: selectedRoute, onSelect: onSelect)
        return view
    }
    func updateUIView(_ view: ARView, context: Context) {
        context.coordinator.update(state: state, speed: speed, command: cameraCommand, selected: selectedRoute, onSelect: onSelect)
    }
    static func dismantleUIView(_ view: ARView, coordinator: CityRenderer) { coordinator.stop() }
}

@MainActor
final class CityRenderer: NSObject, UIGestureRecognizerDelegate {
    private weak var view: ARView?
    private weak var loadingLabel: UILabel?
    private let anchor = AnchorEntity(world: .zero)
    private let camera = PerspectiveCamera()
    private let sun = DirectionalLight()
    private let fill = DirectionalLight()
    private let town = Entity()
    private let traffic = Entity()
    private let dayWindows = Entity()
    private let nightWindows = Entity()
    private var displayLink: CADisplayLink?
    private var lastFrame: CFTimeInterval = 0
    private var time: Double = 0
    private var speed: Double = 1
    private var reducedMotion = false
    private var cityID = ""
    private var signature = ""
    private var selected: String?
    private var commandID: UUID?
    private var onSelect: ((String) -> Void)?
    private var yaw: Float = 0.75
    private var pitch: Float = 0.62
    private var radius: Float = 80
    private var target = SIMD3<Float>(0,0,0)
    private var startYaw: Float = 0
    private var startPitch: Float = 0
    private var startTarget = SIMD3<Float>.zero
    private var mapTask: Task<Void, Never>?
    private var mapTiles: [(Entity, SIMD2<Float>, Float)] = []
    private var detailTiles: [(Entity, Entity, SIMD2<Float>)] = []
    private var mapBounds: [Float] = [-75,-70,75,70]
    private var mapStatus = ""
    private var mapLabels: [(Entity, SIMD2<Float>)] = []
    private var isZurich: Bool { cityID == "zurich" }
    private var startRadius: Float = 80
    private var night = false
    private var seed: UInt64 = 1234
    private var meshes: [String: MeshResource] = [:]
    private var materials: [UInt32: SimpleMaterial] = [:]
    private var people: [(Entity, SIMD3<Float>, Float, Bool)] = []
    private var boats: [ModelEntity] = []
    private var vehicles: [MovingVehicle] = []
    private struct MovingVehicle {
        let node: Entity
        let route: TransitRoute
        let phase: Double
        let points: [MapPoint]
        let base: Float
    }

    func attach(_ view: ARView) {
        self.view = view
        let loading = UILabel()
        loading.translatesAutoresizingMaskIntoConstraints = false
        loading.font = .systemFont(ofSize: 15, weight: .semibold)
        loading.textColor = UIColor(hex: 0x425B51)
        loading.backgroundColor = UIColor(hex: 0xF2EFDF).withAlphaComponent(0.95)
        loading.layer.cornerRadius = 16
        loading.clipsToBounds = true
        loading.textAlignment = .center
        loading.isUserInteractionEnabled = false
        loading.isHidden = true
        view.addSubview(loading)
        NSLayoutConstraint.activate([
            loading.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loading.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            loading.widthAnchor.constraint(equalToConstant: 280),
            loading.heightAnchor.constraint(equalToConstant: 52)
        ])
        loadingLabel = loading
        view.environment.background = .color(UIColor(hex: 0xE1E9D8))
        view.environment.lighting.intensityExponent = 0.5
        view.renderOptions.insert(.disableMotionBlur)
        view.renderOptions.insert(.disableDepthOfField)
        view.scene.addAnchor(anchor)
        anchor.addChild(town); anchor.addChild(traffic); anchor.addChild(camera)
        camera.camera.fieldOfViewInDegrees = 37
        camera.camera.near = 0.01
        camera.camera.far = 1300
        sun.light.color = UIColor(hex: 0xFFF3DB)
        sun.light.intensity = 2300
        var shadows = DirectionalLightComponent.Shadow()
        shadows.maximumDistance = 180
        sun.shadow = shadows
        sun.look(at: .zero, from: SIMD3<Float>(-18,35,17), relativeTo: nil)
        fill.light.intensity = 850
        fill.light.color = UIColor(hex: 0xE9F1EF)
        fill.look(at: .zero, from: SIMD3<Float>(20,15,-20), relativeTo: nil)
        anchor.addChild(sun); anchor.addChild(fill)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(drag(_:)))
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)
        let zoom = UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:)))
        zoom.delegate = self
        view.addGestureRecognizer(zoom)
        let rotation = UIRotationGestureRecognizer(target: self, action: #selector(rotate(_:)))
        rotation.delegate = self
        view.addGestureRecognizer(rotation)
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tap(_:))))
        updateCamera()
        let link = CADisplayLink(target: self, selector: #selector(frame(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func update(state: GameState, speed: Double, command: CameraCommand, selected: String?, onSelect: @escaping (String) -> Void) {
        self.speed = speed; self.reducedMotion = state.settings.reducedMotion || UIAccessibility.isReduceMotionEnabled
        self.onSelect = onSelect
        if state.cityID != cityID {
            cityID = state.cityID; time = state.seconds; signature = ""; self.selected = nil
            mapTask?.cancel(); mapTiles.removeAll(); detailTiles.removeAll(); mapLabels.removeAll()
            loadingLabel?.isHidden = true
            town.children.removeAll(); traffic.children.removeAll(); people.removeAll(); boats.removeAll()
            dayWindows.children.removeAll(); nightWindows.children.removeAll()
            town.addChild(dayWindows); town.addChild(nightWindows)
            seed = state.cityID.utf8.reduce(UInt64(1234)) { $0 &* 31 &+ UInt64($1) }
            buildTown(city: state.currentCity)
            target = isZurich ? [0,0,4] : .zero; radius = isZurich ? 32 : 80; yaw = 0.12; pitch = 0.95
            updateCamera()
        }
        if night != state.settings.night || signature.isEmpty {
            night = state.settings.night
            view?.environment.background = .color(UIColor(hex: night ? 0x354C5A : 0xE1E9D8))
            sun.light.intensity = night ? 500 : 2300
            fill.light.intensity = night ? 280 : 850
            sun.light.color = UIColor(hex: night ? 0x9DB5DE : 0xFFF3DB)
            // Keep material resources immutable while RealityKit renders. Replacing
            // hundreds of shared material blocks can crash older simulator runtimes.
            dayWindows.isEnabled = !night
            nightWindows.isEnabled = night
            view?.environment.lighting.intensityExponent = night ? -1 : 0.5
        }
        let newSignature = state.currentLines.map { "\($0.id):\($0.tier)" }.joined(separator: ",") + (selected ?? "")
        if newSignature != signature {
            signature = newSignature
            buildTraffic(lines: state.currentLines, selected: selected)
        }
        self.selected = selected
        if command.id != commandID {
            let firstCommand = commandID == nil
            commandID = command.id
            switch command.action {
            case .reset:
                if !firstCommand {
                    target = isZurich ? SIMD3<Float>((mapBounds[0]+mapBounds[2])/2,0,(mapBounds[1]+mapBounds[3])/2) : .zero
                    radius = isZurich ? overviewRadius() : 80
                    yaw = 0; pitch = 1.1
                }
            case .zoomIn: radius = max(isZurich ? 5 : 25,radius * 0.76)
            case .zoomOut: radius = min(isZurich ? 620 : 105,radius / 0.76)
            case .focusRoute(let id):
                if let route = Catalog.route(id) {
                    let points = route.points(in: cityID)
                    let point = points[points.count / 2]
                    target = [Float(point.x),0,Float(point.z)]
                    radius = isZurich ? 18 : 49
                }
            }
            updateCamera()
        }
    }

    func stop() {
        mapTask?.cancel(); mapTask = nil
        displayLink?.invalidate(); displayLink = nil
        anchor.removeFromParent()
        vehicles.removeAll(); people.removeAll(); boats.removeAll()
        meshes.removeAll(); materials.removeAll()
    }
    private func random() -> Float { seed = seed &* 6364136223846793005 &+ 1; return Float((seed >> 32) % 10000) / 10000 }
    private func material(_ color: UInt32) -> SimpleMaterial {
        if let existing = materials[color] { return existing }
        let value = SimpleMaterial(color: UIColor(hex: color), roughness: 0.85, isMetallic: false)
        materials[color] = value; return value
    }
    @discardableResult
    private func box(_ size: SIMD3<Float>, _ color: UInt32, _ position: SIMD3<Float>, parent: Entity? = nil, round: Float = 0) -> ModelEntity {
        let key = "box-\(size)-\(round)"
        let mesh: MeshResource
        if let existing = meshes[key] { mesh = existing } else { mesh = .generateBox(size: size, cornerRadius: round); meshes[key] = mesh }
        let entity = ModelEntity(mesh: mesh, materials: [material(color)])
        entity.position = position; (parent ?? town).addChild(entity); return entity
    }
    @discardableResult
    private func sphere(_ radius: Float, _ color: UInt32, _ position: SIMD3<Float>, parent: Entity? = nil) -> ModelEntity {
        let key = "sphere-\(radius)"
        let mesh: MeshResource
        if let existing = meshes[key] { mesh = existing } else { mesh = .generateSphere(radius: radius); meshes[key] = mesh }
        let entity = ModelEntity(mesh: mesh, materials: [material(color)])
        entity.position = position; (parent ?? town).addChild(entity); return entity
    }
    private func tree(_ x: Float, _ z: Float, scale: Float = 1) {
        let group = Entity(); group.position = [x,0,z]; group.scale = SIMD3<Float>(repeating: scale); town.addChild(group)
        box([0.13,0.8,0.13],0x957C53,[0,0.53,0],parent: group)
        sphere(0.52,0x7B9F61,[0,1.2,0],parent: group)
        sphere(0.38,0x96B879,[0.07,1.57,0],parent: group)
    }
    private func segment(from a: SIMD3<Float>, to b: SIMD3<Float>, width: Float, height: Float, color: UInt32, parent: Entity? = nil) {
        let delta = b-a
        let distance = simd_length(delta)
        guard distance > 0 else { return }
        let line = box([width,height,distance],color,(a+b)/2,parent: parent)
        line.orientation = simd_quatf(from: SIMD3<Float>(0,0,1), to: delta / distance)
    }

    private func buildTown(city: TransitCity) {
        if city.id == "zurich" { loadZurich(); return }
        mapStatus = "Stilisierte Stadt"
        box([32,0.65,28],0xC8B799,[0,-0.4,0],round: 0.25)
        box([32,0.18,28],0xB5C99A,[0,0.01,0],round: 0.2)
        box([3.8,0.12,28],0x83C5CD,[7.8,0.12,0])
        for x: Float in [5.78,9.82] { box([0.22,0.18,28],0xDED5B9,[x,0.16,0]) }
        for x: Float in [-10,-4,2,12] {
            box([1.9,0.08,26],0xD8D4C1,[x,0.16,0]); box([1.28,0.05,26],0xA2A99D,[x,0.22,0])
            for z in stride(from: Float(-12.5), through: 12.5, by: 1.5) { box([0.04,0.015,0.6],0xE4E0CB,[x,0.255,z]) }
        }
        for z: Float in [-9,-3,3,9] {
            box([30,0.08,1.9],0xD8D4C1,[0,0.17,z]); box([30,0.05,1.28],0xA2A99D,[0,0.23,z])
            for x in stride(from: Float(-14.5), through: 14.5, by: 1.5) { box([0.6,0.015,0.04],0xE4E0CB,[x,0.265,z]) }
            box([4.3,0.1,1.85],0xD5C9AF,[7.8,0.17,z])
            for dz: Float in [-0.84,0.84] {
                box([4.4,0.045,0.045],0xBDCBBC,[7.8,0.72,z+dz])
                for x in stride(from: Float(5.8), through: 9.8, by: 0.6) { box([0.04,0.45,0.04],0xBDCBBC,[x,0.5,z+dz]) }
            }
        }
        for x: Float in [-10,-4,2,12] { for z: Float in [-9,-3,3,9] {
            box([1.3,0.02,1.3],0xA2A99D,[x,0.27,z])
            for n in 0..<5 { box([0.14,0.02,0.48],0xEDE6CC,[x-0.48+Float(n)*0.24,0.28,z+1.01]) }
        } }
        box([30,0.06,1.35],0xB3B2A2,[0,0.18,-11.8])
        for x in stride(from: Float(-15), through: 15, by: 0.5) { box([0.09,0.05,1.1],0xA29278,[x,0.23,-11.8]) }
        for z: Float in [-12.13,-11.47] { box([30,0.06,0.045],0x6D7A76,[0,0.29,z]) }

        let palette: [UInt32] = [0xE8D4AF,0xEEDFC3,0xD1BEA5,0xD8D8C2,0xE3B9A1,0xBECBC0]
        for cx: Float in [-13,-7,-1,14] { for cz: Float in [-6,0,6,11.5] {
            if (cx == -7 && cz == 0) || (cx == -1 && cz == 6) || (cx == 14 && cz == 11.5) { continue }
            for index in 0..<3 {
                let x = cx + (index == 1 ? 0.9 : -0.95)
                let z = cz + (index == 2 ? 1.1 : -0.7)
                let height = 1.2 + random()*2.1 + (city.id == "newyork" ? random()*2 : 0)
                building(x,z,height: height,color: palette[Int(random()*Float(palette.count)) % palette.count], pitched: city.id != "newyork" && random() > 0.23)
            }
        } }
        for z: Float in [-6,0,6,11] { building(4.3,z,height: 1.5+random(),color: palette[Int(random()*5)],pitched: true) }
        for z in stride(from: Float(-12), through: 12, by: 2) { tree(10.6,z,scale: 0.72) }
        for (x,z) in [(-15.0,2.0),(-15.0,7.5),(-12.0,12.0),(-8.0,12.0),(-5.5,11.5),(-2.0,11.8),(0.0,11.8),(14.0,11.8),(-12.0,-12.8)] { tree(Float(x),Float(z),scale: 0.8) }
        for (x,z) in [(-8.5,-1.3),(-5.4,-1.3),(-8.5,1.4),(-5.4,1.4)] { tree(Float(x),Float(z),scale: 0.9) }
        box([4.4,0.06,3.9],0xA4BD7D,[-7,0.19,0])
        box([4.1,0.03,0.55],0xDCC9A6,[-7,0.24,0]); box([0.55,0.03,3.7],0xDCC9A6,[-7,0.25,0])
        box([1.4,0.18,1.4],0xE1D8C1,[-7,0.34,0],round: 0.5)
        box([1.12,0.03,1.12],0x86C8CE,[-7,0.45,0],round: 0.4)
        box([0.15,0.6,0.15],0xCACAB2,[-7,0.74,0]); sphere(0.23,0xD9DDC8,[-7,1.08,0])
        for x: Float in [-8.3,-5.6] { box([0.7,0.1,0.28],0xAB9167,[x,0.5,0.8]); box([0.7,0.3,0.05],0xAB9167,[x,0.65,0.65]) }
        box([4.8,0.24,1.1],0xDFD6BB,[-1,0.35,-10.5]); box([4.8,0.1,1.1],0x95B3B5,[-1,1.5,-10.5])
        for x: Float in [-3,-1,1] { box([0.08,1.15,0.08],0xEDE2C8,[x,0.9,-10.5]) }
        box([3.4,0.05,3.7],0x8CAA9F,[-0.8,0.25,6.2])
        for z: Float in [4.65,7.75] { box([2.8,0.02,0.035],0xE7EDD9,[-0.8,0.29,z]) }
        for x: Float in [-2.2,0.6] { box([0.035,0.02,3.1],0xE7EDD9,[x,0.29,6.2]) }
        box([2.8,0.02,0.035],0xE7EDD9,[-0.8,0.29,6.2])
        for (x,z) in [(-10.0,9.0),(-10.0,-3.0),(-4.0,-9.0),(2.0,-9.0),(-4.0,9.0),(2.0,3.0),(12.0,3.0),(12.0,9.0)] {
            box([0.05,1.05,0.05],0x798E72,[Float(x)-0.9,0.77,Float(z)])
            box([0.27,0.28,0.07],0xE9BF5D,[Float(x)-0.9,1.25,Float(z)],round: 0.03)
            box([0.65,0.07,0.5],0xA2B49E,[Float(x)-1.1,1.1,Float(z)-0.1])
        }
        hills()
        landmark(city.id)
        makePeople()
        for i in 0..<12 {
            let ripple = box([0.25+random()*0.3,0.01,0.035],0xB9DFD8,[6.5+random()*2.6,0.19,Float(i)*2-12])
            boats.append(ripple)
        }
    }

    // Official survey geometry is triangulated offline; each tile/material is one
    // draw entity, rather than tens of thousands of individual building entities.
    private struct RenderMap: Decodable, Sendable {
        struct Tile: Decodable, Sendable {
            struct Mesh: Decodable, Sendable {
                let kind: String
                let positions: [Float]
                let indices: [UInt32]
            }
            let id: String
            let bounds: [Float]
            let meshes: [Mesh]
        }
        struct Label: Decodable, Sendable { let name: String; let x: Float; let z: Float }
        let labels: [Label]
        let tiles: [Tile]
    }

    private func loadZurich() {
        mapStatus = "Stadtkarte wird geladen"
        loadingLabel?.text = "Zürich wird aufgebaut …"
        loadingLabel?.isHidden = false
        box([2000,0.1,2000],0xC8D1AE,[0,-0.08,0])
        guard let url = Bundle.main.url(forResource: "zurich-city", withExtension: "json") else {
            mapStatus = "Kartendaten fehlen"
            loadingLabel?.text = "Stadtkarte nicht verfügbar"
            return
        }
        mapTask = Task { [weak self] in
            do {
                let document = try await Task.detached(priority: .userInitiated) {
                    try JSONDecoder().decode(RenderMap.self, from: Data(contentsOf: url))
                }.value
                guard let self, !Task.isCancelled, self.isZurich else { return }
                let bounds = document.tiles.map(\.bounds).filter { $0.count == 4 }
                if !bounds.isEmpty {
                    self.mapBounds = [bounds.map{$0[0]}.min()!,bounds.map{$0[1]}.min()!,bounds.map{$0[2]}.max()!,bounds.map{$0[3]}.max()!]
                }
                // Populate the visible centre first, then stream the remaining tiles
                // on successive main-actor turns so gestures remain responsive.
                let ordered = document.tiles.sorted {
                    abs($0.bounds[0]) + abs($0.bounds[1]) < abs($1.bounds[0]) + abs($1.bounds[1])
                }
                for tile in ordered {
                    guard !Task.isCancelled, self.isZurich else { return }
                    self.installTile(tile)
                    self.updateMapDetail()
                    await Task.yield()
                }
                guard !Task.isCancelled, self.isZurich else { return }
                self.installMapLabels(document.labels)
                self.zurichLandmarks()
                self.mapStatus = "Amtliche Stadtkarte · Höhen stilisiert"
                self.loadingLabel?.isHidden = true
                self.updateCamera()
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.mapStatus = "Stadtkarte konnte nicht geladen werden"
                self.loadingLabel?.text = "Stadtkarte konnte nicht geladen werden"
                self.updateCamera()
            }
        }
    }

    private func installTile(_ tile: RenderMap.Tile) {
        guard tile.bounds.count == 4 else { return }
        let center = SIMD2<Float>((tile.bounds[0]+tile.bounds[2])/2,(tile.bounds[1]+tile.bounds[3])/2)
        let extent = max(tile.bounds[2]-tile.bounds[0],tile.bounds[3]-tile.bounds[1])
        let group = Entity()
        group.name = "city-tile:" + tile.id
        town.addChild(group)
        mapTiles.append((group,center,extent))
        var windows: [SIMD3<Float>] = []
        var windowNormals: [SIMD3<Float>] = []
        var windowIndices: [UInt32] = []
        var treeVertices: [SIMD3<Float>] = [], treeNormals: [SIMD3<Float>] = [], treeIndices: [UInt32] = []
        var treeCount = 0
        let palette: [String: UInt32] = ["building":0xE4D5BA,"building2":0xD3C9BA,"building3":0xE7C5AA,
            "roof":0xAD8B77,"roof2":0x89958D,"water":0x74B9BC,"park":0xACC68C,"forest":0x8EAE78,
            "road":0xD6D2C4,"rail":0x929C94,"boundary":0xBAC59E]
        for source in tile.meshes {
            guard source.positions.count >= 9, source.positions.count % 3 == 0, source.indices.count % 3 == 0 else { continue }
            let vertices = stride(from: 0,to: source.positions.count,by: 3).map {
                SIMD3<Float>(source.positions[$0],source.positions[$0+1],source.positions[$0+2])
            }
            guard source.indices.allSatisfy({ Int($0) < vertices.count }) else { continue }
            var normals = [SIMD3<Float>](repeating: .zero,count: vertices.count)
            for index in stride(from: 0,to: source.indices.count,by: 3) {
                let a = Int(source.indices[index]), b = Int(source.indices[index+1]), c = Int(source.indices[index+2])
                let cross = simd_cross(vertices[b]-vertices[a],vertices[c]-vertices[a])
                if simd_length_squared(cross) > 0.0000000001 {
                    normals[a] += cross; normals[b] += cross; normals[c] += cross
                    let centroid = (vertices[a]+vertices[b]+vertices[c])/3
                    if (source.kind == "forest" || source.kind == "park"), treeCount < 40, index % 24 == 0 {
                        treeCount += 1
                        let height: Float = source.kind == "forest" ? 0.16 : 0.1
                        for side in 0..<6 {
                            let angle = Float(side)*2*Float.pi/6, next = Float(side+1)*2*Float.pi/6
                            let p = centroid + SIMD3<Float>(cos(angle)*height*0.35,0.025,sin(angle)*height*0.35)
                            let q = centroid + SIMD3<Float>(0,height,0)
                            let r = centroid + SIMD3<Float>(cos(next)*height*0.35,0.025,sin(next)*height*0.35)
                            let normal = simd_normalize(simd_cross(q-p,r-p))
                            let base = UInt32(treeVertices.count)
                            treeVertices.append(contentsOf: [p,q,r]); treeNormals.append(contentsOf: [normal,normal,normal])
                            treeIndices.append(contentsOf: [base,base+1,base+2])
                        }
                    }
                    if source.kind == "road", people.count < 42, index % 75 == 0,
                       abs(centroid.x) < 6, abs(centroid.z) < 6 {
                        let person = Entity(); person.position = centroid + SIMD3<Float>(0,0.008,0)
                        town.addChild(person)
                        let colors: [UInt32] = [0xC88266,0x627F91,0xE1BD70]
                        box([0.012,0.026,0.012],colors[people.count % 3],[0,0.018,0],parent: person)
                        sphere(0.008,0xD7B491,[0,0.039,0],parent: person)
                        people.append((person,person.position,Float(people.count),true))
                    }
                    // Small facade details are batched, capped, and only visible
                    // nearby. Two immutable models share each window mesh.
                    if source.kind.hasPrefix("building"), abs(cross.y) < simd_length(cross)*0.05,
                       index % 6 == 0, windows.count < 2400 {
                        let points = [vertices[a],vertices[b],vertices[c]]
                        let low = points.map(\.y).min()!, high = points.map(\.y).max()!
                        let n = simd_normalize(cross)
                        let side = SIMD3<Float>(n.z,0,-n.x)
                        let midpoint = (vertices[a]+vertices[b]+vertices[c])/3
                        if high-low > 0.07 {
                            let p = SIMD3<Float>(midpoint.x,(high+low)/2,midpoint.z) + n*0.0015
                            let halfWidth: Float = 0.009, halfHeight: Float = 0.014
                            let up = SIMD3<Float>(0,halfHeight,0), across = side*halfWidth
                            let start = UInt32(windows.count)
                            windows.append(contentsOf: [p-across-up,p+across-up,p+across+up,p-across+up])
                            windowNormals.append(contentsOf: [n,n,n,n])
                            windowIndices.append(contentsOf: [start,start+1,start+2,start,start+2,start+3])
                        }
                    }
                }
            }
            normals = normals.map { simd_length_squared($0) > 0 ? simd_normalize($0) : SIMD3<Float>(0,1,0) }
            if let mesh = makeMesh(vertices,normals,source.indices,name: tile.id + source.kind) {
                group.addChild(ModelEntity(mesh: mesh,materials: [material(palette[source.kind] ?? 0xD2C8AE)]))
            }
        }
        if let mesh = makeMesh(treeVertices,treeNormals,treeIndices,name: tile.id + "-trees") {
            group.addChild(ModelEntity(mesh: mesh,materials: [material(0x739366)]))
        }
        if let mesh = makeMesh(windows,windowNormals,windowIndices,name: tile.id + "-windows") {
            let day = ModelEntity(mesh: mesh,materials: [material(0x779A9B)])
            let evening = ModelEntity(mesh: mesh,materials: [UnlitMaterial(color: UIColor(hex: 0xFFE1A5))])
            dayWindows.addChild(day); nightWindows.addChild(evening)
            detailTiles.append((day,evening,center))
        }
    }

    private func installMapLabels(_ labels: [RenderMap.Label]) {
        for label in labels {
            let node = Entity()
            node.position = [label.x,0.65,label.z]
            let mesh = MeshResource.generateText(label.name,extrusionDepth: 0.001,font: .systemFont(ofSize: 0.24,weight: .semibold))
            let text = ModelEntity(mesh: mesh,materials: [UnlitMaterial(color: UIColor(hex: 0x425B51))])
            let bounds = text.visualBounds(relativeTo: nil)
            text.position.x = -bounds.extents.x/2
            let plate = box([bounds.extents.x+0.18,0.38,0.012],0xF2EFDF,[0,0.1,-0.02],parent: node,round: 0.004)
            plate.name = "district-label"
            node.addChild(text); town.addChild(node)
            mapLabels.append((node,[label.x,label.z]))
        }
    }

    private func zurichLandmarks() {
        // Recognisable, deliberately stylised silhouettes at their geographic
        // locations; the cadastral footprint below remains the survey geometry.
        // LV95 coordinates use the same projection/origin as the bundled mesh.
        let gross = SIMD2<Float>(1.9189,7.5341)
        for offset: Float in [-0.09,0.09] {
            box([0.10,0.53,0.10],0xD8C6A5,[gross.x+offset,0.29,gross.y])
            let crown = sphere(0.065,0x657F70,[gross.x+offset,0.59,gross.y])
            crown.scale = [1,1.4,1]
        }
        let frau = SIMD2<Float>(-0.4162,8.0117)
        box([0.11,0.47,0.11],0xD8C6A5,[frau.x,0.26,frau.y])
        mountain(radius: 0.085,height: 0.34,color: 0x629183,position: [frau.x,0.49,frau.y])
    }

    private func makeMesh(_ positions: [SIMD3<Float>], _ normals: [SIMD3<Float>], _ indices: [UInt32], name: String) -> MeshResource? {
        guard !positions.isEmpty, !indices.isEmpty else { return nil }
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = .init(positions)
        descriptor.normals = .init(normals)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }

    private func updateMapDetail() {
        guard isZurich else { return }
        let focus = SIMD2<Float>(target.x,target.z)
        for (tile, center, extent) in mapTiles {
            tile.isEnabled = simd_distance(center,focus) < radius * 1.3 + extent
        }
        for (node, position) in mapLabels {
            node.isEnabled = radius > 16 && simd_distance(position,focus) < radius*0.4
            node.orientation = camera.orientation
            node.scale = SIMD3<Float>(repeating: max(0.6,radius*0.04))
        }
        for (person, origin, _, _) in people {
            person.isEnabled = radius < 20 && simd_distance(SIMD2<Float>(origin.x,origin.z),focus) < 8
        }
        for (day, evening, center) in detailTiles {
            let visible = radius < 28 && simd_distance(center,focus) < 13
            day.isEnabled = visible; evening.isEnabled = visible
        }
    }

    private func building(_ x: Float, _ z: Float, height: Float, color: UInt32, pitched: Bool) {
        let width: Float = 1.55, depth: Float = 1.5
        box([width+0.15,0.1,depth+0.15],0xCEC7B0,[x,0.2,z])
        box([width,height,depth],color,[x,0.25+height/2,z],round: 0.035)
        for y in stride(from: Float(0.75), through: height+0.05, by: 0.65) {
            for dx: Float in [-0.4,0.4] {
                window(size: [0.25,0.32,0.025],position: [x+dx,y,z+depth/2+0.02])
                window(size: [0.025,0.32,0.25],position: [x+width/2+0.02,y,z+dx])
                window(size: [0.025,0.32,0.25],position: [x-width/2-0.02,y,z+dx])
            }
        }
        box([0.29,0.53,0.035],0x698D88,[x,0.53,z+0.77])
        if pitched {
            let roofColor: UInt32 = random() > 0.3 ? 0xBA876B : 0x82998B
            for direction: Float in [-1,1] {
                let roof = box([1.02,0.13,1.7],roofColor,[x+direction*0.38,height+0.55,z])
                roof.orientation = simd_quatf(angle: direction * -.pi/5, axis: [0,0,1])
            }
            if random() > 0.7 { box([0.2,0.55,0.2],0xCDB99A,[x+0.2,height+0.8,z-0.25]) }
        } else {
            box([1.65,0.13,1.6],0xA9B4A6,[x,height+0.3,z])
            box([0.4,0.2,0.4],0xBBC1B0,[x+0.25,height+0.47,z-0.2])
        }
    }
    private func window(size: SIMD3<Float>, position: SIMD3<Float>) {
        let day = box(size,0x7EABB1,position,parent: dayWindows)
        guard let mesh = day.model?.mesh else { return }
        let illuminated = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: UIColor(hex: 0xFFE0A0))])
        illuminated.position = position
        nightWindows.addChild(illuminated)
    }
    private func hills() {
        for (x,z,h,s): (Float,Float,Float,Float) in [(-13,-14,4.2,2.4),(-16,-13.5,3.1,2.1),(-12,-16,5,2.3)] {
            mountain(radius: s, height: h, color: 0x94AC82, position: [x,-0.4,z])
            mountain(radius: s*0.21, height: h*0.21, color: 0xE5E7D5, position: [x,h*0.79-0.39,z])
        }
        box([0.75,0.7,0.75],0xDAB98F,[-15,3.6,-15])
    }
    private func mountain(radius: Float, height: Float, color: UInt32, position: SIMD3<Float>) {
        var vertices: [SIMD3<Float>] = [], normals: [SIMD3<Float>] = []
        for index in 0..<7 {
            let a = Float(index) * 2 * .pi / 7, b = Float(index+1) * 2 * .pi / 7
            let p = SIMD3<Float>(cos(a)*radius,0,sin(a)*radius), q = SIMD3<Float>(0,height,0), r = SIMD3<Float>(cos(b)*radius,0,sin(b)*radius)
            let normal = simd_normalize(simd_cross(q-p,r-p))
            vertices.append(contentsOf: [p,q,r]); normals.append(contentsOf: [normal,normal,normal])
        }
        var descriptor = MeshDescriptor(name: "Mountain")
        descriptor.positions = .init(vertices)
        descriptor.normals = .init(normals)
        descriptor.primitives = .triangles((0..<vertices.count).map(UInt32.init))
        if let mesh = try? MeshResource.generate(from: [descriptor]) {
            let entity = ModelEntity(mesh: mesh, materials: [material(color)])
            entity.position = position; town.addChild(entity)
        }
    }
    private func landmark(_ city: String) {
        // Different silhouettes give each unlocked city a recognisable centre.
        if city == "paris" || city == "tokyo" {
            let color: UInt32 = city == "paris" ? 0x7C8A77 : 0xC57962
            for x: Float in [-1,1] { for z: Float in [-1,1] {
                segment(from: [-7+x,0.3,-6+z],to: [-7,6.4,-6],width: 0.16,height: 0.16,color: color)
            } }
            box([2.1,0.13,2.1],color,[-7,2,-6]); box([1.1,0.13,1.1],color,[-7,3.7,-6])
        } else if city == "sydney" {
            for i in 0..<3 {
                let shell = sphere(0.85,0xF0EAD9,[-7+Float(i)*0.7,1+Float(i)*0.2,-6])
                shell.scale = [0.55,1.5,1.3]; shell.orientation = simd_quatf(angle: -.pi/7, axis: [0,0,1])
            }
        } else if city == "rio" {
            box([0.35,3.2,0.45],0xCCD1BA,[-7,2,-6]); sphere(0.3,0xD9DDCB,[-7,3.9,-6]); box([2.6,0.25,0.35],0xD9DDCB,[-7,3.3,-6])
        } else {
            box([1.2,2.3,2.4],0xEAE0C2,[-7,1.4,-6]); box([0.9,4.4,0.9],0xE9DCBA,[-7,2.45,-4.6])
            let roof = box([0.75,1.4,0.75],0x74968A,[-7,5.1,-4.6],round: 0.15)
            roof.orientation = simd_quatf(angle: .pi/4, axis: [0,1,0])
            box([0.45,0.45,0.02],0xF4EBD0,[-7,4,-4.135],round: 0.15)
            box([0.03,0.2,0.03],0x657D69,[-7,4.05,-4.11]); box([0.17,0.03,0.03],0x657D69,[-6.93,4,-4.11])
        }
    }
    private func makePeople() {
        let colors: [UInt32] = [0xCB7C62,0x698FA5,0xE4B557,0x849B6F,0xAD94AF]
        for i in 0..<42 {
            let walkingAlongX = i % 2 == 0
            let fixed: Float = walkingAlongX ? [-9.85,-3.85,3.85,9.85][i%4] : [-10.85,-4.85,2.85,12.85][i%4]
            let variable = random()*24-12
            if walkingAlongX && variable > 5 && variable < 10 { continue }
            let start = SIMD3<Float>(walkingAlongX ? variable : fixed,0.27,walkingAlongX ? fixed : variable)
            let person = Entity(); person.position = start; town.addChild(person)
            box([0.15,0.28,0.14],colors[i%colors.count],[0,0.27,0],parent: person,round: 0.03)
            sphere(0.09,0xD9B99A,[0,0.48,0],parent: person)
            box([0.1,0.15,0.09],0x626F67,[0,0.08,0],parent: person)
            people.append((person,start,random()*10,walkingAlongX))
        }
    }

    private func buildTraffic(lines: [OwnedLine], selected: String?) {
        traffic.children.removeAll(); vehicles.removeAll()
        for owned in lines {
            guard let route = Catalog.route(owned.id) else { continue }
            let points = route.points(in: cityID)
            let height: Float = isZurich ? (route.kind == .ship ? 0.025 : 0.045) : (route.kind == .ship ? 0.22 : route.kind == .cable ? 4.8 : route.kind == .plane ? 5 : 0.31)
            if route.kind != .plane {
                drawRoute(points, height: height, width: selected == route.id ? 0.055 : 0.022, route: route)

            }
            if route.kind == .cable && !isZurich {
                for point in [points.first!, points.last!] { box([0.09,4.5,0.09],0x8C9F89,[Float(point.x),2.55,Float(point.z)],parent: traffic) }
            }
            if route.kind == .metro && !isZurich {
                for point in [points.first!,points.last!] {
                    box([0.65,0.2,0.65],route.colorHex,[Float(point.x)-0.75,0.32,Float(point.z)],parent: traffic)
                    box([0.1,0.75,0.1],route.colorHex,[Float(point.x)-0.75,0.75,Float(point.z)],parent: traffic)
                }
            }
            for index in 0..<owned.tier {
                let node = vehicle(route)
                if isZurich { node.scale = SIMD3<Float>(repeating: route.kind == .ship ? 0.3 : 0.16) }
                node.name = "route:\(route.id)"
                node.generateCollisionShapes(recursive: true)
                traffic.addChild(node)
                vehicles.append(.init(node: node,route: route,phase: Double(index) / Double(owned.tier)*2,points: points,base: isZurich ? 0.025 : (route.kind == .ship ? 0.05 : route.kind == .cable ? 3.45 : route.kind == .train ? 0.13 : 0.09)))
            }
        }
    }
    private func drawRoute(_ points: [MapPoint], height: Float, width: Float, route: TransitRoute) {
        guard points.count > 1 else { return }
        var vertices: [SIMD3<Float>] = [], normals: [SIMD3<Float>] = [], indices: [UInt32] = []
        for i in 1..<points.count {
            let a = SIMD3<Float>(Float(points[i-1].x),height,Float(points[i-1].z))
            let b = SIMD3<Float>(Float(points[i].x),height,Float(points[i].z))
            let delta = b-a
            guard simd_length_squared(delta) > 0.000001 else { continue }
            let side = simd_normalize(SIMD3<Float>(delta.z,0,-delta.x))*width/2
            let start = UInt32(vertices.count)
            vertices.append(contentsOf: [a-side,a+side,b+side,b-side])
            normals.append(contentsOf: Array(repeating: SIMD3<Float>(0,1,0),count: 4))
            indices.append(contentsOf: [start,start+2,start+1,start,start+3,start+2])
        }
        if let mesh = makeMesh(vertices,normals,indices,name: route.id) {
            let node = ModelEntity(mesh: mesh,materials: [UnlitMaterial(color: UIColor(hex: route.colorHex))])
            node.name = "route:" + route.id
            traffic.addChild(node)
        }
        for point in [points.first!,points.last!] {
            let stop = box([0.08,0.012,0.08],0xFFF6D9,[Float(point.x),height+0.01,Float(point.z)],parent: traffic,round: 0.004)
            stop.name = "route:" + route.id
        }
    }

    private func vehicle(_ route: TransitRoute) -> Entity {
        let group = Entity(), color = route.colorHex
        switch route.kind {
        case .ship:
            box([0.65,0.25,1.65],0xF0EBD9,[0,0.3,0],parent: group,round: 0.19)
            box([0.48,0.32,0.85],0xF6EDD9,[0,0.56,0],parent: group,round: 0.06)
            box([0.49,0.14,0.6],0x759FAD,[0,0.59,-0.04],parent: group)
            box([0.55,0.08,0.9],color,[0,0.79,0],parent: group)
        case .plane:
            let body = sphere(0.26,0xF6F1E2,[0,0.3,0],parent: group); body.scale = [1,0.8,4]
            box([2.7,0.06,0.4],0xECEBDC,[0,0.3,0.1],parent: group,round: 0.06)
            box([0.95,0.06,0.3],color,[0,0.36,0.9],parent: group)
            box([0.06,0.4,0.35],color,[0,0.5,0.85],parent: group)
        case .cable:
            box([0.63,0.55,0.63],color,[0,0.45,0],parent: group,round: 0.08)
            box([0.65,0.25,0.65],0x8EB3BA,[0,0.68,0],parent: group)
            box([0.05,0.5,0.05],0x647A71,[0,1.05,0],parent: group)
        default:
            let length: Float = route.kind == .bus ? 1.2 : route.kind == .tram ? 2 : 2.2
            let segments = route.kind == .train || route.kind == .metro ? 2 : 1
            for i in 0..<segments {
                let z = Float(i)*(length+0.12)
                let main = box([0.56,0.45,length],color,[0,0.51,z],parent: group,round: 0.08)
                if route.kind == .metro { main.model?.materials = [SimpleMaterial(color: UIColor(hex: color).withAlphaComponent(0.6),isMetallic: false)] }
                box([0.57,0.17,length*0.87],0x7BABB7,[0,0.6,z],parent: group,round: 0.02)
                box([0.53,0.07,length*0.95],0xF7EBD0,[0,0.77,z],parent: group,round: 0.02)
                box([0.4,0.2,0.02],0x638F9D,[0,0.59,z-length/2-0.02],parent: group)
                for dx: Float in [-0.28,0.28] { for dz: Float in [-length*0.3,length*0.3] { sphere(0.09,0x4B5950,[dx,0.26,z+dz],parent: group) } }
                for dx: Float in [-0.16,0.16] { box([0.1,0.05,0.025],0xFFF1A4,[dx,0.4,z-length/2-0.03],parent: group) }
            }
        }
        return group
    }

    @objc private func frame(_ link: CADisplayLink) {
        let elapsed = lastFrame == 0 ? 0 : min(0.05, link.timestamp-lastFrame)
        lastFrame = link.timestamp
        guard view?.window != nil else { return }
        time += elapsed * speed
        for vehicle in vehicles {
            let pose = RouteMotion.pose(points: vehicle.points, phase: time/vehicle.route.duration+vehicle.phase)
            var y = vehicle.base
            if vehicle.route.kind == .plane { y = 3 + Float(sin(pose.fraction * .pi))*5 }
            if vehicle.route.kind == .ship && !reducedMotion { y += Float(sin(time*2+vehicle.phase))*(isZurich ? 0.002 : 0.02) }
            vehicle.node.position = [Float(pose.x),y,Float(pose.z)]
            vehicle.node.orientation = simd_quatf(angle: Float(pose.heading), axis: [0,1,0])
        }
        guard !reducedMotion else { return }
        for (node, origin, phase, alongX) in people {
            let movement = Float(sin(time*0.12+Double(phase)))*(isZurich ? 0.03 : 1.1)
            node.position = origin + SIMD3<Float>(alongX ? movement : 0,abs(Float(sin(time*5+Double(phase))))*(isZurich ? 0.001 : 0.012),alongX ? 0 : movement)
        }
        for (index,ripple) in boats.enumerated() { ripple.scale.x = 0.85+Float(sin(time+Double(index)))*0.25 }
    }
    private func updateCamera() {
        let position = target + SIMD3<Float>(radius*cos(pitch)*sin(yaw),radius*sin(pitch),radius*cos(pitch)*cos(yaw))
        camera.look(at: target,from: position,relativeTo: nil)
        updateMapDetail()
        view?.accessibilityValue = "\(isZurich ? "Zürich" : "Stadt") · Zoom \(Int(radius)) · Fokus \(Int(target.x)),\(Int(target.z)) · \(mapStatus)"
    }
    private func overviewRadius() -> Float {
        let aspect = max(0.4, Float((view?.bounds.width ?? 390) / max(1, view?.bounds.height ?? 844)))
        let width = mapBounds[2]-mapBounds[0], depth = mapBounds[3]-mapBounds[1]
        return min(620, max(width / aspect, depth) * 1.75)
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        (gestureRecognizer is UIPinchGestureRecognizer && otherGestureRecognizer is UIRotationGestureRecognizer) ||
        (gestureRecognizer is UIRotationGestureRecognizer && otherGestureRecognizer is UIPinchGestureRecognizer)
    }
    @objc private func drag(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .began { startTarget = target }
        let delta = gesture.translation(in: view)
        let factor = radius * 0.67 / Float(max(1, view?.bounds.height ?? 844))
        let right = SIMD3<Float>(cos(yaw),0,-sin(yaw))
        let down = SIMD3<Float>(sin(yaw),0,cos(yaw))
        target = startTarget - right * Float(delta.x) * factor - down * Float(delta.y) * factor / sin(pitch)
        let bounds: [Float] = isZurich ? mapBounds : [-20,-20,20,20]
        target.x = max(bounds[0],min(bounds[2],target.x))
        target.z = max(bounds[1],min(bounds[3],target.z))
        updateCamera()
    }
    @objc private func rotate(_ gesture: UIRotationGestureRecognizer) {
        if gesture.state == .began { startYaw = yaw }
        yaw = startYaw - Float(gesture.rotation)
        updateCamera()
    }
    @objc private func pinch(_ gesture: UIPinchGestureRecognizer) {
        if gesture.state == .began { startRadius = radius }
        radius = max(isZurich ? 5 : 25,min(isZurich ? 620 : 105,startRadius/Float(gesture.scale)))
        updateCamera()
    }
    @objc private func tap(_ gesture: UITapGestureRecognizer) {
        guard let view else { return }
        var hit = view.entity(at: gesture.location(in: view))
        while let entity = hit {
            if entity.name.hasPrefix("route:") { onSelect?(String(entity.name.dropFirst(6))); return }
            hit = entity.parent
        }
    }
}
