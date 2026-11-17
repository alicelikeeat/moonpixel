import SwiftUI
import UIKit
import RealityKit
import Metal
import simd
import Combine
import SpriteKit
import MoonPixelCore

// The 3D view: the same world, drawn as solids with RealityKit.
//
// Nothing is simulated here. `GameScene` keeps running the game exactly as in 2D (fixed steps, the
// traveller, saves); in 3D mode it stops drawing and this renderer draws instead, reading the same
// state every frame. The meshes come from MoonPixelCore (`Solid.swift`), which knows no graphics
// framework; this file only hands them to RealityKit, places them and moves the camera.
//
// Space: one tile is one unit; x east, y up, z south. A point of the world (16 units per tile, y
// southwards) is at (x / 16, ground, y / 16).

/// SwiftUI wrapper: the 3D picture and its touches, above the (now blank) SpriteKit view.
struct Solid3DView: UIViewRepresentable {
    @EnvironmentObject var model: GameModel
    func makeUIView(context: Context) -> SolidInputView { SolidInputView(model: model) }
    func updateUIView(_ v: SolidInputView, context: Context) {}
    static func dismantleUIView(_ v: SolidInputView, coordinator: ()) { v.renderer.stop() }
}

enum Solid3DLimits {
    /// Storeys drawn above and below the one you are on.
    static let storeySpan = 6
}

@MainActor
final class SolidRenderer {
    let view: ARView
    weak var model: GameModel?
    weak var host: SolidInputView?
    private let root = AnchorEntity(world: .zero)
    private let camera = PerspectiveCamera()
    private var update: Cancellable?

    /// Where the camera stands around what it looks at (radians); the distance follows the scene's zoom.
    var yaw: Float = 0
    /// Third person: how high the camera stands over the traveller (radians above the horizon).
    var pitch: Float = 0.92
    /// First person: where the eyes look, up (+) or down (-), never past straight up or down.
    var lookPitch: Float = 0
    static let lookLimit: Float = 85 * .pi / 180
    static let orbitRange: ClosedRange<Float> = 0.05...1.45
    private var seenReset = 0
    private var shownOpacity: Double = -1
    private var target = SIMD3<Float>(0, 0, 0)
    private var distance: Float = 12

    // chunks
    private struct ChunkEntry { var entity: ModelEntity; var key: BakeKey; var heights: [Float]; var ground: TextureResource; var groundHash: UInt64; var builtAt: Double; var props: [Entity]
        /// What was built, broken or opened in it, and what its neighbours read of its border, as shown.
        var structHash: UInt64; var edgeHash: UInt64 }
    /// Chunks to mesh again although their own revision did not change: a neighbour's border did.
    private var forced: Set<Int64> = []
    /// Chunks sent at once because something was built, broken or opened (no waiting behind growth).
    private var urgent: Set<Int64> = []
    private var urgentSent = 0, staleShown = 0, oldestStale = 0.0
    private var staleSince: [Int64: Double] = [:]
    /// When a chunk already on screen was last sent to be re-meshed (see `updateChunks`).
    private var lastRefresh = 0.0
    private var chunks: [Int64: ChunkEntry] = [:]
    private let queue = BakeQueue(maxInFlight: 2)
    private let work = DispatchQueue(label: "moonpixel.mesh", qos: .userInitiated, attributes: .concurrent)
    private var shownWorld = -1, shownEpoch = -1, shownDepth = -1

    // materials: everything but the ground tops shares one palette texture
    private var palette: TextureResource?
    private var solidMaterial = UnlitMaterial()
    private var light: Float = -1
    private var lightColor = UIColor.white

    // figures
    /// Figure meshes, bounded by an estimate of their bytes; the least used go first.
    private let meshes = ByteLRU<String, MeshResource>(budget: 24 << 20)
    private var agents: [Int: ModelEntity] = [:]
    private var soldiers: [Int: ModelEntity] = [:]
    private var shownSoldiers: Set<Int> = []
    private var animals: [Int: ModelEntity] = [:]
    private var roofs: [Int: (entity: ModelEntity, nation: Int)] = [:]
    private var standards: [Int: ModelEntity] = [:]
    /// Outside elevators: the car (moved to its real height every frame) and the shaft's rails.
    private var liftEntities: [Int: (car: ModelEntity, rails: [ModelEntity], top: Float)] = [:]
    private var pool: [ModelEntity] = []
    private let player = ModelEntity()
    private let playerRing = ModelEntity()
    private let selectRing = ModelEntity()
    private var previews: [ModelEntity] = []
    private var billboards: [Entity] = []

    // effects
    private struct Particle { var entity: ModelEntity; var v: SIMD3<Float>; var life: Float; var age: Float; var gravity: Float; var to: SIMD3<Float>?; var onEnd: (() -> Void)? }
    private var particles: [Particle] = []
    private var rainAcc: Float = 0

    init(model: GameModel) {
        self.model = model
        view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.renderOptions = [.disableMotionBlur, .disableDepthOfField, .disableGroundingShadows, .disableCameraGrain]
        view.environment.background = .color(UIColor(red: 0.56, green: 0.74, blue: 0.90, alpha: 1))
        view.scene.addAnchor(root)
        camera.camera.fieldOfViewInDegrees = 50
        camera.camera.near = 0.1
        camera.camera.far = 600
        root.addChild(camera)
        if let cg = Palette3D.bitmap.cgImage {
            palette = try? TextureResource.generate(from: cg, options: TextureResource.CreateOptions(semantic: .color, mipmapsMode: .none))
        }
        setLight(1, sky: UIColor(red: 0.56, green: 0.74, blue: 0.90, alpha: 1))
        for e in [player, playerRing, selectRing] { root.addChild(e) }
        playerRing.model = model3D(key: "ring-player") { Figure3D.plate(color: RGBA(hex: "#7fe6ff"), w: 0.9, d: 0.9, h: 0.04) }
        selectRing.model = model3D(key: "ring-select") { Figure3D.plate(color: RGBA(hex: "#fff266"), w: 1.0, d: 1.0, h: 0.05) }
        selectRing.isEnabled = false
        update = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] e in
            let dt = Float(e.deltaTime)
            MainActor.assumeIsolated { self?.frame(dt) }           // RealityKit calls this on the main thread
        }
    }

    func stop() {
        update?.cancel(); update = nil
        if model?.solid === self { model?.solid = nil }
    }

    // MARK: meshes and materials

    private func descriptor(_ m: Mesh3D, material: UInt32) -> MeshDescriptor {
        var d = MeshDescriptor()
        d.positions = MeshBuffers.Positions(m.positions)
        d.normals = MeshBuffers.Normals(m.normals)
        d.textureCoordinates = MeshBuffers.TextureCoordinates(m.uvs)
        d.primitives = .triangles(m.indices)
        d.materials = .allFaces(material)
        return d
    }

    private func resource(_ m: Mesh3D) -> MeshResource? {
        m.isEmpty ? nil : try? MeshResource.generate(from: [descriptor(m, material: 0)])
    }

    /// A cached model of a flat-coloured mesh (figures, roofs, markers).
    private func model3D(key: String, _ make: () -> Mesh3D) -> ModelComponent? {
        if let r = meshes.get(key) { return ModelComponent(mesh: r, materials: [solidMaterial]) }
        let m = make()
        guard let r = resource(m) else { return nil }
        meshes.put(key, r, bytes: m.positions.count * 32 + m.indices.count * 4 + 256)
        return ModelComponent(mesh: r, materials: [solidMaterial])
    }

    private func texture(_ t: TextureResource) -> MaterialParameters.Texture {
        // pixel art stays crisp: nearest sampling where the system lets a material choose its sampler
        if #available(iOS 18.0, *) {
            let d = MTLSamplerDescriptor()
            d.minFilter = .nearest; d.magFilter = .nearest; d.mipFilter = .notMipmapped
            return MaterialParameters.Texture(t, sampler: MaterialParameters.Texture.Sampler(d))
        }
        return MaterialParameters.Texture(t)
    }

    private func material(_ t: TextureResource?) -> UnlitMaterial {
        var m = UnlitMaterial()
        if let t = t { m.color = UnlitMaterial.BaseColor(tint: lightColor, texture: texture(t)) } else { m.color = UnlitMaterial.BaseColor(tint: lightColor) }
        return m
    }

    /// Day, night and weather: the meshes carry their own shading, so light is one tint over everything.
    private func setLight(_ l: Float, sky: UIColor) {
        if abs(l - light) < 0.02 { return }
        light = l
        let night = SIMD3<Float>(0.30, 0.36, 0.62)
        let c = night + (SIMD3<Float>(1, 1, 1) - night) * l
        lightColor = UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
        solidMaterial = material(palette)
        view.environment.background = .color(sky)
        for e in chunks.values { e.entity.model?.materials = materials(for: e) }
        func paint(_ e: Entity) {
            if let m = e as? ModelEntity, m.name != "chunk", m.name != "sprite", m.model != nil { m.model?.materials = [solidMaterial] }
            for c in e.children { paint(c) }
        }
        for c in root.children where c.name != "chunk" { paint(c) }
        for e in pool { e.model?.materials = [solidMaterial] }
    }

    private func materials(for e: ChunkEntry) -> [any RealityKit.Material] {
        // the floor you stand on, when it is a storey, is see-through too: what is below shows
        let ground = (model?.depth ?? 0) >= OpenWorld.storeyBase ? floorMaterial(e.ground) : material(e.ground)
        return (e.entity.model?.materials.count ?? 2) > 1 ? [ground, solidMaterial] : [ground]
    }

    /// A storey's floor: see-through by the setting (its sides and its edges stay solid, so it reads as a slab).
    /// Only the picture changes: the floor holds and is walked on the same at any setting.
    private func floorMaterial(_ t: TextureResource?) -> UnlitMaterial {
        var m = material(t)
        let a = Float(max(0.15, min(1, model?.floorOpacity ?? 0.45)))
        if a < 0.99 { m.blending = .transparent(opacity: .init(scale: a)) }
        return m
    }

    // MARK: frame

    private func frame(_ dt: Float) {
        guard let model = model, model.render3D, let scene = model.scene, model.world != nil, let society = model.society else { return }
        let t0 = CACurrentMediaTime()
        let world = model.activeWorld
        if shownWorld != model.epoch || shownEpoch != world.mapEpoch || shownDepth != model.depth {
            shownWorld = model.epoch; shownEpoch = world.mapEpoch; shownDepth = model.depth
            reset()
        }
        // light and sky
        let under = model.depth == 1
        let w = society.weather(at: scene.player)
        var l = under ? 0.62 : Float(0.25 + 0.75 * world.daylight)
        if !under { l *= 1 - Float(w.dim) * 0.6 }
        let day = CGFloat(under ? 0 : world.daylight)
        let sky = under ? UIColor(red: 0.03, green: 0.03, blue: 0.05, alpha: 1)
            : (w.fall == 3 ? UIColor(white: 0.78 * day + 0.08, alpha: 1) : UIColor(red: 0.05 + 0.51 * day, green: 0.07 + 0.67 * day, blue: 0.18 + 0.72 * day, alpha: 1))
        setLight(l, sky: sky)

        if model.inputReset != seenReset { seenReset = model.inputReset; host?.releaseTouches() }
        if model.floorOpacity != shownOpacity { shownOpacity = model.floorOpacity; resetLayers(); for e in chunks.values { e.entity.model?.materials = materials(for: e) } }
        // camera. First person: from the traveller's eyes, where the drag points them (the yaw and pitch are
        // only ever changed by the drag: nothing here pulls them back). Third person: around the traveller.
        let vp = scene.viewPos
        let body = society.realm.player.body
        let feet = model.watch == .none ? Float(body?.z ?? Double(groundY(world, vp))) : groundY(world, vp)
        let want = SIMD3<Float>(Float(vp.x / 16), feet, Float(vp.y / 16))
        let jump = abs(want.x - target.x) + abs(want.z - target.z) > 40
        target = jump ? want : SIMD3(want.x, target.y + (want.y - target.y) * min(1, dt * 10), want.z)
        distance = 24 / Float(max(0.2, scene.zoom))
        let first = model.viewMode == .first && model.watch == .none
        if first {
            let eye = SIMD3<Float>(want.x, feet + 1.35, want.z)
            let dir = SIMD3<Float>(-sin(yaw) * cos(lookPitch), sin(lookPitch), -cos(yaw) * cos(lookPitch))
            camera.look(at: eye + dir, from: eye, relativeTo: nil)
        } else {
            var eye = target + distance * SIMD3<Float>(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
            // never under the ground behind the traveller
            let under = groundY(world, Vec2(Double(eye.x * 16), Double(eye.z * 16))) + 0.4
            if eye.y < under { eye.y = under }
            camera.look(at: target + SIMD3<Float>(0, 0.6, 0), from: eye, relativeTo: nil)
        }
        player.isEnabled = !first                     // through your own eyes your head is not in the way
        playerRing.isEnabled = !first
        cameraState = String(format: "%@ yaw %.2f pitch %.2f", first ? "first" : "third", yaw, first ? lookPitch : pitch)

        updateChunks(world, model)
        updateLayers(model)
        let reach = Double(distance) * 1.5 * 16 + 64
        updateActors(world, society, model, scene, reach: reach, dt: dt)
        if !model.plainRender { updateSoldiers(world, society, model, reach: reach, dt: dt); updateRoofs(world, society, model, scene, reach: reach) }
        updateAnimals(world, society, model, reach: reach, dt: dt)
        updateStandards(world, society, model, reach: reach)
        updateLifts(society, model, reach: reach)
        updateMachines(world, society, model, reach: reach)
        updateLabels(world, society, model, reach: reach)
        updatePreview(world, scene)
        updateWeather(w.fall, under: under, dt: dt)
        stepParticles(dt)
        let q = simd_quatf(angle: yaw, axis: [0, 1, 0])
        for b in billboards { b.orientation = q }
        model.perf.phase("3d", CACurrentMediaTime() - t0)
    }

    /// Another world, a new map or another layer: nothing drawn before belongs here.
    private func reset() {
        for e in chunks.values { e.entity.removeFromParent() }
        chunks = [:]; billboards = []; queue.dropAll()
        resetLayers()
        for d in [agents, soldiers, animals, standards] { for e in d.values { e.removeFromParent() } }
        for v in liftEntities.values { v.car.removeFromParent(); for r in v.rails { r.removeFromParent() } }
        liftEntities = [:]
        agents = [:]; soldiers = [:]; animals = [:]; standards = [:]; shownSoldiers = []
        for r in roofs.values { r.entity.removeFromParent() }
        roofs = [:]
        for p in particles { p.entity.removeFromParent() }
        particles = []
        host?.clearLabels()
        target = SIMD3(0, -1000, 0)
    }

    /// Top of the ground under a point: from the chunk on screen when there is one, else worked out.
    func groundY(_ world: OpenWorld, _ p: Vec2) -> Float {
        let t = p.tile
        if let e = chunks[MP.chunkKey(t.x >> 5, t.y >> 5)] { return e.heights[(t.y & 31) * 32 + (t.x & 31)] }
        return Terrain3D.groundY(world: world, at: p)
    }

    private func place(_ p: Vec2, _ world: OpenWorld, lift: Float = 0) -> SIMD3<Float> {
        SIMD3(Float(p.x / 16), groundY(world, p) + lift, Float(p.y / 16))
    }

    // MARK: chunks

    private func updateChunks(_ world: OpenWorld, _ model: GameModel) {
        let r = min(3, Int(distance * 1.3 / 32) + 1)
        let ccx = Int((target.x / 32).rounded(.down)), ccy = Int((target.z / 32).rounded(.down))
        let wid = model.epoch, ep = world.mapEpoch, depth = model.depth
        let now = CACurrentMediaTime()
        var visible = Set<Int64>()
        for cy in (ccy - r)...(ccy + r) { for cx in (ccx - r)...(ccx + r) {
            let k = MP.chunkKey(cx, cy)
            visible.insert(k)
            let key = BakeKey(world: wid, epoch: ep, depth: depth, chunk: k, revision: world.revision(cx, cy))
            if chunks[k]?.key == key && !forced.contains(k) { staleSince[k] = nil; continue }
            if chunks[k] != nil && staleSince[k] == nil { staleSince[k] = now }
            // what the player built, broke or opened is shown at once; other changes (crops grow; at 64x
            // this is constant) are re-meshed at most every two seconds, so the picture never starves the game
            var now1 = false
            if let shown = chunks[k] {
                let hash = Mesher3D.structureHash(world.chunk(cx, cy).layers)
                now1 = hash != shown.structHash || forced.contains(k)
                if now1 { urgent.insert(k) } else if now - shown.builtAt < 2 { continue }
            }
            let dx = Float(cx * 32 + 16) - target.x, dz = Float(cy * 32 + 16) - target.z
            queue.want(key, priority: now1 ? -1e6 + Double(dx * dx + dz * dz) : Double(dx * dx + dz * dz) + (chunks[k] != nil ? 1e6 : 0))      // urgent, then missing, then the rest
        } }
        staleShown = staleSince.count
        oldestStale = staleSince.values.map { now - $0 }.max() ?? 0
        queue.drop { !visible.contains($0.chunk) || $0.world != wid || $0.epoch != ep || $0.depth != depth }
        for key in queue.next() {
            // refreshes of chunks already on screen are also spaced out as a whole: four a second at most
            let had = chunks[key.chunk]
            if urgent.remove(key.chunk) != nil { urgentSent += 1; forced.remove(key.chunk) }
            else if had != nil {
                if now - lastRefresh < 0.25 { _ = queue.finished(key, current: nil); continue }
                lastRefresh = now
            }
            // the snapshot is taken here, on the main thread; the mesh and the ground picture are made elsewhere
            let input = ChunkInput3D(world: world, cx: MP.keyCX(key.chunk), cy: MP.keyCY(key.chunk))
            let gen = world.gen
            let oldHash = had?.groundHash
            work.async { [weak self] in
                let t0 = CACurrentMediaTime()
                let mesh = Mesher3D.build(input, gen: gen)
                // the ground picture only depends on the two flat layers: when they are the same, the old texture stays
                var hash: UInt64 = 1469598103934665603
                for l in 0..<2 { for v in input.layers[l] { hash = (hash ^ UInt64(v)) &* 1099511628211 } }
                let cg = hash == oldHash ? nil : PixelArt.bakeGround(layers: input.layers).cgImage
                let sh = Mesher3D.structureHash(input.layers), eh = Mesher3D.edgeHash(input.layers)
                let took = CACurrentMediaTime() - t0
                DispatchQueue.main.async { self?.built(key, mesh, cg, hash, took, structHash: sh, edgeHash: eh) }
            }
        }
        for (k, e) in chunks {
            let cx = MP.keyCX(k), cy = MP.keyCY(k)
            if abs(cx - ccx) > r + 1 || abs(cy - ccy) > r + 1 {
                e.entity.removeFromParent()
                billboards.removeAll { b in e.props.contains { $0 === b } }
                chunks[k] = nil
                staleSince[k] = nil; forced.remove(k); urgent.remove(k)
            }
        }
    }

    private func built(_ key: BakeKey, _ mesh: ChunkMesh3D, _ cg: CGImage?, _ groundHash: UInt64, _ took: Double, structHash: UInt64, edgeHash: UInt64) {
        guard let model = model, model.world != nil, model.render3D else { _ = queue.finished(key, current: nil); return }
        let world = model.activeWorld
        let cx = MP.keyCX(key.chunk), cy = MP.keyCY(key.chunk)
        let current = BakeKey(world: model.epoch, epoch: world.mapEpoch, depth: model.depth, chunk: key.chunk, revision: world.revision(cx, cy))
        // a result for an older revision is still better than what is shown, unless the place itself changed
        let fits = key.world == current.world && key.epoch == current.epoch && key.depth == current.depth
        _ = queue.finished(key, current: current)
        guard fits else { return }
        model.perf.phase("mesh", took)
        let t0 = CACurrentMediaTime()
        let old = chunks[key.chunk]
        let made = cg.flatMap { try? TextureResource.generate(from: $0, options: TextureResource.CreateOptions(semantic: .color, mipmapsMode: .none)) }
        guard let tex = made ?? (old?.groundHash == groundHash ? old?.ground : nil) else { return }
        var parts = [descriptor(mesh.ground, material: 0)]
        if !mesh.solid.isEmpty { parts.append(descriptor(mesh.solid, material: 1)) }
        guard let res = try? MeshResource.generate(from: parts) else { return }
        let entity = old?.entity ?? {
            let e = ModelEntity()
            e.name = "chunk"
            e.position = SIMD3(Float(cx * 32), 0, Float(cy * 32))
            root.addChild(e)
            return e
        }()
        if let old = old {
            for p in old.props { p.removeFromParent() }
            billboards.removeAll { b in old.props.contains { $0 === b } }
        }
        var entry = ChunkEntry(entity: entity, key: key, heights: mesh.heights, ground: tex, groundHash: groundHash, builtAt: CACurrentMediaTime(), props: [],
                               structHash: structHash, edgeHash: edgeHash)
        // its border changed: the neighbours on screen read it, so they are meshed again too, at once
        if let old = old, old.edgeHash != edgeHash {
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] { let n = MP.chunkKey(cx + dx, cy + dy); if chunks[n] != nil { forced.insert(n) } }
        }
        entity.model = ModelComponent(mesh: res, materials: mesh.solid.isEmpty ? [material(tex)] : [material(tex), solidMaterial])
        // imported pictures placed in the world stand upright and turn to the camera
        for p in world.chunk(cx, cy).props {
            guard let t = model.assets[String(p.key.dropFirst(6))], let e = sprite(t) else { continue }
            e.position = SIMD3(Float(p.x / 16) - Float(cx * 32), mesh.heights[(p.tileY & 31) * 32 + (p.tileX & 31)], Float(p.y / 16) - Float(cy * 32))
            entity.addChild(e)
            entry.props.append(e); billboards.append(e)
        }
        chunks[key.chunk] = entry
        model.perf.phase("upload", CACurrentMediaTime() - t0)
    }

    // MARK: the other layers of the stack (storeys above, or the ground under the storey you are on)

    private struct LayerChunk: Hashable { let depth: Int, chunk: Int64 }
    private var layerChunks: [LayerChunk: (entity: ModelEntity, revision: Int)] = [:]
    private var layerWaiting: Set<LayerChunk> = []

    /// Every built storey is drawn at its height, together with the ground, wherever you stand (not underground):
    /// a building looks as tall as it is. Only chunks something was built in are meshed; a chunk is meshed again
    /// when its revision changes, two at most a frame.
    private func updateLayers(_ model: GameModel) {
        guard let society = model.society else { return }
        let here = model.depth
        var show: [Int] = []
        if here != 1 {
            // the storeys near the one you are on (built ones and the floors of standing towers), never all of them
            let n = here >= OpenWorld.storeyBase ? here - OpenWorld.storeyBase : 0
            show = society.storeysNear(n, span: Solid3DLimits.storeySpan).map { OpenWorld.storeyBase + $0 } + [0]
            show.removeAll { $0 == here }
        }
        let r = min(3, Int(distance * 1.3 / 32) + 1)
        let ccx = Int((target.x / 32).rounded(.down)), ccy = Int((target.z / 32).rounded(.down))
        var wanted = Set<LayerChunk>()
        var started = 0
        for d in show {
            let w = society.layer(d)
            for cy in (ccy - r)...(ccy + r) { for cx in (ccx - r)...(ccx + r) {
                // the ground is drawn wherever you look; a storey only where something was built on it
                if d != 0 && !w.touched(cx, cy) && !society.towerCovers(storey: d - OpenWorld.storeyBase, cx: cx, cy: cy) { continue }
                let lk = LayerChunk(depth: d, chunk: MP.chunkKey(cx, cy))
                wanted.insert(lk)
                let rev = w.revision(cx, cy)
                if let e = layerChunks[lk], e.revision == rev { continue }
                guard started < 2, !layerWaiting.contains(lk) else { continue }
                started += 1
                layerWaiting.insert(lk)
                let input = ChunkInput3D(world: w, cx: cx, cy: cy)
                let gen = w.gen
                work.async { [weak self] in
                    let mesh = Mesher3D.build(input, gen: gen)
                    let cg = PixelArt.bakeGround(layers: input.layers).cgImage
                    DispatchQueue.main.async { self?.layerBuilt(lk, mesh, cg, rev) }
                }
            } }
        }
        for (k, e) in layerChunks where !wanted.contains(k) { e.entity.removeFromParent(); layerChunks[k] = nil }
    }

    private func layerBuilt(_ lk: LayerChunk, _ mesh: ChunkMesh3D, _ cg: CGImage?, _ rev: Int) {
        layerWaiting.remove(lk)
        guard let model = model, model.render3D, model.depth != 1 else { return }
        let tex = cg.flatMap { try? TextureResource.generate(from: $0, options: TextureResource.CreateOptions(semantic: .color, mipmapsMode: .none)) }
        var parts: [MeshDescriptor] = []
        if !mesh.ground.isEmpty && tex != nil { parts.append(descriptor(mesh.ground, material: 0)) }
        if !mesh.solid.isEmpty { parts.append(descriptor(mesh.solid, material: parts.isEmpty ? 0 : 1)) }
        let entity = layerChunks[lk]?.entity ?? {
            let e = ModelEntity()
            e.name = "layer"
            e.position = SIMD3(Float(MP.keyCX(lk.chunk) * 32), 0, Float(MP.keyCY(lk.chunk) * 32))
            root.addChild(e)
            return e
        }()
        if parts.isEmpty { entity.model = nil }
        else if let res = try? MeshResource.generate(from: parts) {
            var mats: [any RealityKit.Material] = []
            if !mesh.ground.isEmpty, let t = tex { mats.append(lk.depth >= OpenWorld.storeyBase ? floorMaterial(t) : material(t)) }
            if !mesh.solid.isEmpty { mats.append(solidMaterial) }
            entity.model = ModelComponent(mesh: res, materials: mats)
        }
        layerChunks[lk] = (entity, rev)
    }

    private func resetLayers() {
        for e in layerChunks.values { e.entity.removeFromParent() }
        layerChunks = [:]; layerWaiting = []
    }

    /// An upright picture, 16 pixels to the tile, standing on its bottom edge.
    private func sprite(_ t: SKTexture) -> ModelEntity? {
        let cg = t.cgImage()
        guard let tex = try? TextureResource.generate(from: cg, options: TextureResource.CreateOptions(semantic: .color, mipmapsMode: .none)) else { return nil }
        let w = Float(cg.width) / 16, h = Float(cg.height) / 16
        var m = Mesh3D()
        m.quad([-w / 2, 0, 0], [w / 2, 0, 0], [w / 2, h, 0], [-w / 2, h, 0], normal: [0, 0, 1], uv: ([0, 0], [1, 0], [1, 1], [0, 1]))
        guard let res = resource(m) else { return nil }
        var mat = UnlitMaterial()
        mat.color = UnlitMaterial.BaseColor(tint: .white, texture: texture(tex))
        mat.blending = .transparent(opacity: 1.0)
        mat.opacityThreshold = 0.5
        let e = ModelEntity(mesh: res, materials: [mat])
        e.name = "sprite"
        return e
    }

    // MARK: people

    private func take() -> ModelEntity {
        let e = pool.popLast() ?? ModelEntity()
        e.isEnabled = true
        e.scale = [1, 1, 1]
        e.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])      // a pooled entity may have been a turned figure
        root.addChild(e)
        return e
    }

    private func give(_ e: ModelEntity) {
        e.removeFromParent()
        for c in e.children.map({ $0 }) { c.removeFromParent() }
        if pool.count < 480 { pool.append(e) }
    }

    private func human(_ look: Look, moving: Bool, acting: Bool, held: String, child: Bool, female: Bool, phase: Int) -> ModelComponent? {
        let frame = acting ? (phase % 2 == 0 ? 3 : 0) : (moving ? 1 + phase % 2 : 0)
        let key = "h\(look.skin)\(look.hair)\(look.shirt)\(look.pants)\(look.shoes)\(look.face)\(look.style)\(frame)\(held)\(child)\(female)"
        return model3D(key: key) { Figure3D.human(look, frame: frame, held: held, child: child, female: female, face: look.face.isEmpty ? nil : PixelArt.faces[look.face]) }
    }

    private func turn(_ e: Entity, facing f: Vec2, lying: Bool = false) {
        let q = simd_quatf(angle: Float(atan2(f.x, f.y)), axis: [0, 1, 0])
        e.orientation = lying ? q * simd_quatf(angle: -.pi / 2, axis: [1, 0, 0]) : q
    }

    private func settle(_ e: Entity, at p: SIMD3<Float>, dt: Float, fresh: Bool) {
        // steps between heights are climbed over a moment instead of in one frame
        e.position = fresh ? p : SIMD3(p.x, e.position.y + (p.y - e.position.y) * min(1, dt * 12), p.z)
    }

    private func mount(_ e: ModelEntity, rides: Bool, phase: Int, moving: Bool) {
        let horse = e.children.first { $0.name == "horse" } as? ModelEntity
        if rides {
            let h = horse ?? { let h = ModelEntity(); h.name = "horse"; h.position = [0, -Figure3D.saddleHeight, 0]; e.addChild(h); return h }()
            let f = moving ? phase % 2 : 0
            h.model = model3D(key: "horse\(f)") { Figure3D.horse(frame: f) }
        } else { horse?.removeFromParent() }
    }

    private func updateActors(_ world: OpenWorld, _ society: Society, _ model: GameModel, _ scene: GameScene, reach: Double, dt: Float) {
        let now = world.time
        let phase = Int(CACurrentMediaTime() * 6.5)
        var seen = Set<Int>()
        let upstairs = world.storey > 0 ? society.storeyView(storey: world.storey, center: scene.viewPos, halfW: reach, halfH: reach) : (shown: [], at: [:])
        let split: (shown: [Agent], badges: [TilePos: Int]) = world.storey > 0 ? (upstairs.shown, [:]) : (model.depth > 0 ? ([], [:])
            : society.crowdSplit(center: scene.viewPos, halfW: reach, halfH: reach, limit: GameScene.maxCharacters, soldiersApart: !model.plainRender))
        for a in split.shown {
            seen.insert(a.id)
            let fresh = agents[a.id] == nil
            let e = agents[a.id] ?? take()
            agents[a.id] = e
            let st = a.stage(now)
            var look = a.look
            if a.age(now) >= 58 && look.face.isEmpty { look.hair = "#e0e0e8" }
            let working = a.task.map { $0.stage == 1 && ["chop", "mine", "build", "forage", "reap", "sow", "plant"].contains($0.act) } ?? false
            var held = st == "elder" ? "cane" : (GameScene.jobTool[a.job] ?? "")
            if working && a.task?.act == "build" { held = "hammer" }
            if a.legion != nil { held = ["sword", "bow", "sword", "hammer", "basket"][min(4, a.unit ?? 0)] }
            e.model = human(look, moving: a.moving && !a.sleeping, acting: working, held: held, child: st == "child", female: a.female, phase: phase + a.id)
            let rides = a.legion != nil && a.unit == MoonPixelCore.Unit.cavalry
            mount(e, rides: rides, phase: phase + a.id, moving: a.moving)
            turn(e, facing: a.facing, lying: a.sleeping)
            settle(e, at: place(upstairs.at[a.id] ?? a.pos, world, lift: (rides ? Figure3D.saddleHeight : 0) + (a.sleeping ? 0.25 : 0)), dt: dt, fresh: fresh)
        }
        for (id, e) in agents where !seen.contains(id) { give(e); agents[id] = nil }
        host?.badges = split.badges

        // the traveller
        let held = GameModel.weapons[model.weaponIndex]
        player.model = human(model.playerLook, moving: scene.moving, acting: scene.striking, held: held, child: false, female: false, phase: phase)
        turn(player, facing: scene.facing)
        let feetAt = place(scene.player, world)
        let bodyZ = society.realm.player.body.map { Float($0.z) } ?? feetAt.y
        settle(player, at: SIMD3(feetAt.x, bodyZ, feetAt.z), dt: dt, fresh: abs(player.position.x - Float(scene.player.x / 16)) > 6 || abs(player.position.y - bodyZ) > 1.5)
        playerRing.position = player.position + SIMD3<Float>(-0.45, 0.02, -0.45)
        if let a = society.agents[model.selectedID] {
            selectRing.isEnabled = true
            selectRing.position = place(a.pos, world, lift: 0.03) + SIMD3<Float>(-0.5, 0, -0.5)
        } else { selectRing.isEnabled = false }
    }

    private func updateSoldiers(_ world: OpenWorld, _ society: Society, _ model: GameModel, reach: Double, dt: Float) {
        var seen = Set<Int>()
        var masses: [Int: Int] = [:]
        if model.depth == 0, let scene = model.scene {
            let detail = BattleDetail.at(zoom: Double(scene.zoom))
            let v = society.battleView(center: scene.viewPos, halfW: reach, halfH: reach, limit: detail == .far ? 0 : scene.renderBudget.soldiers, previous: shownSoldiers)
            for m in v.masses { masses[m.legion] = m.hidden }
            let phase = Int(CACurrentMediaTime() * 6.5)
            for a in v.shown {
                guard let lid = a.legion, let lg = society.realm.legion(lid) else { continue }
                seen.insert(a.id)
                let fresh = soldiers[a.id] == nil
                let e = soldiers[a.id] ?? take()
                soldiers[a.id] = e
                var fighting = false
                if detail == .near {
                    if lg.state == 4, let f = lg.foe.flatMap({ society.realm.legion($0) }) { fighting = a.pos.distance(to: f.pos) < 150 }
                    else if lg.state == 2, (lg.phase ?? 0) >= 1, let t = society.settlements[lg.target] { fighting = a.pos.distance(to: t.center.center) < 220 }
                }
                let held = ["sword", "bow", "sword", "hammer", "basket"][min(4, a.unit ?? 0)]
                e.model = human(a.look, moving: a.moving, acting: fighting, held: held, child: false, female: a.female, phase: phase + a.id)
                let rides = detail == .near && a.unit == MoonPixelCore.Unit.cavalry
                mount(e, rides: rides, phase: phase + a.id, moving: a.moving)
                turn(e, facing: a.facing)
                settle(e, at: place(a.pos, world, lift: rides ? Figure3D.saddleHeight : 0), dt: dt, fresh: fresh)
            }
        }
        for (id, e) in soldiers where !seen.contains(id) { give(e); soldiers[id] = nil }
        shownSoldiers = seen
        host?.masses = masses
    }

    private func updateAnimals(_ world: OpenWorld, _ society: Society, _ model: GameModel, reach: Double, dt: Float) {
        var seen = Set<Int>()
        if model.depth == 0, let scene = model.scene {
            let frame = Int(CACurrentMediaTime() * 5)
            for a in society.realm.fauna.animals {
                if abs(a.pos.x - scene.viewPos.x) > reach || abs(a.pos.y - scene.viewPos.y) > reach { continue }
                seen.insert(a.id)
                let fresh = animals[a.id] == nil
                let e = animals[a.id] ?? take()
                animals[a.id] = e
                let f = a.moving ? frame % 2 : 0
                e.model = model3D(key: "a\(a.kind)-\(f)") { Figure3D.animal(a.species, frame: f) }
                let d = a.to - a.pos
                turn(e, facing: a.moving && d.length > 1 ? d : Vec2(a.facing, 0.4))
                settle(e, at: place(a.pos, world), dt: dt, fresh: fresh)
            }
        }
        for (id, e) in animals where !seen.contains(id) { give(e); animals[id] = nil }
    }

    // MARK: buildings and armies

    private func updateRoofs(_ world: OpenWorld, _ society: Society, _ model: GameModel, _ scene: GameScene, reach: Double) {
        var seen = Set<Int>()
        if model.depth == 0 {
            let c = scene.viewPos.tile, half = Int(reach / 16)
            let who = model.following ? (society.agents[model.selectedID]?.pos ?? scene.player) : scene.player
            for r in society.roofs(minX: c.x - half, minY: c.y - half, maxX: c.x + half, maxY: c.y + half) {
                seen.insert(r.building)
                if roofs[r.building] == nil || roofs[r.building]?.nation != r.nation {
                    roofs[r.building]?.entity.removeFromParent()
                    let e = ModelEntity()
                    e.model = model3D(key: "roof\(r.nation)-\(r.w)x\(r.h)") { Figure3D.roof(nation: r.nation, w: r.w, h: r.h) }
                    root.addChild(e)
                    roofs[r.building] = (e, r.nation)
                }
                guard let e = roofs[r.building]?.entity else { continue }
                // the roof sits on the walls of the highest corner
                var y: Float = -100
                for t in [TilePos(r.x, r.y), TilePos(r.x + r.w - 1, r.y), TilePos(r.x, r.y + r.h - 1), TilePos(r.x + r.w - 1, r.y + r.h - 1)] { y = max(y, groundY(world, t.center)) }
                e.position = SIMD3(Float(r.x), y + 1.5, Float(r.y))
                // whoever the camera is with must stay visible: the roof over them is lifted away
                let inside = who.x >= Double(r.x * 16) && who.x < Double((r.x + r.w) * 16) && who.y >= Double(r.y * 16) && who.y < Double((r.y + r.h) * 16)
                e.isEnabled = !inside
            }
        }
        for (id, r) in roofs where !seen.contains(id) { r.entity.removeFromParent(); roofs[id] = nil }
    }

    private var machines: [Int: ModelEntity] = [:]
    /// Machines of the regional wars standing by a town in view, as models in their nation's colour;
    /// aircraft and sky carriers hang in the air above.
    private func updateMachines(_ world: OpenWorld, _ society: Society, _ model: GameModel, reach: Double) {
        var seen = Set<Int>()
        if model.depth == 0, let scene = model.scene {
            for m in society.machinesInView() where abs(m.pos.x - scene.viewPos.x) < reach * 1.5 && abs(m.pos.y - scene.viewPos.y) < reach * 1.5 {
                seen.insert(m.id)
                let e = machines[m.id] ?? take()
                machines[m.id] = e
                e.model = model3D(key: "machine:" + m.kind + m.color) { Figure3D.machine(m.kind, color: RGBA(hex: m.color)) }
                e.position = place(m.pos, world, lift: m.layer == .nearSpace ? 14 : (m.layer == .highAir ? 9 : (m.layer == .lowAir ? 5 : 0)))
            }
        }
        for (id, e) in machines where !seen.contains(id) { give(e); machines[id] = nil }
    }

    /// Every elevator in reach: rails up the outside from the lowest landing to above the highest, and
    /// the car at the height the elevator really has now.
    private func updateLifts(_ society: Society, _ model: GameModel, reach: Double) {
        var seen = Set<Int>()
        if model.depth != 1 {
            for e in society.realm.lifts where !e.stops.isEmpty {
                let c = Vec2(Double(e.x * 16 + e.w * 8), Double(e.y * 16 + e.d * 8))
                guard c.distance(to: model.scene?.viewPos ?? c) <= reach + 64 else { continue }
                seen.insert(e.id)
                let bottom = Float(e.stops.first!.z), top = Float(e.stops.last!.z) + 2
                var entry = liftEntities[e.id]
                if entry == nil || entry!.top != top {
                    if let old = entry { old.car.removeFromParent(); for r in old.rails { r.removeFromParent() } }
                    let car = ModelEntity()
                    car.model = model3D(key: "lift-car-\(e.w)x\(e.d)") { Figure3D.liftCar(w: Float(e.w), d: Float(e.d)) }
                    root.addChild(car)
                    var rails: [ModelEntity] = []
                    for (dx, dz) in [(Float(-0.14), Float(-0.14)), (Float(e.w), Float(-0.14)), (Float(-0.14), Float(e.d)), (Float(e.w), Float(e.d))] {
                        let r = ModelEntity()
                        r.model = model3D(key: "lift-rail") { Figure3D.liftRail() }
                        r.position = SIMD3(Float(e.x) + dx, bottom, Float(e.y) + dz)
                        r.scale = SIMD3(1, max(0.1, top - bottom), 1)
                        root.addChild(r); rails.append(r)
                    }
                    entry = (car, rails, top)
                    liftEntities[e.id] = entry
                }
                entry!.car.position = SIMD3(Float(e.x), Float(e.z), Float(e.y))
            }
        }
        for (id, v) in liftEntities where !seen.contains(id) { v.car.removeFromParent(); for r in v.rails { r.removeFromParent() }; liftEntities[id] = nil }
    }

    private func updateStandards(_ world: OpenWorld, _ society: Society, _ model: GameModel, reach: Double) {
        var seen = Set<Int>()
        var infos: [Society.LegionInfo] = []
        if model.depth == 0, let scene = model.scene {
            for l in society.legionInfos() {
                if abs(l.pos.x - scene.viewPos.x) > reach * 1.5 || abs(l.pos.y - scene.viewPos.y) > reach * 1.5 { continue }
                seen.insert(l.id)
                let e = standards[l.id] ?? take()
                standards[l.id] = e
                e.model = model3D(key: "std\(l.color)") { Figure3D.standard(color: RGBA(hex: l.color)) }
                e.position = place(l.pos, world)
                e.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
                infos.append(l)
            }
        }
        for (id, e) in standards where !seen.contains(id) { give(e); standards[id] = nil }
        host?.legions = infos
    }

    /// Names and counts are ordinary labels laid over the picture where their place in the world falls on screen.
    private func updateLabels(_ world: OpenWorld, _ society: Society, _ model: GameModel, reach: Double) {
        guard let host = host, let scene = model.scene else { return }
        var out: [String: (String, CGPoint, UIColor, CGFloat)] = [:]
        // what is behind the camera would project to nonsense: only places in front of it get a label
        let eye = camera.position(relativeTo: nil), fwd = simd_normalize(target - camera.position(relativeTo: nil))
        func screen(_ p: SIMD3<Float>) -> CGPoint? {
            guard simd_dot(p - eye, fwd) > 0.5, let s = view.project(p), s.x.isFinite, s.y.isFinite else { return nil }
            return s
        }
        if model.depth == 0 {
            for s in society.settlements.values where !s.abandoned {
                let c = s.center.center
                if abs(c.x - scene.viewPos.x) > reach * 1.6 || abs(c.y - scene.viewPos.y) > reach * 1.6 { continue }
                let cap = society.isCapital(s)
                if scene.zoom < 0.8 && !cap && s.members.count < 30 { continue }
                guard let p = screen(place(c, world, lift: 4.2)) else { continue }
                let nation = society.realm.nation(s.nation ?? 0)
                let kind = Society.kindNames[society.cityKind(s)].map { GameModel.zh ? $0.1 : $0.0 } ?? ""
                let text = (cap ? "★ " : "") + society.cityName(s) + " · " + (nation?.name(zh: GameModel.zh) ?? "") + (cap ? L(" 首都", " capital") : (kind.isEmpty ? "" : " · " + kind)) + (s.siege != nil ? " ⚔" : "")
                out["t\(s.id)"] = (text, p, scene.nationColor(s.nation ?? 0, society), cap ? 15 : 12)
            }
            for l in host.legions {
                guard let p = screen(place(l.pos, world, lift: 3.4)) else { continue }
                let hidden = host.masses[l.id] ?? 0
                out["l\(l.id)"] = ("\(l.count) · \(l.state)" + (hidden > 0 ? "  +\(hidden)" : ""), p, UIColor(hex: l.color).lighter(), 12)
            }
            for (t, n) in host.badges {
                guard let p = screen(place(t.center, world, lift: 2.4)) else { continue }
                out["b\(t.x),\(t.y)"] = ("\(n)", p, .white, 11)
            }
        }
        host.show(out)
    }

    private func updatePreview(_ world: OpenWorld, _ scene: GameScene) {
        let cells = scene.previewCells
        while previews.count < cells.count { let e = ModelEntity(); root.addChild(e); previews.append(e) }
        for (i, e) in previews.enumerated() {
            guard i < cells.count else { e.isEnabled = false; continue }
            let c = cells[i]
            e.isEnabled = true
            e.model = model3D(key: c.ok ? "pre-ok" : "pre-bad") { Figure3D.plate(color: RGBA(hex: c.ok ? "#4dff80" : "#ff4d4d"), w: 0.9, d: 0.9, h: 0.12) }
            e.position = place(c.pos.center, world, lift: 0.05) + SIMD3<Float>(-0.45, 0, -0.45)
        }
    }

    // MARK: touches

    /// The agent drawn nearest to a point of the screen, if one is under the finger.
    func pickAgent(_ p: CGPoint) -> Int? {
        var best: (Int, CGFloat)?
        for (id, e) in agents {
            guard let s = view.project(e.position + SIMD3<Float>(0, 0.8, 0)) else { continue }
            let d = hypot(s.x - p.x, s.y - p.y)
            if d < 30 && d < (best?.1 ?? .infinity) { best = (id, d) }
        }
        return best?.0
    }

    /// The point of the world under a point of the screen.
    func pickGround(_ p: CGPoint) -> Vec2? {
        guard let model = model, model.world != nil, let ray = view.ray(through: p) else { return nil }
        let world = model.activeWorld
        // walls and solid things (trees, rocks, furniture) are hit on their sides and tops, so a tap on
        // them means them, not the ground behind
        let solid = Content.shared.solid
        let hit = Terrain3D.pickThing(origin: ray.origin, direction: ray.direction, ground: { [weak self] x, z in
            self?.groundY(world, TilePos(x, z).center) ?? 0
        }, standing: { x, z in
            let l = world.chunk(x >> 5, z >> 5).layers, t = (z & 31) * 32 + (x & 31)
            if solid[Int(l[1][t])] { return (1.5, .wall) }
            if l[2][t] != 0 && solid[Int(l[2][t])] { return (1.2, .object) }
            return (0, .ground)
        })
        lastHit = hit?.1
        return hit?.0
    }
    /// What the last tap in 3D landed on (for the info shown and for tests).
    private(set) var lastHit: Terrain3D.Hit?
    /// "first yaw 0.40 pitch 0.80": the camera, as read by the HUD for assistive technology and UI tests.
    private(set) var cameraState = ""

    /// First person: what the cross in the middle of the screen points at, within reach and not through
    /// anything solid (a wall or glass stops it: what is seen through it is not reached).
    func pickCentre(reach: Double = 4.5) -> Vec2? {
        let c = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        guard let p = pickGround(c), let me = model?.scene?.player else { return nil }
        return p.distance(to: me) <= reach * 16 ? p : nil
    }

    // MARK: effects

    private func cube(_ color: RGBA, size: Float) -> ModelEntity {
        let e = take()
        e.model = model3D(key: "cube\(color.hex)") { Figure3D.cube(color: color) }
        e.scale = [size, size, size]
        return e
    }

    /// Sparks flying out from a place in the world.
    func burst(at p: Vec2, lift: Float = 0.8, color: RGBA, count: Int = 9, speed: Float = 3, size: Float = 0.14) {
        guard let model = model, model.render3D, model.world != nil else { return }
        let o = place(p, model.activeWorld, lift: lift)
        if simd_distance(o, target) > distance * 3 + 20 { return }
        for i in 0..<count where particles.count < 220 {
            let a = Float(i) / Float(count) * 2 * .pi + Float.random(in: 0...0.6)
            let v = SIMD3<Float>(cos(a), Float.random(in: 0.6...1.6), sin(a)) * speed * Float.random(in: 0.5...1)
            let e = cube(color, size: size)
            e.position = o
            particles.append(Particle(entity: e, v: v, life: Float.random(in: 0.35...0.7), age: 0, gravity: 9, to: nil, onEnd: nil))
        }
    }

    /// Something that flies from one place to another, then bursts.
    func bolt(from a: Vec2, to b: Vec2, lift: Float = 1, fromLift: Float? = nil, color: RGBA, time: Float = 0.35, size: Float = 0.2, burst n: Int = 8) {
        guard let model = model, model.render3D, model.world != nil, particles.count < 220 else { return }
        let world = model.activeWorld
        let e = cube(color, size: size)
        e.position = place(a, world, lift: fromLift ?? lift)
        let to = place(b, world, lift: lift)
        particles.append(Particle(entity: e, v: .zero, life: time, age: 0, gravity: 0, to: to, onEnd: n > 0 ? { [weak self] in self?.burst(at: b, lift: lift, color: color, count: n) } : nil))
    }

    func flash(_ alpha: CGFloat, time: Double = 0.3) { host?.flash(alpha, time: time) }

    /// The traveller's blow: an arrow or a bolt that flies, or the sweep of a blade, and a mark on whoever was hit.
    func strike(from p: Vec2, dir: Vec2, weapon: String, target: Vec2, hits: [(Vec2, Bool)]) {
        switch weapon {
        case "bow": bolt(from: p, to: p + dir * 270, color: RGBA(hex: "#a87038"), time: 0.6, size: 0.12, burst: 0)
        case "staff": bolt(from: p, to: target, lift: 0.8, fromLift: 1.6, color: RGBA(hex: "#59d8ff"), time: 0.4, size: 0.25)
        default: burst(at: p + dir * 14, lift: 0.9, color: .white, count: 5, speed: 1.6, size: 0.1)
        }
        for h in hits { burst(at: h.0, lift: 1, color: RGBA(hex: h.1 ? "#ff4040" : "#ffd0a0"), count: h.1 ? 14 : 7) }
    }

    /// A power being used: something travels along its path in the colour of its school, and bursts where it lands.
    func cast(_ r: Society.CastResult, from p: Vec2) {
        guard let power = r.power, power.fx != "swarm" else { return }          // the swarm draws itself (SwarmView)
        let c = RGBA(hex: ["#ffd966", "#59d8ff", "#b48cff", "#fff2b0", "#ffffff"][min(4, max(0, power.school))])
        var last = r.path.first ?? p
        for q in r.path.dropFirst() { bolt(from: last, to: q, color: c, time: 0.25, size: 0.22, burst: 6); last = q }
        if r.path.count < 2 { bolt(from: p, to: r.impact, color: c, time: 0.3, size: 0.22, burst: 0) }
        burst(at: r.impact, lift: 0.8, color: c, count: min(28, 10 + Int(power.radius / 8)), speed: 2 + Float(power.radius) / 30, size: 0.18)
        for h in r.hits.prefix(8) { burst(at: h.pos, lift: 1, color: RGBA(hex: h.dead ? "#ff4040" : "#ffd0a0"), count: 6) }
        if power.tier >= 4 { flash(0.3) }
    }

    /// Things that happen in the world by themselves: lightning, fireworks, the turns of a battle.
    func worldFX(_ e: WorldFX) {
        switch e.kind {
        case "lightning":
            bolt(from: e.pos + Vec2(30, -20), to: e.pos, lift: 0.2, fromLift: 16, color: RGBA(hex: "#e6f0ff"), time: 0.08, size: 0.35, burst: 14)
            flash(0.4, time: 0.25)
        case "firework":
            let colors = ["#ff5fa2", "#ffd84a", "#59d8ff", "#ff9a3a", "#6fe07a", "#b48cff"]
            let c = RGBA(hex: colors[Int(abs(e.pos.x)) % colors.count])
            bolt(from: e.pos, to: e.pos, lift: 7, fromLift: 1, color: .white, time: 0.5, size: 0.12, burst: 0)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.burst(at: e.pos, lift: 7, color: c, count: 18, speed: 4, size: 0.16) }
        case "volley": bolt(from: e.pos, to: e.to, lift: 1, fromLift: 1.4, color: RGBA(hex: "#d8c8a0"), time: 0.7, size: 0.1, burst: 4)
        case "charge", "rout", "breach":
            let n = model?.society?.realm.nation(e.nation).map { RGBA(hex: $0.color) } ?? .white
            burst(at: e.pos, lift: 0.6, color: e.kind == "breach" ? RGBA(hex: "#9a9ca6") : n, count: e.kind == "breach" ? 18 : 10, speed: 2.5)
        default: break
        }
    }

    private func updateWeather(_ fall: Int, under: Bool, dt: Float) {
        guard !under, fall == 1 || fall == 2 else { return }
        rainAcc += dt * (fall == 1 ? 90 : 40)
        let c = fall == 1 ? RGBA(hex: "#a8c8f0") : RGBA.white
        while rainAcc >= 1 && particles.count < 200 {
            rainAcc -= 1
            let e = cube(c, size: 1)
            e.scale = fall == 1 ? SIMD3<Float>(0.03, 0.5, 0.03) : SIMD3<Float>(0.07, 0.07, 0.07)
            let r = distance * 0.9
            e.position = target + SIMD3<Float>(Float.random(in: -r...r), Float.random(in: 5...9), Float.random(in: -r...r))
            particles.append(Particle(entity: e, v: SIMD3<Float>(fall == 1 ? -1 : Float.random(in: -0.6...0.6), fall == 1 ? -14 : -2.5, 0), life: fall == 1 ? 0.6 : 2.6, age: -1, gravity: 0, to: nil, onEnd: nil))
        }
        if rainAcc > 4 { rainAcc = 0 }
    }

    private func stepParticles(_ dt: Float) {
        var i = 0
        while i < particles.count {
            var p = particles[i]
            let falling = p.age < 0                     // rain and snow keep their size
            if falling { p.life -= dt } else { p.age += dt }
            let done = falling ? p.life <= 0 : p.age >= p.life
            if done {
                give(p.entity)
                let end = p.onEnd
                particles.remove(at: i)
                end?()
                continue
            }
            if let to = p.to {
                let left = max(0.001, p.life - p.age)
                p.entity.position += (to - p.entity.position) * min(1, dt / left)
            } else {
                p.v.y -= p.gravity * dt
                p.entity.position += p.v * dt
                if !falling { let k = max(0.05, 1 - p.age / p.life); p.entity.scale *= SIMD3<Float>(repeating: 0.9 + 0.1 * k) }
            }
            particles[i] = p
            i += 1
        }
    }

    /// How the 3D camera sees a place of the world (for the swarm, which is drawn over this view).
    func frame(at p: Vec2) -> (center: CGPoint, pointsPerTile: CGFloat, right: SIMD3<Float>, up: SIMD3<Float>, forward: SIMD3<Float>)? {
        guard let model = model, model.world != nil else { return nil }
        let o = place(p, model.activeWorld)
        let eye = camera.position(relativeTo: nil)
        let f = simd_normalize(target + SIMD3<Float>(0, 0.6, 0) - eye)
        let r = SIMD3<Float>(cos(yaw), 0, -sin(yaw))
        let u = simd_cross(r, f)
        guard simd_dot(o - eye, f) > 0.5, let s0 = view.project(o), let s1 = view.project(o + r), s0.x.isFinite, s1.x.isFinite else { return nil }
        return (s0, hypot(s1.x - s0.x, s1.y - s0.y), r, u, f)
    }

    /// The chunks drawn now: a cleanup must not throw away what is on screen.
    var chunkKeys: Set<Int64> { Set(chunks.keys) }

    /// Memory is short: forget every cached figure mesh and spare entity (they are rebuilt when needed).
    func trim() { meshes.trim(to: 0); pool.removeAll() }

    var report: String {
        String(format: "3D: %d chunks (%d behind, oldest %.1f s; %d urgent sent, %d stale dropped), %d figures, %d particles, meshes %.1f MB (%d evicted)",
               chunks.count, staleShown, oldestStale, urgentSent, queue.stale, agents.count + soldiers.count, particles.count, Double(meshes.bytes) / 1048576, meshes.evictions)
    }
}

private extension Prop {
    var tileX: Int { Int((x / 16).rounded(.down)) }
    var tileY: Int { Int((y / 16).rounded(.down)) }
}

/// Holds the 3D picture and turns touches into the same actions the 2D scene takes: the stick walks
/// (in the direction the camera faces), a tap acts, a drag turns the camera, a pinch zooms, and in
/// building mode a drag lays out a line of tiles.
final class SolidInputView: UIView {
    let renderer: SolidRenderer
    weak var model: GameModel?
    var badges: [TilePos: Int] = [:]
    var masses: [Int: Int] = [:]
    var legions: [Society.LegionInfo] = []
    private var labels: [String: UILabel] = [:]
    private let veil = UIView()
    private let joyBase = CAShapeLayer(), joyKnob = CAShapeLayer()
    private var joyTouch: UITouch?
    private var joyOrigin = CGPoint.zero
    private var joyVec = CGVector.zero
    private var dragTouch: UITouch?
    private var others: [UITouch] = []
    private var starts: [ObjectIdentifier: CGPoint] = [:]
    private var lastPoint: [ObjectIdentifier: CGPoint] = [:]
    private var turned = false, pinching = false
    private var pinchDist: CGFloat = 1, pinchZoom: CGFloat = 2

    init(model: GameModel) {
        self.model = model
        renderer = SolidRenderer(model: model)
        super.init(frame: .zero)
        renderer.host = self
        model.solid = renderer
        isMultipleTouchEnabled = true
        backgroundColor = .black
        renderer.view.isUserInteractionEnabled = false
        renderer.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(renderer.view)
        veil.backgroundColor = .white; veil.alpha = 0; veil.isUserInteractionEnabled = false
        veil.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(veil)
        joyBase.fillColor = UIColor(white: 1, alpha: 0.10).cgColor; joyBase.strokeColor = UIColor(white: 1, alpha: 0.35).cgColor; joyBase.lineWidth = 1.5
        joyKnob.fillColor = UIColor(white: 1, alpha: 0.35).cgColor
        joyBase.path = UIBezierPath(ovalIn: CGRect(x: -46, y: -46, width: 92, height: 92)).cgPath
        joyKnob.path = UIBezierPath(ovalIn: CGRect(x: -20, y: -20, width: 40, height: 40)).cgPath
        layer.addSublayer(joyBase); layer.addSublayer(joyKnob)
        accessibilityIdentifier = "Solid3D"
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        renderer.view.frame = bounds
        veil.frame = bounds
        layoutJoystick()
    }

    private func layoutJoystick() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let base = joyTouch != nil ? joyOrigin : CGPoint(x: 110, y: bounds.height - 120)
        joyBase.position = base
        joyKnob.position = CGPoint(x: base.x + joyVec.dx * 32, y: base.y + joyVec.dy * 32)
        CATransaction.commit()
    }

    func flash(_ alpha: CGFloat, time: Double) {
        veil.layer.removeAllAnimations()
        veil.alpha = alpha
        UIView.animate(withDuration: time) { self.veil.alpha = 0 }
    }

    // MARK: labels
    func clearLabels() { for l in labels.values { l.removeFromSuperview() }; labels = [:] }

    func show(_ items: [String: (String, CGPoint, UIColor, CGFloat)]) {
        for (k, v) in items {
            let l = labels[k] ?? {
                let l = UILabel()
                l.font = .boldSystemFont(ofSize: v.3)
                l.textAlignment = .center
                l.layer.shadowColor = UIColor.black.cgColor; l.layer.shadowOpacity = 0.9; l.layer.shadowRadius = 1.5; l.layer.shadowOffset = .zero
                l.isUserInteractionEnabled = false
                insertSubview(l, belowSubview: veil)
                labels[k] = l
                return l
            }()
            if l.text != v.0 { l.text = v.0; l.sizeToFit() }
            l.textColor = v.2
            l.center = v.1
            l.isHidden = !bounds.insetBy(dx: -80, dy: -30).contains(v.1)
        }
        for (k, l) in labels where items[k] == nil { l.removeFromSuperview(); labels[k] = nil }
    }

    // MARK: touches
    private func inJoyZone(_ p: CGPoint) -> Bool {
        p.x < bounds.width * 0.36 && p.y > bounds.height * 0.34 && p.y < bounds.height - 70
    }

    private func steer() {
        // the stick is read on the screen; the traveller walks that way as the camera sees it
        let c = CGFloat(cos(renderer.yaw)), s = CGFloat(sin(renderer.yaw))
        model?.scene?.steer(CGVector(dx: c * joyVec.dx + s * joyVec.dy, dy: -s * joyVec.dx + c * joyVec.dy))
        layoutJoystick()
    }

    private func spread() -> CGFloat {
        guard others.count >= 2 else { return 0 }
        let a = others[0].location(in: self), b = others[1].location(in: self)
        return hypot(a.x - b.x, a.y - b.y)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let model = model, let scene = model.scene else { return }
        for t in touches {
            let p = t.location(in: self)
            if joyTouch == nil && others.isEmpty && inJoyZone(p) { joyTouch = t; joyOrigin = p; joyVec = .zero; steer() }
            else if Piece.byKey[model.buildMode] != nil, dragTouch == nil, others.isEmpty, let wp = renderer.pickGround(p) {
                dragTouch = t
                scene.dragStart = wp.tile
                model.planCells([wp.tile])
            } else {
                starts[ObjectIdentifier(t)] = p; lastPoint[ObjectIdentifier(t)] = p
                others.append(t)
                if others.count == 1 { turned = false }
                if others.count == 2 { pinching = true; pinchDist = max(1, spread()); pinchZoom = scene.zoom }
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let model = model, let scene = model.scene else { return }
        if pinching && others.count >= 2 {
            scene.zoom = min(5, max(scene.minZoom, pinchZoom * spread() / pinchDist))
        } else if let t = others.first, others.count == 1, touches.contains(t), let last = lastPoint[ObjectIdentifier(t)], let start = starts[ObjectIdentifier(t)] {
            let p = t.location(in: self)
            if turned || hypot(p.x - start.x, p.y - start.y) > 14 {
                turned = true
                let k = Float(model.lookSensitivity)
                renderer.yaw -= Float(p.x - last.x) * 0.008 * k
                let dy = Float(p.y - last.y) * 0.006 * k * (model.invertLook ? -1 : 1)
                if model.viewMode == .first {
                    // drag up to look up, down to look down; it stays where it is put
                    renderer.lookPitch = min(SolidRenderer.lookLimit, max(-SolidRenderer.lookLimit, renderer.lookPitch - dy))
                } else {
                    renderer.pitch = min(SolidRenderer.orbitRange.upperBound, max(SolidRenderer.orbitRange.lowerBound, renderer.pitch + dy))
                }
                if joyTouch != nil { steer() }
            }
            lastPoint[ObjectIdentifier(t)] = p
        }
        if let dt = dragTouch, touches.contains(dt), let a = scene.dragStart, let wp = renderer.pickGround(dt.location(in: self)) {
            model.planCells(GameScene.line(a, wp.tile))
        }
        guard let jt = joyTouch, touches.contains(jt) else { return }
        let p = jt.location(in: self)
        var d = CGVector(dx: (p.x - joyOrigin.x) / 40, dy: (p.y - joyOrigin.y) / 40)
        let l = hypot(d.dx, d.dy)
        if l > 1 { d = CGVector(dx: d.dx / l, dy: d.dy / l) }
        joyVec = d
        steer()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let model = model, let scene = model.scene else { return }
        for t in touches {
            if t === joyTouch { joyTouch = nil; joyVec = .zero; steer(); continue }
            if t === dragTouch { dragTouch = nil; scene.dragStart = nil; continue }
            let wasPinch = pinching, wasTurn = turned
            others.removeAll { $0 === t }
            lastPoint[ObjectIdentifier(t)] = nil
            if others.isEmpty { pinching = false }
            guard let start = starts.removeValue(forKey: ObjectIdentifier(t)), !wasPinch, !wasTurn else { continue }
            let p = t.location(in: self)
            if hypot(p.x - start.x, p.y - start.y) > 14 { continue }
            if let id = renderer.pickAgent(p), let a = model.society?.agents[id] { scene.tapWorld(a.pos, agent: id) }
            else if let wp = renderer.pickGround(p) { scene.tapWorld(wp, agent: nil) }
        }
    }

    /// Let go of everything held: the stick, a drag, a turn (a panel opened, the view changed).
    func releaseTouches() {
        if joyTouch != nil { joyTouch = nil; joyVec = .zero; steer() }
        if dragTouch != nil { dragTouch = nil; model?.scene?.dragStart = nil }
        others = []; starts = [:]; lastPoint = [:]; pinching = false; turned = false
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            if t === joyTouch { joyTouch = nil; joyVec = .zero; steer() }
            if t === dragTouch { dragTouch = nil; model?.scene?.dragStart = nil }
            starts[ObjectIdentifier(t)] = nil; lastPoint[ObjectIdentifier(t)] = nil
            others.removeAll { $0 === t }
        }
        if others.isEmpty { pinching = false }
    }
}
