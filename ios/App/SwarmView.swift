import SwiftUI
import UIKit
import MetalKit
import simd
import MoonPixelCore

// The nanite swarm on screen: a transparent Metal view over the game (2D or 3D) and under the HUD.
// Up to 1 048 576 points are moved by a compute shader and drawn as grains every frame (Swarm.metal).
// Where each point belongs in each shape comes from MoonPixelCore (Swarm.swift). The view holds no
// memory and does not draw while no swarm is out.
//
// It is an effect only: what the power does to the world is decided by the core when it is cast.

struct SwarmOverlay: UIViewRepresentable {
    @EnvironmentObject var model: GameModel
    func makeUIView(context: Context) -> SwarmView { SwarmView(model: model) }
    func updateUIView(_ v: SwarmView, context: Context) {}
    static func dismantleUIView(_ v: SwarmView, coordinator: ()) { v.stop() }
}

private struct SwarmUniforms {
    var right = SIMD4<Float>(1, 0, 0, 0), up = SIMD4<Float>(0, 1, 0, 0), fwd = SIMD4<Float>(0, 0, 1, 0)
    var center = SIMD4<Float>(0, 0, 0, 0), params = SIMD4<Float>(0, 0, 0, 0), travel = SIMD4<Float>(0, 0, 0, 0)
}

final class SwarmView: MTKView, MTKViewDelegate {
    weak var model: GameModel?
    private var queue: MTLCommandQueue?
    private var stepState: MTLComputePipelineState?
    private var drawState: MTLRenderPipelineState?
    private var depthState: MTLDepthStencilState?
    private var pos: MTLBuffer?, vel: MTLBuffer?
    private var shapes: [MTLBuffer] = []
    private(set) var count = 0
    private var started: CFTimeInterval = 0
    private var last: CFTimeInterval = 0
    private var anchor = Vec2.zero
    private var generation = 0
    private let work = DispatchQueue(label: "moonpixel.swarm", qos: .userInitiated)
    /// Frames drawn and the longest one of the last show (for the performance panel and the log).
    private(set) var frames = 0
    private(set) var worst = 0.0

    init(model: GameModel) {
        self.model = model
        super.init(frame: .zero, device: MTLCreateSystemDefaultDevice())
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        colorPixelFormat = .bgra8Unorm
        depthStencilPixelFormat = .depth32Float
        preferredFramesPerSecond = 60
        isPaused = true
        isHidden = true
        delegate = self
        model.swarm = self
        guard let dev = device, let lib = dev.makeDefaultLibrary(),
              let k = lib.makeFunction(name: "swarmStep"), let v = lib.makeFunction(name: "swarmVertex"), let f = lib.makeFunction(name: "swarmFragment") else { return }
        queue = dev.makeCommandQueue()
        stepState = try? dev.makeComputePipelineState(function: k)
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = v; d.fragmentFunction = f
        d.colorAttachments[0].pixelFormat = colorPixelFormat
        d.depthAttachmentPixelFormat = depthStencilPixelFormat
        drawState = try? dev.makeRenderPipelineState(descriptor: d)
        let ds = MTLDepthStencilDescriptor()
        ds.depthCompareFunction = .less; ds.isDepthWriteEnabled = true
        depthState = dev.makeDepthStencilState(descriptor: ds)
    }

    required init(coder: NSCoder) { fatalError("not used") }

    var ready: Bool { queue != nil && stepState != nil && drawState != nil && depthState != nil }
    var running: Bool { !isPaused }

    /// Let the swarm out: it rises as dust at the caster, pours to the place it was sent and goes
    /// through its shapes there. The buffers are filled off the main thread; nothing is drawn until then.
    func launch(caster: Vec2, impact: Vec2, look: Look) {
        guard ready, let dev = device, let model = model else { return }
        stop()
        generation += 1
        let gen = generation
        let n = model.swarmCount
        let bytes = n * MemoryLayout<SIMD4<Float>>.stride
        guard let p = dev.makeBuffer(length: bytes, options: .storageModeShared), let v = dev.makeBuffer(length: bytes, options: .storageModeShared) else { return }
        var made: [MTLBuffer] = []
        for _ in 0..<4 { guard let b = dev.makeBuffer(length: bytes, options: .storageModeShared) else { return }; made.append(b) }
        let off = SIMD4<Float>(Float((caster.x - impact.x) / 16), 0, Float((caster.y - impact.y) / 16), 0)
        let wolf = Species.all.first { $0.key == "wolf" } ?? Species.all[0]
        func points(_ b: MTLBuffer) -> UnsafeMutableBufferPointer<SIMD4<Float>> {
            UnsafeMutableBufferPointer(start: b.contents().bindMemory(to: SIMD4<Float>.self, capacity: n), count: n)
        }
        let pp = points(p), vv = points(v), s = made.map(points)
        work.async { [weak self] in
            SwarmShapes.dust(into: pp)
            for i in 0..<n { pp[i] += off; vv[i] = .zero }
            SwarmShapes.sphere(into: s[0])
            SwarmShapes.mesh(Figure3D.human(look, frame: 3, held: "sword", child: false, female: false), into: s[1], scale: 3)
            SwarmShapes.mesh(Figure3D.animal(wolf, frame: 0), into: s[2], scale: 4.5)
            SwarmShapes.helix(into: s[3])
            DispatchQueue.main.async {
                guard let self = self, self.generation == gen else { return }
                self.pos = p; self.vel = v; self.shapes = made; self.count = n
                self.anchor = impact
                self.started = CACurrentMediaTime(); self.last = self.started
                self.frames = 0; self.worst = 0
                self.isHidden = false
                self.isPaused = false
            }
        }
    }

    /// Put the swarm away and give its memory back.
    func stop() {
        generation += 1
        isPaused = true
        isHidden = true
        pos = nil; vel = nil; shapes = []; count = 0
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let model = model, let queue = queue, let step = stepState, let draw = drawState, let depth = depthState,
              let pos = pos, let vel = vel, shapes.count == 4, count > 0 else { return }
        let now = CACurrentMediaTime()
        let t = Float(now - started)
        if t > SwarmShapes.showLength || model.scene == nil {
            model.swarmReport = String(format: "swarm %d points: %d frames, longest %.1f ms", count, frames, worst * 1000)
            stop()
            return
        }
        // where the swarm's origin is on screen and how the camera is turned, from whichever view is showing
        guard let f = model.swarmFrame(at: anchor), bounds.width > 0, bounds.height > 0,
              let drawable = currentDrawable, let pass = currentRenderPassDescriptor, let cb = queue.makeCommandBuffer() else { return }
        let w = Float(bounds.width), h = Float(bounds.height)
        let px = Float(f.pointsPerTile)
        let stage = SwarmShapes.stage(at: t)
        let fade = max(0, min(1, (SwarmShapes.showLength - t) / 0.7))
        var u = SwarmUniforms()
        u.right = SIMD4(f.right, px / w * 2)
        u.up = SIMD4(f.up, px / h * 2)
        u.fwd = SIMD4(f.forward, max(1.5, px * Float(contentScaleFactor) * 0.032) * fade)
        u.center = SIMD4(Float(f.center.x) / w * 2 - 1, 1 - Float(f.center.y) / h * 2, t, Float(min(1.0 / 30, max(1.0 / 240, now - last))))
        u.params = SIMD4(t < 0.35 ? 0 : 1, stage.blend, t > SwarmShapes.scatterAt ? 1 : 0, Float(count))
        u.travel = SIMD4(min(1, max(0, (t - 0.35) / 1.3)), 0, 0, 0)
        worst = max(worst, frames > 2 ? now - last : 0)
        last = now
        frames += 1
        let a = shapes[stage.from], b = shapes[stage.to]

        if let c = cb.makeComputeCommandEncoder() {
            c.setComputePipelineState(step)
            c.setBuffer(pos, offset: 0, index: 0); c.setBuffer(vel, offset: 0, index: 1)
            c.setBuffer(a, offset: 0, index: 2); c.setBuffer(b, offset: 0, index: 3)
            c.setBytes(&u, length: MemoryLayout<SwarmUniforms>.stride, index: 4)
            let tw = step.threadExecutionWidth
            c.dispatchThreadgroups(MTLSize(width: (count + tw - 1) / tw, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: tw, height: 1, depth: 1))
            c.endEncoding()
        }
        if let r = cb.makeRenderCommandEncoder(descriptor: pass) {
            r.setRenderPipelineState(draw)
            r.setDepthStencilState(depth)
            r.setVertexBuffer(pos, offset: 0, index: 0); r.setVertexBuffer(vel, offset: 0, index: 1)
            r.setVertexBuffer(a, offset: 0, index: 2); r.setVertexBuffer(b, offset: 0, index: 3)
            r.setVertexBytes(&u, length: MemoryLayout<SwarmUniforms>.stride, index: 4)
            r.drawPrimitives(type: .point, vertexStart: 0, vertexCount: count)
            r.endEncoding()
        }
        cb.present(drawable)
        cb.commit()
    }
}

extension GameModel {
    /// How the view that is showing sees a place of the world: where it is on screen (points), how many
    /// points a tile is there, and the camera's axes in world space (x east, y up, z south).
    func swarmFrame(at p: Vec2) -> (center: CGPoint, pointsPerTile: CGFloat, right: SIMD3<Float>, up: SIMD3<Float>, forward: SIMD3<Float>)? {
        if render3D, let s = solid { return s.frame(at: p) }
        guard let sc = scene, let v = sc.view else { return nil }
        // 2D looks straight down with figures standing up the screen: height and north both go up
        let c = sc.convertPoint(toView: sc.pt(p))
        let scale = v.bounds.width / max(1, sc.size.width)
        return (c, 16 * sc.zoom * scale, SIMD3(1, 0, 0), SIMD3(0, 0.8, -0.6), SIMD3(0, -0.6, -0.8))
    }
}
