import SwiftUI
import RealityKit
import UIKit
import TaktCore

struct CameraCommand: Equatable {
    enum Action { case reset, zoomIn, zoomOut }
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
        view.accessibilityIdentifier = "realitykit-canvas"
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
final class CityRenderer: NSObject {
    private weak var view: ARView?
    private let anchor = AnchorEntity(world: .zero)
    private let camera = PerspectiveCamera()
    private let sun = DirectionalLight()
    private let fill = DirectionalLight()
    private let town = Entity()
    private let traffic = Entity()
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
    private var radius: Float = 72
    private var target = SIMD3<Float>(0,0,0)
    private var startYaw: Float = 0
    private var startPitch: Float = 0
    private var startRadius: Float = 72
    private var night = false
    private var seed: UInt64 = 1234
    private var meshes: [String: MeshResource] = [:]
    private var materials: [UInt32: SimpleMaterial] = [:]
    private var windows: [ModelEntity] = []
    private var people: [(Entity, SIMD3<Float>, Float, Bool)] = []
    private var boats: [ModelEntity] = []
    private var vehicles: [MovingVehicle] = []
    private struct MovingVehicle {
        let node: Entity
        let route: TransitRoute
        let phase: Double
        let base: Float
    }

    func attach(_ view: ARView) {
        self.view = view
        view.environment.background = .color(UIColor(hex: 0xE1E9D8))
        view.environment.lighting.intensityExponent = 0.5
        view.renderOptions.insert(.disableMotionBlur)
        view.renderOptions.insert(.disableDepthOfField)
        view.scene.addAnchor(anchor)
        anchor.addChild(town); anchor.addChild(traffic); anchor.addChild(camera)
        camera.camera.fieldOfViewInDegrees = 37
        sun.light.color = UIColor(hex: 0xFFF3DB)
        sun.light.intensity = 2300
        var shadows = DirectionalLightComponent.Shadow()
        shadows.maximumDistance = 110
        sun.shadow = shadows
        sun.look(at: .zero, from: SIMD3<Float>(-18,35,17), relativeTo: nil)
        fill.light.intensity = 850
        fill.light.color = UIColor(hex: 0xE9F1EF)
        fill.look(at: .zero, from: SIMD3<Float>(20,15,-20), relativeTo: nil)
        anchor.addChild(sun); anchor.addChild(fill)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(drag(_:)))
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:))))
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
            town.children.removeAll(); traffic.children.removeAll(); people.removeAll(); windows.removeAll(); boats.removeAll()
            seed = state.cityID.utf8.reduce(UInt64(1234)) { $0 &* 31 &+ UInt64($1) }
            buildTown(city: state.currentCity)
            target = .zero; radius = 72; yaw = 0.75; pitch = 0.62
            updateCamera()
        }
        if night != state.settings.night || signature.isEmpty {
            night = state.settings.night
            view?.environment.background = .color(UIColor(hex: night ? 0x354C5A : 0xE1E9D8))
            sun.light.intensity = night ? 500 : 2300
            fill.light.intensity = night ? 280 : 850
            sun.light.color = UIColor(hex: night ? 0x9DB5DE : 0xFFF3DB)
            for window in windows { window.model?.materials = [material(night ? 0xFFE4A2 : 0x7EABB1)] }
        }
        let newSignature = state.currentLines.map { "\($0.id):\($0.tier)" }.joined(separator: ",") + (selected ?? "")
        if newSignature != signature {
            signature = newSignature
            buildTraffic(lines: state.currentLines, selected: selected)
        }
        if selected != self.selected {
            self.selected = selected
            if let selected, let route = Catalog.route(selected) {
                let middle = route.points[route.points.count / 2]
                target = SIMD3<Float>(Float(middle.x),0,Float(middle.z)); radius = 49; updateCamera()
            }
        }
        if command.id != commandID {
            commandID = command.id
            switch command.action {
            case .reset: target = .zero; radius = 72; yaw = 0.75; pitch = 0.62
            case .zoomIn: radius = max(25,radius - 8)
            case .zoomOut: radius = min(105,radius + 8)
            }
            updateCamera()
        }
    }

    func stop() {
        displayLink?.invalidate(); displayLink = nil
        anchor.removeFromParent()
        vehicles.removeAll(); people.removeAll(); windows.removeAll(); boats.removeAll()
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

    private func building(_ x: Float, _ z: Float, height: Float, color: UInt32, pitched: Bool) {
        let width: Float = 1.55, depth: Float = 1.5
        box([width+0.15,0.1,depth+0.15],0xCEC7B0,[x,0.2,z])
        box([width,height,depth],color,[x,0.25+height/2,z],round: 0.035)
        for y in stride(from: Float(0.75), through: height+0.05, by: 0.65) {
            for dx: Float in [-0.4,0.4] {
                windows.append(box([0.25,0.32,0.025],0x7EABB1,[x+dx,y,z+depth/2+0.02]))
                windows.append(box([0.025,0.32,0.25],0x7EABB1,[x+width/2+0.02,y,z+dx]))
                windows.append(box([0.025,0.32,0.25],0x7EABB1,[x-width/2-0.02,y,z+dx]))
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
    private func hills() {
        for (x,z,h,s): (Float,Float,Float,Float) in [(-13,-14,4.2,2.4),(-16,-13.5,3.1,2.1),(-12,-16,5,2.3)] {
            let hill = box([s,h,s],0x94AC82,[x,h/2-0.5,z],round: 0.6)
            hill.orientation = simd_quatf(angle: .pi/4, axis: [0,1,0])
            sphere(0.6,0xDCE3CC,[x,h-0.3,z])
        }
        box([0.75,0.7,0.75],0xDAB98F,[-15,3.6,-15])
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
            let height: Float = route.kind == .ship ? 0.22 : route.kind == .cable ? 4.8 : route.kind == .plane ? 5 : 0.31
            if route.kind != .plane {
                for i in 1..<route.points.count {
                    let a = route.points[i-1], b = route.points[i]
                    segment(from: [Float(a.x),height,Float(a.z)],to: [Float(b.x),height,Float(b.z)],width: selected == route.id ? 0.12 : 0.045,height: 0.02,color: route.colorHex,parent: traffic)
                }
            }
            if route.kind == .cable {
                for point in route.points { box([0.09,4.5,0.09],0x8C9F89,[Float(point.x),2.55,Float(point.z)],parent: traffic) }
            }
            if route.kind == .metro {
                for point in [route.points.first!,route.points.last!] {
                    box([0.65,0.2,0.65],route.colorHex,[Float(point.x)-0.75,0.32,Float(point.z)],parent: traffic)
                    box([0.1,0.75,0.1],route.colorHex,[Float(point.x)-0.75,0.75,Float(point.z)],parent: traffic)
                }
            }
            for index in 0..<owned.tier {
                let node = vehicle(route)
                node.name = "route:\(route.id)"
                node.generateCollisionShapes(recursive: true)
                traffic.addChild(node)
                vehicles.append(.init(node: node,route: route,phase: Double(index) / Double(owned.tier)*2,base: route.kind == .ship ? 0.05 : route.kind == .cable ? 3.45 : route.kind == .train ? 0.13 : 0.09))
            }
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
            let pose = RouteMotion.pose(points: vehicle.route.points, phase: time/vehicle.route.duration+vehicle.phase)
            var y = vehicle.base
            if vehicle.route.kind == .plane { y = 3 + Float(sin(pose.fraction * .pi))*5 }
            if vehicle.route.kind == .ship && !reducedMotion { y += Float(sin(time*2+vehicle.phase))*0.02 }
            vehicle.node.position = [Float(pose.x),y,Float(pose.z)]
            vehicle.node.orientation = simd_quatf(angle: Float(pose.heading), axis: [0,1,0])
        }
        guard !reducedMotion else { return }
        for (node, origin, phase, alongX) in people {
            let movement = Float(sin(time*0.12+Double(phase)))*1.1
            node.position = origin + SIMD3<Float>(alongX ? movement : 0,abs(Float(sin(time*5+Double(phase))))*0.012,alongX ? 0 : movement)
        }
        for (index,ripple) in boats.enumerated() { ripple.scale.x = 0.85+Float(sin(time+Double(index)))*0.25 }
    }
    private func updateCamera() {
        let position = target + SIMD3<Float>(radius*cos(pitch)*sin(yaw),radius*sin(pitch),radius*cos(pitch)*cos(yaw))
        camera.look(at: target,from: position,relativeTo: nil)
    }
    @objc private func drag(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .began { startYaw = yaw; startPitch = pitch }
        let delta = gesture.translation(in: view)
        yaw = startYaw-Float(delta.x)*0.006
        pitch = max(0.35,min(1.2,startPitch+Float(delta.y)*0.003))
        updateCamera()
    }
    @objc private func pinch(_ gesture: UIPinchGestureRecognizer) {
        if gesture.state == .began { startRadius = radius }
        radius = max(25,min(105,startRadius/Float(gesture.scale)))
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
