import AppKit
import SwiftUI
import Metal
import MetalKit
import MailroomCore

public enum ThemeMode: String, Sendable {
    case light
    case dark
}

public struct DeckPalette: Sendable {
    public let mode: ThemeMode
    public let canvas: Color
    public let paper: Color
    public let raised: Color
    public let sunken: Color
    public let hoverFill: Color
    public let focusFill: Color
    public let ink: Color
    public let ink2: Color
    public let ink3: Color
    public let line: Color
    public let lineStrong: Color
    public let amber: Color
    public let cobalt: Color
    public let sage: Color
    public let coral: Color
    public let ridgeSkyTop: Color
    public let ridgeSkyBottom: Color
    public let ridge1: Color
    public let ridge2: Color
    public let ridge3: Color

    public static let light = DeckPalette(
        mode: .light,
        canvas: Color(hex: 0xFAFBFD),
        paper: Color(hex: 0xFFFFFF),
        raised: Color(hex: 0xFFFFFF),
        sunken: Color(hex: 0xF5F7FA),
        hoverFill: Color(hex: 0x0F172A, alpha: 0.026),
        focusFill: Color(hex: 0xF3EEFF),
        ink: Color(hex: 0x0F1117),
        ink2: Color(hex: 0x484E5C),
        ink3: Color(hex: 0x878E9C),
        line: Color(hex: 0x0F1420, alpha: 0.042),
        lineStrong: Color(hex: 0x0F1420, alpha: 0.095),
        amber: Color(hex: 0xB86E14),
        cobalt: Color(hex: 0x3B63E6),
        sage: Color(hex: 0x25855A),
        coral: Color(hex: 0xD1434E),
        ridgeSkyTop: Color(hex: 0xF7F8FA),
        ridgeSkyBottom: Color(hex: 0xEEF1F6),
        ridge1: Color(hex: 0xDFE4EC),
        ridge2: Color(hex: 0xC9D2DF),
        ridge3: Color(hex: 0xAEBACC)
    )

    public static let dark = DeckPalette(
        mode: .dark,
        canvas: Color(hex: 0x101114),
        paper: Color(hex: 0x16171B),
        raised: Color(hex: 0x191A20),
        sunken: Color(hex: 0x1E1F26),
        hoverFill: Color.white.opacity(0.028),
        focusFill: Color(hex: 0x231E38),
        ink: Color(hex: 0xECEDEF),
        ink2: Color(hex: 0xA5A9B3),
        ink3: Color(hex: 0x686C77),
        line: Color.white.opacity(0.042),
        lineStrong: Color.white.opacity(0.11),
        amber: Color(hex: 0xF1A638),
        cobalt: Color(hex: 0x6B9AFF),
        sage: Color(hex: 0x4CC38A),
        coral: Color(hex: 0xF26B75),
        ridgeSkyTop: Color(hex: 0x161821),
        ridgeSkyBottom: Color(hex: 0x1F2433),
        ridge1: Color(hex: 0x252B3D),
        ridge2: Color(hex: 0x1D2230),
        ridge3: Color(hex: 0x141720)
    )

    public func accountDotColor(_ accountId: String) -> Color {
        if accountId == "work" { return cobalt }
        if accountId == "personal" { return sage }
        return pickTone(seed: accountId)
    }

    public func kindDotColor(_ kind: DecisionKind) -> Color {
        switch kind {
        case .human: return cobalt
        case .contract, .policy, .uncertain: return amber
        case .billing: return coral
        case .rescued: return sage
        }
    }

    public func pickTone(seed: String) -> Color {
        let tones = [cobalt, sage, amber, coral]
        var h: Int32 = 0
        for scalar in seed.unicodeScalars {
            h = h &* 31 &+ Int32(bitPattern: UInt32(scalar.value & 0xFFFF))
        }
        let idx = Int(abs(Int64(h))) % tones.count
        return tones[idx]
    }
}

private struct DeckPaletteKey: EnvironmentKey {
    static let defaultValue: DeckPalette = .light
}

public extension EnvironmentValues {
    var palette: DeckPalette {
        get { self[DeckPaletteKey.self] }
        set { self[DeckPaletteKey.self] = newValue }
    }
}

public extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

/// 键盘按键徽标：单个大写字母用无衬线避免 O/0 混淆，其余用等宽数字体。
struct KbdView: View {
    @Environment(\.palette) private var p
    let text: String

    private var isSingleUpperLetter: Bool {
        text.count == 1 && text.range(of: #"^[A-Z]$"#, options: .regularExpression) != nil
    }

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium, design: isSingleUpperLetter ? .default : .monospaced))
            .monospacedDigit()
            .foregroundStyle(p.ink3)
            .padding(.horizontal, 4.5)
            .frame(minWidth: 18, minHeight: 18)
            .background(p.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 4.5, style: .continuous))
    }
}

/// 虚线圆角描边，用于低确信度（< 90%）胶囊标签
struct DashedBadgeBorder: View {
    let color: Color
    var cornerRadius: CGFloat = 4.5

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            .foregroundStyle(color)
    }
}

private struct FluidSilkPalette: Sendable {
    let core: Color
    let deep: Color
    let mist: Color
    let rim: Color
    let warm: Color
    let warmPeak: Color

    static let lightAir = FluidSilkPalette(
        core: Color(hex: 0xEFE8FE),
        deep: Color(hex: 0xE7DDFD),
        mist: Color(hex: 0xF8F5FF),
        rim: Color(hex: 0xF9ECF6),
        warm: Color(hex: 0xFDE6D1),
        warmPeak: Color(hex: 0xFCD6B4)
    )

    static let darkVelvet = FluidSilkPalette(
        core: Color(hex: 0x2F264B),
        deep: Color(hex: 0x221E37),
        mist: Color(hex: 0x27233D),
        rim: Color(hex: 0x3E2D50),
        warm: Color(hex: 0x5A3732),
        warmPeak: Color(hex: 0x5A3732)
    )

    static let fullSilk = FluidSilkPalette(
        core: Color(hex: 0xB588FC),
        deep: Color(hex: 0x9E6FF6),
        mist: Color(hex: 0xDCC3FD),
        rim: Color(hex: 0xECC7E2),
        warm: Color(hex: 0xF6B06F),
        warmPeak: Color(hex: 0xF6B06F)
    )
}

/// 紫杏晨光流体丝绸着色层（24fps 呼吸感渐变，对应 v7 原型 WebGL 着色器）
private struct FluidSilkCanvas: View {
    let palette: FluidSilkPalette

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            Canvas(rendersAsynchronously: true) { context, size in
                guard size.width > 0, size.height > 0 else { return }

                let t = timeline.date.timeIntervalSinceReferenceDate * 0.28
                let unitRect = CGRect(x: 0, y: 0, width: 1, height: 1)
                let unitPath = Path(unitRect)

                context.scaleBy(x: size.width, y: size.height)

                // 1. Base silk drape (cDeep <-> cCore)
                let baseStart = CGPoint(x: 0.08 + sin(t * 0.35) * 0.06, y: 0.92)
                let baseEnd = CGPoint(x: 0.92 - cos(t * 0.30) * 0.06, y: 0.08)
                context.fill(
                    unitPath,
                    with: .linearGradient(
                        Gradient(colors: [palette.deep, palette.core, palette.deep.opacity(0.92)]),
                        startPoint: baseStart,
                        endPoint: baseEnd
                    )
                )

                // 2. Flowing mid-canvas silk fold
                let silkCenter = CGPoint(x: 0.54 + sin(t * 0.48) * 0.07, y: 0.46 + cos(t * 0.42) * 0.06)
                context.fill(
                    unitPath,
                    with: .radialGradient(
                        Gradient(stops: [
                            .init(color: palette.core.opacity(0.85), location: 0.0),
                            .init(color: palette.core.opacity(0.35), location: 0.48),
                            .init(color: palette.core.opacity(0.0), location: 1.0)
                        ]),
                        center: silkCenter,
                        startRadius: 0.0,
                        endRadius: 0.72
                    )
                )

                // 3. Left & upper-left mist so left-aligned text stays ultra-crisp
                let mistEndX = 0.68 + sin(t * 0.32) * 0.03
                context.fill(
                    unitPath,
                    with: .linearGradient(
                        Gradient(stops: [
                            .init(color: palette.mist.opacity(0.82), location: 0.0),
                            .init(color: palette.mist.opacity(0.45), location: 0.42),
                            .init(color: palette.mist.opacity(0.0), location: 1.0)
                        ]),
                        startPoint: CGPoint(x: 0.0, y: 0.20),
                        endPoint: CGPoint(x: mistEndX, y: 0.78)
                    )
                )

                // 4. Top-right rose / violet rim
                let rimCenter = CGPoint(x: 0.88 + cos(t * 0.45) * 0.03, y: 0.14 + sin(t * 0.40) * 0.03)
                context.fill(
                    unitPath,
                    with: .radialGradient(
                        Gradient(stops: [
                            .init(color: palette.rim.opacity(0.62), location: 0.0),
                            .init(color: palette.rim.opacity(0.24), location: 0.46),
                            .init(color: palette.rim.opacity(0.0), location: 1.0)
                        ]),
                        center: rimCenter,
                        startRadius: 0.0,
                        endRadius: 0.56
                    )
                )

                // 5. Bottom-right breathing warm apricot-cream / amber bloom
                let warmCenter = CGPoint(
                    x: 0.84 + sin(t * 0.70) * 0.04,
                    y: 0.86 - cos(t * 0.60) * 0.04
                )
                context.fill(
                    unitPath,
                    with: .radialGradient(
                        Gradient(stops: [
                            .init(color: palette.warmPeak.opacity(0.92), location: 0.0),
                            .init(color: palette.warm.opacity(0.72), location: 0.34),
                            .init(color: palette.warm.opacity(0.22), location: 0.66),
                            .init(color: palette.warm.opacity(0.0), location: 1.0)
                        ]),
                        center: warmCenter,
                        startRadius: 0.0,
                        endRadius: 0.54
                    )
                )
            }
        }
    }
}

private struct FluidSilkUniforms {
    var time: Float
    var surfaceMode: Int32
}

/// 紫杏晨光 GPU Metal 着色管线单例（运行时编译 MSL 源码，无需 .metallib 资源）
@MainActor
private final class FluidSilkMetalPipeline {
    static let shared = FluidSilkMetalPipeline()

    let device: MTLDevice?
    let commandQueue: MTLCommandQueue?
    let pipelineState: MTLRenderPipelineState?
    let vertexBuffer: MTLBuffer?
    let startTime: CFTimeInterval

    var isAvailable: Bool {
        device != nil && commandQueue != nil && pipelineState != nil && vertexBuffer != nil
    }

    private init() {
        self.startTime = CACurrentMediaTime()

        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: Self.mslSource, options: nil),
              let vertexFunction = library.makeFunction(name: "fluidSilkVertex"),
              let fragmentFunction = library.makeFunction(name: "fluidSilkFragment")
        else {
            self.device = nil
            self.commandQueue = nil
            self.pipelineState = nil
            self.vertexBuffer = nil
            return
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        guard let pipelineState = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            self.device = nil
            self.commandQueue = nil
            self.pipelineState = nil
            self.vertexBuffer = nil
            return
        }

        let vertices: [SIMD2<Float>] = [
            SIMD2<Float>(-1, -1),
            SIMD2<Float>( 1, -1),
            SIMD2<Float>(-1,  1),
            SIMD2<Float>( 1,  1)
        ]
        guard let vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: MemoryLayout<SIMD2<Float>>.stride * vertices.count,
            options: .storageModeShared
        ) else {
            self.device = nil
            self.commandQueue = nil
            self.pipelineState = nil
            self.vertexBuffer = nil
            return
        }

        self.device = device
        self.commandQueue = commandQueue
        self.pipelineState = pipelineState
        self.vertexBuffer = vertexBuffer
    }

    private static let mslSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float2 v_uv;
    };

    struct FluidSilkUniforms {
        float u_time;
        int u_surfaceMode;
    };

    static float hash(float2 p) {
        float3 p3 = fract(float3(p.xyx) * 0.1031);
        p3 += dot(p3, p3.yzx + 33.33);
        return fract((p3.x + p3.y) * p3.z);
    }

    static float noise(float2 p) {
        float2 i = floor(p);
        float2 f = fract(p);
        float2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
        return mix(
            mix(hash(i + float2(0.0, 0.0)), hash(i + float2(1.0, 0.0)), u.x),
            mix(hash(i + float2(0.0, 1.0)), hash(i + float2(1.0, 1.0)), u.x),
            u.y
        );
    }

    static float silkWave(float2 p) {
        float v = 0.65 * noise(p);
        float2x2 rot = float2x2(0.84, 0.54, -0.54, 0.84);
        v += 0.35 * noise(rot * p * 1.65 + float2(2.3, 4.1));
        return v;
    }

    vertex VertexOut fluidSilkVertex(
        uint vid [[vertex_id]],
        constant float2 *positions [[buffer(0)]]
    ) {
        VertexOut out;
        float2 a_pos = positions[vid];
        out.position = float4(a_pos, 0.0, 1.0);
        out.v_uv = a_pos * 0.5 + 0.5;
        return out;
    }

    fragment float4 fluidSilkFragment(
        VertexOut in [[stage_in]],
        constant FluidSilkUniforms &u [[buffer(0)]]
    ) {
        float2 uv = in.v_uv;
        float t = u.u_time * 0.28;

        float w1 = silkWave(uv * float2(1.15, 0.95) + float2(t * 0.25, -t * 0.18));
        float w2 = silkWave(uv * float2(1.35, 1.10) + float2(w1 * 0.55 - t * 0.15, w1 * 0.45 + t * 0.20));

        // 1.0 - smoothstep(low, high, x) matches WebGL smoothstep(high, low, x) without MSL undefined edge0 >= edge1
        float leftMist = 1.0 - smoothstep(0.02, 0.68, uv.x * 0.82 + uv.y * 0.28 - (w2 - 0.5) * 0.38);
        float centerSilk = smoothstep(0.18, 0.85, w2 + (uv.x - uv.y) * 0.18);

        float2 warmCenter = float2(0.84 + sin(t * 0.7) * 0.04, 0.14 + cos(t * 0.6) * 0.04);
        float2 dWarm = (uv - warmCenter) * float2(1.15, 1.35);
        float warmDist = length(dWarm) - (w1 - 0.5) * 0.28;
        float warmBloom = 1.0 - smoothstep(0.04, 0.68, warmDist);

        float topRightRim = smoothstep(0.42, 0.98, uv.x * 0.62 + uv.y * 0.52 + (w1 - 0.5) * 0.22) * (1.0 - warmBloom * 0.6);

        float3 cCore, cDeep, cMist, cWarm, cRim;

        if (u.u_surfaceMode == 0) {
            cCore = float3(0.710, 0.533, 0.988);
            cDeep = float3(0.620, 0.435, 0.965);
            cMist = float3(0.865, 0.765, 0.992);
            cWarm = float3(0.965, 0.690, 0.435);
            cRim  = float3(0.925, 0.780, 0.885);
        } else if (u.u_surfaceMode == 1) {
            cCore = float3(0.938, 0.910, 0.996);
            cDeep = float3(0.905, 0.865, 0.992);
            cMist = float3(0.972, 0.960, 0.998);
            cWarm = float3(0.994, 0.902, 0.820);
            cRim  = float3(0.975, 0.925, 0.965);
        } else {
            cCore = float3(0.185, 0.148, 0.295);
            cDeep = float3(0.135, 0.118, 0.215);
            cMist = float3(0.155, 0.138, 0.240);
            cWarm = float3(0.355, 0.215, 0.195);
            cRim  = float3(0.245, 0.175, 0.315);
        }

        float3 col = mix(cDeep, cCore, centerSilk);
        col = mix(col, cMist, leftMist * 0.75);
        col = mix(col, cRim, topRightRim * 0.55);
        col = mix(col, cWarm, pow(max(warmBloom, 0.0), 1.35) * 0.92);

        float grainStrength = (u.u_surfaceMode == 1) ? 0.012 : 0.022;
        float grain = (hash(in.position.xy + fract(t) * 100.0) - 0.5) * grainStrength;
        col = clamp(col + grain, 0.0, 1.0);

        return float4(col, 1.0);
    }
    """
}

/// 穿透点击与悬停事件的 MTKView，避免拦截 MailListRowView 的 .onTapGesture / .onHover
private final class PassthroughMTKView: MTKView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private struct FluidSilkMetalView: NSViewRepresentable {
    let surfaceMode: Int32

    @MainActor
    final class Coordinator: NSObject, MTKViewDelegate {
        var surfaceMode: Int32

        init(surfaceMode: Int32) {
            self.surfaceMode = surfaceMode
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard view.drawableSize.width > 0, view.drawableSize.height > 0 else { return }
            let pipeline = FluidSilkMetalPipeline.shared
            guard let commandQueue = pipeline.commandQueue,
                  let pipelineState = pipeline.pipelineState,
                  let vertexBuffer = pipeline.vertexBuffer,
                  let drawable = view.currentDrawable,
                  let renderPassDescriptor = view.currentRenderPassDescriptor,
                  let commandBuffer = commandQueue.makeCommandBuffer(),
                  let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
            else {
                return
            }

            var uniforms = FluidSilkUniforms(
                time: Float(CACurrentMediaTime() - pipeline.startTime),
                surfaceMode: surfaceMode
            )

            encoder.setRenderPipelineState(pipelineState)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<FluidSilkUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding()

            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(surfaceMode: surfaceMode)
    }

    func makeNSView(context: Context) -> PassthroughMTKView {
        let view = PassthroughMTKView(frame: .zero, device: FluidSilkMetalPipeline.shared.device)
        view.delegate = context.coordinator
        view.preferredFramesPerSecond = 24
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.clearColor = MTLClearColorMake(0, 0, 0, 1)
        view.wantsLayer = true
        view.layer?.isOpaque = true
        return view
    }

    func updateNSView(_ nsView: PassthroughMTKView, context: Context) {
        context.coordinator.surfaceMode = surfaceMode
    }

    static func dismantleNSView(_ nsView: PassthroughMTKView, coordinator: Coordinator) {
        nsView.isPaused = true
        nsView.delegate = nil
    }
}

/// 选中行背景：Mode A · 无框原生空气晕染（紫杏晨光，无描边）
struct FluidSilkRowBackground: View {
    @Environment(\.palette) private var p

    var body: some View {
        Group {
            if FluidSilkMetalPipeline.shared.isAvailable {
                FluidSilkMetalView(surfaceMode: p.mode == .dark ? 2 : 1)
            } else {
                FluidSilkCanvas(palette: p.mode == .dark ? .darkVelvet : .lightAir)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .shadow(
            color: p.mode == .dark ? Color.black.opacity(0.45) : Color(hex: 0x6E52D2, alpha: 0.10),
            radius: p.mode == .dark ? 11 : 8,
            x: 0,
            y: p.mode == .dark ? 4 : 2
        )
    }
}

/// 侧栏品牌标识：22×22 满色度紫杏晨光流体丝绸徽标
struct FluidSilkLogoIcon: View {
    var body: some View {
        Group {
            if FluidSilkMetalPipeline.shared.isAvailable {
                FluidSilkMetalView(surfaceMode: 0)
            } else {
                FluidSilkCanvas(palette: .fullSilk)
            }
        }
        .frame(width: 22, height: 22)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// MARK: - Native macOS Liquid Glass (Z-Axis Floating Chrome Only)

/// 悬浮液态玻璃聚合容器：在 macOS 26+ 使用 GlassEffectContainer 实现相邻胶囊的光学折射与水滴聚拢。
struct DeckGlassCluster<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }
}

private struct DeckGlassCapsuleModifier: ViewModifier {
    @Environment(\.palette) private var p
    let interactive: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(interactive ? .regular.interactive() : .regular, in: .capsule)
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .background(p.raised.opacity(0.86), in: Capsule())
                .overlay(Capsule().strokeBorder(p.lineStrong, lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 14, y: 5)
        }
    }
}

private struct DeckGlassRectModifier: ViewModifier {
    @Environment(\.palette) private var p
    let cornerRadius: CGFloat
    let interactive: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(
                    interactive ? .regular.interactive() : .regular,
                    in: .rect(cornerRadius: cornerRadius)
                )
        } else {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            content
                .background(.ultraThinMaterial, in: shape)
                .background(p.raised.opacity(0.92), in: shape)
                .overlay(shape.strokeBorder(p.lineStrong, lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 22, y: 10)
        }
    }
}

extension View {
    /// 为悬浮在 Z 轴上的胶囊控件（HUD、撤销气泡、顶栏悬浮操作组）赋予原生 Liquid Glass 光学折射与高光交互。
    func deckGlassCapsule(interactive: Bool = false) -> some View {
        modifier(DeckGlassCapsuleModifier(interactive: interactive))
    }

    /// 为悬浮模态层（如 ⌘K 命令面板）赋予圆角矩形原生 Liquid Glass 折射表面。
    func deckGlassRect(cornerRadius: CGFloat = 16, interactive: Bool = false) -> some View {
        modifier(DeckGlassRectModifier(cornerRadius: cornerRadius, interactive: interactive))
    }

    /// 在 DeckGlassCluster 内标识液态玻璃个体，以支持出现/收起时的形态融合过渡。
    @ViewBuilder
    func deckGlassID<ID: Hashable & Sendable>(_ id: ID, in namespace: Namespace.ID) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffectID(id, in: namespace)
        } else {
            self
        }
    }
}

// MARK: - Window Behind-Window Sidebar Vibrancy

private final class BehindWindowVisualEffectView: NSVisualEffectView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
    }
}

/// 窗口级桌面透光底板：让左侧 206pt 侧边栏微微透出桌面壁纸冷暖环境光，与右侧 100% 实心纸张工作台形成“左虚右实”层次。
struct WindowSidebarBackdrop: NSViewRepresentable {
    let mode: ThemeMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = BehindWindowVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .sidebar
        view.state = .followsWindowActiveState
        view.isEmphasized = false
        view.appearance = NSAppearance(named: mode == .dark ? .darkAqua : .aqua)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.appearance = NSAppearance(named: mode == .dark ? .darkAqua : .aqua)
    }
}
