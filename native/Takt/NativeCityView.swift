import SwiftUI
import RealityKit
import UIKit
import TaktCore

struct CameraCommand: Equatable {
    enum Action: Equatable { case reset, region, zoomIn, zoomOut, focusRoute(String) }
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
    var onRegionSelect: ((String) -> Void)? = nil

    func makeCoordinator() -> CityRenderer { CityRenderer() }
    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.accessibilityIdentifier = "native-city"
        view.accessibilityLabel = "Stadtkarte"
        view.accessibilityHint = "Mit einem Finger verschieben, mit zwei Fingern zoomen und drehen."
        view.isAccessibilityElement = true
        context.coordinator.attach(view)
        context.coordinator.update(state: state, speed: speed, command: cameraCommand, selected: selectedRoute, onSelect: onSelect, onRegionSelect: onRegionSelect)
        return view
    }
    func updateUIView(_ view: ARView, context: Context) {
        context.coordinator.update(state: state, speed: speed, command: cameraCommand, selected: selectedRoute, onSelect: onSelect, onRegionSelect: onRegionSelect)
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
    private let localRoutes = Entity()
    private let nationalRoutes = Entity()
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
    private var startTarget = SIMD3<Float>.zero
    private var mapTasks: [String: Task<Void, Never>] = [:]
    private var loadedMaps = Set<String>()
    private var worldStarted = false
    private var regionSignature = ""
    private let regionPins = Entity()
    private var regionMarkers: [(node: Entity, title: Entity, position: SIMD2<Float>, width: Float, id: String)] = []
    private var unlockedRegions = Set<String>()
    private var onRegionSelect: ((String) -> Void)?
    private var mapTiles: [(Entity, SIMD2<Float>, Float, Bool)] = []
    private var detailTiles: [(Entity, Entity, SIMD2<Float>)] = []
    private var mapBounds: [Float] = [-2000,-600,1100,1900]
    private var mapStatus = ""
    private var mapLabels: [(Entity, SIMD2<Float>)] = []
    private var isZurich: Bool { cityID == "zurich" }
    private var startRadius: Float = 80
    private var night = false
    private var meshes: [String: MeshResource] = [:]
    private var materials: [UInt32: SimpleMaterial] = [:]
    private var people: [(Entity, SIMD3<Float>, Float, Bool)] = []
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
        anchor.addChild(regionPins); anchor.addChild(town); anchor.addChild(traffic); anchor.addChild(camera)
        camera.camera.fieldOfViewInDegrees = 37
        camera.camera.near = 0.01
        camera.camera.far = 20000
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

    func update(state: GameState, speed: Double, command: CameraCommand, selected: String?, onSelect: @escaping (String) -> Void, onRegionSelect: ((String) -> Void)?) {
        self.speed = speed; self.reducedMotion = state.settings.reducedMotion || UIAccessibility.isReduceMotionEnabled
        self.onSelect = onSelect
        self.onRegionSelect = onRegionSelect
        if !worldStarted {
            worldStarted = true
            town.addChild(dayWindows); town.addChild(nightWindows)
            box([20000,0.1,20000],0xBECBB8,[0,-0.15,0])
            loadMap("switzerland-map", country: true)
            loadMap("andermatt-city", country: false)
            buildSwissMountains()
            buildAndermattRelief()
            buildIllustrativeSettlements()
        }
        if state.cityID != cityID {
            cityID = state.cityID; time = state.seconds; signature = ""; self.selected = nil
            focusRegion()
        }
        let unlocked = state.networks.keys.sorted().joined(separator: ",")
        if unlocked != regionSignature {
            regionSignature = unlocked
            buildRegionMarkers(unlocked: Set(state.networks.keys))
        }
        if night != state.settings.night || signature.isEmpty {
            night = state.settings.night
            view?.environment.background = .color(UIColor(hex: night ? 0x152937 : 0xE1E9D8))
            sun.light.intensity = night ? 75 : 2300
            fill.light.intensity = night ? 40 : 850
            sun.light.color = UIColor(hex: night ? 0x789BD6 : 0xFFF3DB)
            // Keep material resources immutable while RealityKit renders. Replacing
            // hundreds of shared material blocks can crash older simulator runtimes.
            dayWindows.isEnabled = !night
            nightWindows.isEnabled = night
            view?.environment.lighting.intensityExponent = night ? -4 : 0.5
        }
        let newSignature = state.networks.keys.sorted().map { id in
            id + (state.networks[id]?.lines.map { "\($0.id):\($0.tier)" }.joined(separator: ",") ?? "")
        }.joined(separator: ";") + cityID + (selected ?? "")
        if newSignature != signature {
            signature = newSignature
            buildTraffic(networks: state.networks.keys.sorted().map { ($0, state.networks[$0]!.lines) }, selected: selected)
        }
        self.selected = selected
        updateMapDetail()
        if command.id != commandID {
            let firstCommand = commandID == nil
            commandID = command.id
            switch command.action {
            case .reset:
                if !firstCommand {
                    target = SIMD3<Float>((mapBounds[0]+mapBounds[2])/2,0,(mapBounds[1]+mapBounds[3])/2)
                    radius = overviewRadius()
                    yaw = 0; pitch = 1.1
                }
            case .region: focusRegion()
            case .zoomIn: radius = max(4,radius * 0.7)
            case .zoomOut: radius = min(14000,radius / 0.7)
            case .focusRoute(let id):
                if let route = Catalog.route(id) {
                    let points = route.points(in: cityID)
                    guard let first = points.first else { break }
                    let minX = points.map(\.x).min() ?? first.x
                    let maxX = points.map(\.x).max() ?? first.x
                    let minZ = points.map(\.z).min() ?? first.z
                    let maxZ = points.map(\.z).max() ?? first.z
                    target = [Float((minX+maxX)/2),0,Float((minZ+maxZ)/2)]
                    yaw = 0; pitch = 0.9
                    let aspect = max(0.4,Float((view?.bounds.width ?? 390) / max(1,view?.bounds.height ?? 844)))
                    radius = min(14000,max(18,max(Float(maxX-minX)/aspect,Float(maxZ-minZ)/sin(pitch))*1.9))
                }
            }
            updateCamera()
        }
    }

    func stop() {
        mapTasks.values.forEach { $0.cancel() }; mapTasks.removeAll()
        displayLink?.invalidate(); displayLink = nil
        anchor.removeFromParent()
        vehicles.removeAll(); people.removeAll()
        meshes.removeAll(); materials.removeAll()
    }
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

    private func refreshReadiness() {
        let requiredDetail = cityID == "zurich" ? "zurich-city" : "andermatt-city"
        let ready = loadedMaps.contains("switzerland-map") && loadedMaps.contains(requiredDetail)
        mapStatus = ready ? "Amtliche Stadtkarte / OSM - Schweiz bereit" : "Schweizer Karte wird geladen"
        loadingLabel?.isHidden = ready
    }

    private func buildRegionMarkers(unlocked: Set<String>) {
        regionPins.children.removeAll(); regionMarkers.removeAll()
        unlockedRegions = unlocked
        for city in Catalog.cities {
            let point = city.mapCenter
            let node = Entity(); node.name = "region:" + city.id
            node.position = [Float(point.x),1,Float(point.z)]
            let owned = unlocked.contains(city.id)
            let titleNode = Entity(); titleNode.position.y = 0.15; node.addChild(titleNode)
            let dot = sphere(0.075,owned ? 0xFFF3CA : 0x587D68,[0,-0.07,0],parent: node)
            dot.generateCollisionShapes(recursive: false)
            let title = city.name + (owned ? "" : " +")
            let mesh = MeshResource.generateText(title,extrusionDepth: 0.001,font: .systemFont(ofSize: 0.23,weight: .semibold))
            let text = ModelEntity(mesh: mesh,materials: [UnlitMaterial(color: UIColor(hex: owned ? 0xF8F1D9 : 0x54665C))])
            let width = text.visualBounds(relativeTo: nil).extents.x
            text.position = [-width/2,0,0.02]
            let plate = box([width+0.25,0.42,0.04],owned ? 0x477A65 : 0xDDDCC9,[0,0.1,0],parent: titleNode,round: 0.015)
            plate.generateCollisionShapes(recursive: false)
            titleNode.addChild(text); regionPins.addChild(node)
            regionMarkers.append((node,titleNode,[Float(point.x),Float(point.z)],width+0.25,city.id))
        }
        updateMapDetail()
    }

    // Illustrative alpine relief, not an elevation survey. The real horizontal
    // footprints are preserved; every local surface uses this one height field.
    private func andermattElevation(_ x: Float, _ z: Float) -> Float {
        guard x > 20, x < 85, z > 795, z < 860 else { return 0 }
        let axis: [SIMD2<Float>] = [[46,800],[51,810],[52,822],[33,841],[25,848]]
        let point = SIMD2<Float>(x,z)
        var distance = Float.greatestFiniteMagnitude
        for i in 1..<axis.count {
            let a = axis[i-1], delta = axis[i]-a
            let fraction = max(0,min(1,simd_dot(point-a,delta)/simd_length_squared(delta)))
            distance = min(distance,simd_distance(point,a+delta*fraction))
        }
        let slope = max(0,distance-3.2)
        let rise = min(1,slope/18)
        let eased = rise*rise*(3-2*rise)
        let edge = min(min(x-20,85-x),min(z-795,860-z))
        let fade = min(1,max(0,edge/6))
        return eased * (14 + 1.4*sin(z*0.21) + 0.7*cos(x*0.3)) * fade*fade*(3-2*fade)
    }

    private func buildAndermattRelief() {
        var positions: [SIMD3<Float>] = [], normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        for x in stride(from: Float(20),to: 85,by: 1) {
            for z in stride(from: Float(795),to: 860,by: 1) {
                let corners: [SIMD3<Float>] = [[x,0,z],[x+1,0,z],[x+1,0,z+1],[x,0,z+1]]
                let lifted = corners.map { SIMD3<Float>($0.x,andermattElevation($0.x,$0.z)-0.16,$0.z) }
                for face in [[0,2,1],[0,3,2]] {
                    let a = lifted[face[0]], b = lifted[face[1]], c = lifted[face[2]]
                    let normal = simd_normalize(simd_cross(b-a,c-a))
                    let start = UInt32(positions.count)
                    positions.append(contentsOf: [a,b,c]); normals.append(contentsOf: [normal,normal,normal])
                    indices.append(contentsOf: [start,start+1,start+2])
                }
            }
        }
        if let mesh = makeMesh(positions,normals,indices,name: "Andermatt illustrative valley") {
            let node = ModelEntity(mesh: mesh,materials: [material(0x91A77D)])
            town.addChild(node); mapTiles.append((node,[52.5,827.5],46,false))
        }
    }

    private func buildSwissMountains() {
        for peak in SwissGeography.peaks {
            let point = peak.point
            let andermatt = Catalog.city("andermatt").mapCenter
            let distance = hypot(point.x-andermatt.x,point.z-andermatt.z)
            let height = Float(max(2,peak.height - (distance < 100 ? 14 : 0)))
            let base = SIMD3<Float>(Float(point.x),0,Float(point.z))
            // These are deliberately sculpted silhouettes, not surveyed terrain.
            mountain(radius: height*1.4,height: height,color: 0x8D9F83,position: base)
            mountain(radius: height*0.7,height: height*0.55,color: 0xA3A99B,position: base + SIMD3<Float>(0,height*0.45,0))
            if peak.height > 25 {
                mountain(radius: height*0.29,height: height*0.23,color: 0xEBEDE0,position: base + SIMD3<Float>(0,height*0.77,0))
            }
        }
    }

    private func buildIllustrativeSettlements() {
        // Smaller unlocked centres use illustrative settlement masses around
        // real geographic centres until detailed local survey data is bundled.
        for city in Catalog.cities where city.id != "andermatt" && city.id != "zurich" {
            let center = city.mapCenter
            let group = Entity(); town.addChild(group)
            let x = Float(center.x), z = Float(center.z)
            for i in 0..<64 {
                let angle = Float(i)*2.39996
                let distance = sqrt(Float(i))*0.24
                let height: Float = 0.09 + Float(i%7)*0.025
                let position = SIMD3<Float>(x+cos(angle)*distance,height/2+0.01,z+sin(angle)*distance)
                box([0.12,height,0.18],i%3 == 0 ? 0xDCC4AB : 0xE3D6BD,position,parent: group)
                box([0.14,0.025,0.20],0xA48A77,position + SIMD3<Float>(0,height/2+0.01,0),parent: group)
            }
            mapTiles.append((group,[x,z],4,false))
        }
    }

    private func focusRegion() {
        let center = Catalog.city(cityID).mapCenter
        target = [Float(center.x),0,Float(center.z) + (isZurich ? 4 : 0)]
        radius = isZurich ? 32 : (cityID == "andermatt" ? 40 : 22)
        yaw = 0.12; pitch = cityID == "andermatt" ? 0.65 : 0.9
        refreshReadiness()
        updateCamera()
    }

    private func loadMap(_ resource: String, country: Bool) {
        guard mapTasks[resource] == nil, !loadedMaps.contains(resource) else { return }
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json") else {
            mapStatus = "Kartendaten fehlen"; return
        }
        mapStatus = "Schweizer Karte wird geladen"
        loadingLabel?.text = "Schweizer Karte wird geladen"
        loadingLabel?.isHidden = false
        mapTasks[resource] = Task { [weak self] in
            do {
                let document = try await Task.detached(priority: .userInitiated) {
                    try JSONDecoder().decode(RenderMap.self, from: Data(contentsOf: url,options: .mappedIfSafe))
                }.value
                guard let self, !Task.isCancelled else { return }
                if country {
                    let bounds = document.tiles.map(\.bounds).filter { $0.count == 4 }
                    if !bounds.isEmpty {
                        self.mapBounds = [bounds.map{$0[0]}.min()!,bounds.map{$0[1]}.min()!,bounds.map{$0[2]}.max()!,bounds.map{$0[3]}.max()!]
                    }
                }
                let focus = self.target
                let ordered = document.tiles.filter { $0.bounds.count == 4 }.sorted {
                    abs($0.bounds[0]-focus.x) + abs($0.bounds[1]-focus.z) < abs($1.bounds[0]-focus.x) + abs($1.bounds[1]-focus.z)
                }
                for tile in ordered {
                    guard !Task.isCancelled else { return }
                    self.installTile(tile,country: country)
                    self.updateMapDetail()
                    await Task.yield()
                }
                guard !Task.isCancelled else { return }
                if !country { self.installMapLabels(document.labels) }
                if resource == "zurich-city" { self.zurichLandmarks() }
                self.loadedMaps.insert(resource)
                self.mapTasks[resource] = nil
                self.refreshReadiness()
                self.updateCamera()
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.mapStatus = "Karte konnte nicht geladen werden"
                self.loadingLabel?.text = "Karte konnte nicht geladen werden"
                self.updateCamera()
            }
        }
    }

    private func installTile(_ tile: RenderMap.Tile, country: Bool) {
        guard tile.bounds.count == 4 else { return }
        let center = SIMD2<Float>((tile.bounds[0]+tile.bounds[2])/2,(tile.bounds[1]+tile.bounds[3])/2)
        let extent = max(tile.bounds[2]-tile.bounds[0],tile.bounds[3]-tile.bounds[1])
        let group = Entity()
        group.name = "city-tile:" + tile.id
        town.addChild(group)
        mapTiles.append((group,center,extent,country))
        var windows: [SIMD3<Float>] = []
        var windowNormals: [SIMD3<Float>] = []
        var windowIndices: [UInt32] = []
        var treeVertices: [SIMD3<Float>] = [], treeNormals: [SIMD3<Float>] = [], treeIndices: [UInt32] = []
        var treeCount = 0
        let palette: [String: UInt32] = ["building":0xE4D5BA,"building2":0xD3C9BA,"building3":0xE7C5AA,
            "roof":0xAD8B77,"roof2":0x89958D,"water":0x74B9BC,"park":0xACC68C,"forest":0x8EAE78,
            "road":0xD6D2C4,"rail":0x929C94,"boundary":0xBAC59E,"terrain":0x94AA88,"rock":0xA7AA9C,"snow":0xEDF0E4]
        for source in tile.meshes {
            guard source.positions.count >= 9, source.positions.count % 3 == 0, source.indices.count % 3 == 0 else { continue }
            var vertices = stride(from: 0,to: source.positions.count,by: 3).map {
                SIMD3<Float>(source.positions[$0],source.positions[$0+1],source.positions[$0+2])
            }
            guard source.indices.allSatisfy({ Int($0) < vertices.count }) else { continue }
            var indices = source.indices
            if !country, center.x > 15, center.x < 90, center.y > 790, center.y < 865 {
                if !source.kind.hasPrefix("building") && !source.kind.hasPrefix("roof") {
                    var refined: [SIMD3<Float>] = []
                    func triangle(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ depth: Int) {
                        if depth < 7 && max(simd_distance(a,b),max(simd_distance(b,c),simd_distance(c,a))) > 1.2 {
                            let ab = (a+b)/2, bc = (b+c)/2, ca = (c+a)/2
                            triangle(a,ab,ca,depth+1); triangle(ab,b,bc,depth+1)
                            triangle(ca,bc,c,depth+1); triangle(ab,bc,ca,depth+1)
                        } else { refined.append(contentsOf: [a,b,c]) }
                    }
                    for i in stride(from: 0,to: indices.count,by: 3) {
                        triangle(vertices[Int(indices[i])],vertices[Int(indices[i+1])],vertices[Int(indices[i+2])],0)
                    }
                    vertices = refined; indices = (0..<vertices.count).map(UInt32.init)
                }
                vertices = vertices.map { $0 + SIMD3<Float>(0,andermattElevation($0.x,$0.z),0) }
            }
            var normals = [SIMD3<Float>](repeating: .zero,count: vertices.count)
            for index in stride(from: 0,to: indices.count,by: 3) {
                let a = Int(indices[index]), b = Int(indices[index+1]), c = Int(indices[index+2])
                let cross = simd_cross(vertices[b]-vertices[a],vertices[c]-vertices[a])
                if simd_length_squared(cross) > 0.0000000001 {
                    normals[a] += cross; normals[b] += cross; normals[c] += cross
                    let centroid = (vertices[a]+vertices[b]+vertices[c])/3
                    if !country, (source.kind == "forest" || source.kind == "park"), treeCount < 40, index % 24 == 0 {
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
                    if !country, source.kind == "road", people.count < 96, index % 75 == 0 {
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
                            let left: SIMD3<Float> = p - across
                            let right: SIMD3<Float> = p + across
                            let lowerLeft: SIMD3<Float> = left - up
                            let lowerRight: SIMD3<Float> = right - up
                            let upperRight: SIMD3<Float> = right + up
                            let upperLeft: SIMD3<Float> = left + up
                            windows.append(contentsOf: [lowerLeft,lowerRight,upperRight,upperLeft])
                            windowNormals.append(contentsOf: [n,n,n,n])
                            windowIndices.append(contentsOf: [start,start+1,start+2,start,start+2,start+3])
                        }
                    }
                }
            }
            normals = normals.map { simd_length_squared($0) > 0 ? simd_normalize($0) : SIMD3<Float>(0,1,0) }
            if let mesh = makeMesh(vertices,normals,indices,name: tile.id + source.kind) {
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
            node.position = [label.x,0.65+andermattElevation(label.x,label.z),label.z]
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
        let focus = SIMD2<Float>(target.x,target.z)
        for (tile, center, extent, country) in mapTiles {
            tile.isEnabled = (country || radius < 700) && simd_distance(center,focus) < radius * 1.3 + extent
        }
        for (node, position) in mapLabels {
            node.isEnabled = radius > 16 && radius < 500 && simd_distance(position,focus) < radius*0.4
            node.orientation = camera.orientation
            node.scale = SIMD3<Float>(repeating: max(0.6,radius*0.04))
        }
        localRoutes.isEnabled = radius < 650
        nationalRoutes.isEnabled = radius >= 650
        let nextID = Catalog.cities.first { !unlockedRegions.contains($0.id) }?.id
        func priority(_ id: String) -> Int {
            if id == cityID { return 0 }
            if id == nextID { return 1 }
            return ["zurich", "bern", "basel", "geneva"].contains(id) ? 2 : 3
        }
        var occupied: [CGRect] = []
        for entry in regionMarkers.sorted(by: { priority($0.id) < priority($1.id) }) {
            let marker = entry.node
            marker.isEnabled = radius > 180 && simd_distance(entry.position,focus) < radius
            marker.position.y = max(12,radius*0.012)
            marker.orientation = camera.orientation
            let scale = max(2,radius*0.028)
            marker.scale = SIMD3<Float>(repeating: scale)
            entry.title.isEnabled = true
            guard marker.isEnabled, let view,
                  let left = view.project(marker.convert(position: [-entry.width/2,0.04,0],to: nil)),
                  let right = view.project(marker.convert(position: [entry.width/2,0.58,0],to: nil)) else { continue }
            let rect = CGRect(x: min(left.x,right.x)-4,y: min(left.y,right.y)-4,
                              width: abs(right.x-left.x)+8,height: abs(right.y-left.y)+8)
            if occupied.contains(where: { $0.intersects(rect) }) { entry.title.isEnabled = false }
            else { occupied.append(rect) }
        }
        for (person, origin, _, _) in people {
            person.isEnabled = radius < 20 && simd_distance(SIMD2<Float>(origin.x,origin.z),focus) < 8
        }
        for (day, evening, center) in detailTiles {
            let visible = radius < 55 && simd_distance(center,focus) < 26
            day.isEnabled = visible; evening.isEnabled = visible
        }
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
    private func buildTraffic(networks: [(String,[OwnedLine])], selected: String?) {
        traffic.children.removeAll(); vehicles.removeAll()
        localRoutes.children.removeAll(); nationalRoutes.children.removeAll()
        traffic.addChild(localRoutes); traffic.addChild(nationalRoutes)
        for (regionID, lines) in networks {
        for owned in lines {
            guard let route = Catalog.route(owned.id) else { continue }
            let points = route.points(in: regionID)
            guard points.count > 1 else { continue }
            let height: Float = route.kind == .ship ? 0.025 : 0.045
            if route.kind != .plane {
                drawRoute(points, height: height, width: regionID == cityID && selected == route.id ? 0.055 : 0.022, route: route,parent: localRoutes)
                drawRoute(points,height: height,width: 8,route: route,parent: nationalRoutes)
            }
            for index in 0..<owned.tier {
                let node = vehicle(route)
                node.scale = SIMD3<Float>(repeating: route.kind == .ship ? 0.3 : 0.16)
                node.name = regionID == cityID ? "route:\(route.id)" : "region:\(regionID)"
                node.generateCollisionShapes(recursive: true)
                let phase = Double(index) / Double(owned.tier)*2
                let pose = RouteMotion.pose(points: points,phase: time/route.duration+phase)
                node.position = [Float(pose.x),route.kind == .plane ? 3 + Float(sin(pose.fraction * .pi))*5 : 0.025 + andermattElevation(Float(pose.x),Float(pose.z)),Float(pose.z)]
                node.orientation = simd_quatf(angle: Float(pose.heading),axis: [0,1,0])
                node.isEnabled = radius < 650
                traffic.addChild(node)
                vehicles.append(.init(node: node,route: route,phase: phase,points: points,base: 0.025))
            }
        }
    }
    }
    private func drawRoute(_ points: [MapPoint], height: Float, width: Float, route: TransitRoute, parent: Entity) {
        guard points.count > 1 else { return }
        var vertices: [SIMD3<Float>] = [], normals: [SIMD3<Float>] = [], indices: [UInt32] = []
        for i in 1..<points.count {
            let a = SIMD3<Float>(Float(points[i-1].x),height,Float(points[i-1].z))
            let b = SIMD3<Float>(Float(points[i].x),height,Float(points[i].z))
            let delta = b-a
            guard simd_length_squared(delta) > 0.000001 else { continue }
            let side = simd_normalize(SIMD3<Float>(delta.z,0,-delta.x))*width/2
            let touchesValley = min(a.x,b.x) < 85 && max(a.x,b.x) > 20 && min(a.z,b.z) < 860 && max(a.z,b.z) > 795
            let steps = parent === nationalRoutes || !touchesValley ? 1 : max(1,Int(ceil(simd_length(delta)/0.3)))
            for step in 0..<steps {
                let p = a + delta * (Float(step)/Float(steps))
                let q = a + delta * (Float(step+1)/Float(steps))
                let start = UInt32(vertices.count)
                let corners = [p-side,p+side,q+side,q-side].map { point in
                    point + SIMD3<Float>(0,parent === nationalRoutes ? 0 : andermattElevation(point.x,point.z),0)
                }
                vertices.append(contentsOf: corners)
                normals.append(contentsOf: Array(repeating: SIMD3<Float>(0,1,0),count: 4))
                indices.append(contentsOf: [start,start+2,start+1,start,start+3,start+2])
            }
        }
        if let mesh = makeMesh(vertices,normals,indices,name: route.id) {
            let node = ModelEntity(mesh: mesh,materials: [UnlitMaterial(color: UIColor(hex: route.colorHex))])
            node.name = "route:" + route.id
            parent.addChild(node)
        }
        if parent === nationalRoutes { return }
        for point in [points.first!,points.last!] {
            let stop = box([0.08,0.012,0.08],0xFFF6D9,[Float(point.x),height+0.01+andermattElevation(Float(point.x),Float(point.z)),Float(point.z)],parent: traffic,round: 0.004)
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
            let segments = route.kind == .intercity ? 4 : (route.kind == .train || route.kind == .metro ? 2 : 1)
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
            var y = vehicle.base + andermattElevation(Float(pose.x),Float(pose.z))
            if vehicle.route.kind == .plane { y = 3 + Float(sin(pose.fraction * .pi))*5 }
            if vehicle.route.kind == .ship && !reducedMotion { y += Float(sin(time*2+vehicle.phase))*0.002 }
            vehicle.node.isEnabled = radius < 650
            vehicle.node.position = [Float(pose.x),y,Float(pose.z)]
            vehicle.node.orientation = simd_quatf(angle: Float(pose.heading), axis: [0,1,0])
        }
        guard !reducedMotion else { return }
        for (node, origin, phase, alongX) in people {
            let movement = Float(sin(time*0.12+Double(phase)))*0.03
            node.position = origin + SIMD3<Float>(alongX ? movement : 0,abs(Float(sin(time*5+Double(phase))))*0.001,alongX ? 0 : movement)
            node.position.y += andermattElevation(node.position.x,node.position.z) - andermattElevation(origin.x,origin.z)
        }
    }
    private func updateCamera() {
        let position = target + SIMD3<Float>(radius*cos(pitch)*sin(yaw),radius*sin(pitch),radius*cos(pitch)*cos(yaw))
        // Preserve depth precision from village detail to the whole country.
        camera.camera.near = max(0.02,radius*0.01)
        camera.camera.far = max(500,radius*3)
        camera.look(at: target,from: position,relativeTo: nil)
        updateMapDetail()
        if worldStarted && radius < 400 && simd_length(SIMD2<Float>(target.x,target.z)) < 150 { loadMap("zurich-city", country: false) }
        view?.accessibilityValue = "Schweiz · Zoom \(Int(radius)) · Fokus \(Int(target.x)),\(Int(target.z)) · \(mapStatus)"
    }
    private func overviewRadius() -> Float {
        let aspect = max(0.4, Float((view?.bounds.width ?? 390) / max(1, view?.bounds.height ?? 844)))
        let width = mapBounds[2]-mapBounds[0], depth = mapBounds[3]-mapBounds[1]
        return min(14000, max(width / aspect, depth) * 1.75)
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
        let bounds = mapBounds
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
        radius = max(4,min(14000,startRadius/Float(gesture.scale)))
        updateCamera()
    }
    @objc private func tap(_ gesture: UITapGestureRecognizer) {
        guard let view else { return }
        var hit = view.entity(at: gesture.location(in: view))
        while let entity = hit {
            if entity.name.hasPrefix("region:") { onRegionSelect?(String(entity.name.dropFirst(7))); return }
            if entity.name.hasPrefix("route:") { onSelect?(String(entity.name.dropFirst(6))); return }
            hit = entity.parent
        }
        // Suppressed labels keep a comfortable touch target around their dot.
        let location = gesture.location(in: view)
        var nearest: (String, CGFloat)?
        for entry in regionMarkers where entry.node.isEnabled {
            guard let projected = view.project(entry.node.convert(position: [0,-0.07,0],to: nil)) else { continue }
            let distance = hypot(projected.x-location.x,projected.y-location.y)
            if distance < 18 && distance < (nearest?.1 ?? 18) { nearest = (entry.id,distance) }
        }
        if let nearest { onRegionSelect?(nearest.0) }
    }
}
