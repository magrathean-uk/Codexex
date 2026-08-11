import CoreMotion
import SwiftUI
import CodexMeterCore

@MainActor
final class CodexiOSMatrixMotion {
    private let manager = CMMotionManager()

    func start() {
        guard manager.isDeviceMotionAvailable, manager.isDeviceMotionActive == false else { return }

        manager.deviceMotionUpdateInterval = matrixMotionSamplingInterval
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical)
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }

    func currentTilt() -> (horizontal: Double, vertical: Double) {
        guard let gravity = manager.deviceMotion?.gravity else { return (0, 0) }
        return (
            matrixHorizontalTilt(for: gravity.x),
            clamp((gravity.y + 0.35) * 1.35, lower: -1, upper: 1)
        )
    }
}

struct CodexiOSMatrixQuotaView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var model: CodexiOSModel
    let onOpenSettings: () -> Void
    @State private var motion = CodexiOSMatrixMotion()
    @AppStorage(CodexiOSSettingsKeys.showUsedQuota) private var showUsedQuota = false
    @State private var speedMultiplier = matrixDefaultSpeedMultiplier
    @State private var dragStartSpeed = matrixDefaultSpeedMultiplier
    @State private var density = matrixDefaultDensity
    @State private var dragStartDensity = matrixDefaultDensity

    private var weeklyWindow: CodexQuotaWindow? {
        guard let snapshot = model.snapshot else { return nil }
        guard let limit = CodexQuotaPresentationRules.orderedLimits(snapshot.limits).first(where: { $0.bucket == .codex }) else {
            return nil
        }
        return CodexiOSQuotaPresentation.weeklyWindow(for: limit)
    }

    private var weeklyPercent: Double? {
        weeklyWindow.map { CodexiOSQuotaDisplay.percent(for: $0, showUsedQuota: showUsedQuota) }
    }

    private var percentText: String {
        guard let weeklyPercent else { return "--" }
        return "\(Int(weeklyPercent.rounded()))"
    }

    private var isAnimationActive: Bool {
        reduceMotion == false && scenePhase == .active
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                TimelineView(
                    .animation(
                        minimumInterval: matrixRenderInterval,
                        paused: isAnimationActive == false
                    )
                ) { timeline in
                    Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: true) { context, size in
                        let tilt = isAnimationActive ? motion.currentTilt() : (0.0, 0.0)
                        drawMatrix(
                            context: &context,
                            size: size,
                            date: timeline.date,
                            fillPercent: weeklyPercent,
                            horizontalTilt: tilt.0,
                            verticalTilt: tilt.1,
                            speedMultiplier: speedMultiplier,
                            density: density,
                            reduceMotion: reduceMotion
                        )
                    }
                    .accessibilityHidden(true)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { value in
                                if abs(value.translation.width) > abs(value.translation.height) {
                                    density = matrixDensity(
                                        from: dragStartDensity,
                                        horizontalTranslation: value.translation.width
                                    )
                                } else {
                                    speedMultiplier = matrixSpeedMultiplier(
                                        from: dragStartSpeed,
                                        verticalTranslation: value.translation.height
                                    )
                                }
                            }
                            .onEnded { _ in
                                dragStartSpeed = speedMultiplier
                                dragStartDensity = density
                            }
                    )
                }

                VStack(spacing: 0) {
                    HStack {
                        Button {
                            onOpenSettings()
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 17, weight: .medium))
                                .frame(width: 44, height: 44)
                                .background(.black.opacity(0.48), in: Circle())
                                .overlay {
                                    Circle().stroke(Color.green.opacity(0.55), lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Matrix theme settings")

                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 52)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(percentText)
                            .font(.system(size: min(proxy.size.width * 0.24, 142), weight: .thin, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Color(red: 0.64, green: 1, blue: 0.68))
                            .shadow(color: .green.opacity(0.85), radius: 18)
                            .shadow(color: .green.opacity(0.58), radius: 42)
                        Text("%")
                            .font(.system(size: min(proxy.size.width * 0.15, 88), weight: .thin, design: .rounded))
                            .foregroundStyle(Color(red: 0.64, green: 1, blue: 0.68))
                            .shadow(color: .green.opacity(0.85), radius: 18)
                    }
                    .background {
                        Capsule(style: .continuous)
                            .fill(.ultraThinMaterial.opacity(0.15))
                            .overlay {
                                Capsule(style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                            }
                            .padding(.horizontal, -18)
                            .padding(.vertical, -10)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        weeklyWindow.map {
                            CodexiOSQuotaDisplay.accessibilityValue(for: $0, showUsedQuota: showUsedQuota)
                        } ?? "Weekly quota unavailable"
                    )
                    .padding(.top, 50)

                    Spacer()
                }
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .task(id: isAnimationActive) {
            if isAnimationActive {
                motion.start()
            } else {
                motion.stop()
            }
        }
        .onDisappear {
            motion.stop()
        }
    }
}

private func drawMatrix(
    context: inout GraphicsContext,
    size: CGSize,
    date: Date,
    fillPercent: Double?,
    horizontalTilt: Double,
    verticalTilt: Double,
    speedMultiplier: Double,
    density: Double,
    reduceMotion: Bool
) {
    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))

    guard let fillPercent else { return }

    let time = reduceMotion ? 0 : date.timeIntervalSinceReferenceDate
    let clampedFillPercent = clamp(fillPercent, lower: 0, upper: 100)
    let baseSurface = size.height * (1 - clampedFillPercent / 100)
    let fontSize = max(13, min(17, size.width / 26))
    let lineHeight = fontSize * 1.4
    let maximumColumnCount = max(1, Int(size.width / (fontSize * 1.2)))
    let columnCount = matrixColumnCount(maximum: maximumColumnCount, density: density)
    let columnWidth = columnCount > 0 ? size.width / CGFloat(columnCount) : 0
    let rowCount = Int(ceil(size.height / lineHeight)) + 2
    let wave = matrixWaterLine(
        size: size,
        baseSurface: baseSurface,
        time: time,
        horizontalTilt: horizontalTilt,
        verticalTilt: verticalTilt,
        reduceMotion: reduceMotion
    )
    let waterClip = matrixWaterFill(
        size: size,
        baseSurface: baseSurface,
        time: time,
        horizontalTilt: horizontalTilt,
        verticalTilt: verticalTilt,
        reduceMotion: reduceMotion
    )

    var glyphContext = context
    glyphContext.clip(to: waterClip)

    for column in 0..<columnCount {
        let x = (CGFloat(column) + 0.5) * columnWidth
        let trackLength = 8 + Int(seeded(Double(column) * 1.7) * 8)
        let trackGap = matrixTrackGapRows(trackLength: trackLength, density: density)
        let patternLength = trackLength + trackGap
        let rowsTravelled = time / matrixGIFDropInterval * speedMultiplier
            + seeded(Double(column) * 0.7) * Double(patternLength)
        let completedRows = Int(rowsTravelled.rounded(.down))
        let rowOffset = CGFloat(rowsTravelled - floor(rowsTravelled)) * lineHeight

        for row in -1...rowCount {
            let patternRow = positiveModulo(row - completedRows, by: patternLength)
            guard patternRow >= trackGap else { continue }

            let trackRow = patternRow - trackGap
            let y = CGFloat(row) * lineHeight + rowOffset
            let distance = Double(trackRow) / Double(max(1, trackLength - 1))
            let isLead = trackRow == trackLength - 1
            let isGlow = trackRow >= trackLength - 3
            let opacity = min(0.98, max(0.10, (0.28 + distance * 0.70) * (isGlow ? 1 : 0.78)))
            let glyphIndex = positiveModulo(column * 31 + (row - completedRows) * 17, by: matrixGlyphs.count)

            glyphContext.draw(
                Text(matrixGlyphs[glyphIndex])
                    .font(matrixGlyphFont(size: fontSize))
                    .foregroundStyle(
                        isLead
                            ? Color(red: 0.9, green: 1, blue: 0.92).opacity(opacity)
                            : Color(red: 0.03, green: 0.94, blue: 0.16).opacity(opacity)
                    ),
                at: CGPoint(x: x, y: y),
                anchor: .topLeading
            )
        }
    }

    context.stroke(
        wave,
        with: .color(Color.green.opacity(0.24)),
        style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
    )
    context.stroke(
        wave,
        with: .color(Color.green.opacity(0.78)),
        style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
    )
    context.stroke(
        wave,
        with: .color(Color(red: 0.8, green: 1, blue: 0.8).opacity(0.74)),
        style: StrokeStyle(lineWidth: 0.7, lineCap: .round, lineJoin: .round)
    )
}

private func seeded(_ value: Double) -> Double {
    let raw = sin(value * 12.9898 + 78.233) * 43758.5453
    return raw - floor(raw)
}

private func matrixWaterLine(
    size: CGSize,
    baseSurface: CGFloat,
    time: TimeInterval,
    horizontalTilt: Double,
    verticalTilt: Double,
    reduceMotion: Bool
) -> Path {
    var wave = Path()
    let samples = 36
    for sample in 0...samples {
        let xRatio = CGFloat(sample) / CGFloat(samples)
        let x = xRatio * size.width
        let y = matrixSurfaceY(
            xRatio: xRatio,
            size: size,
            baseSurface: baseSurface,
            time: time,
            horizontalTilt: horizontalTilt,
            verticalTilt: verticalTilt,
            reduceMotion: reduceMotion
        )
        if sample == 0 {
            wave.move(to: CGPoint(x: x, y: y))
        } else {
            wave.addLine(to: CGPoint(x: x, y: y))
        }
    }
    return wave
}

private func matrixWaterFill(
    size: CGSize,
    baseSurface: CGFloat,
    time: TimeInterval,
    horizontalTilt: Double,
    verticalTilt: Double,
    reduceMotion: Bool
) -> Path {
    var fill = matrixWaterLine(
        size: size,
        baseSurface: baseSurface,
        time: time,
        horizontalTilt: horizontalTilt,
        verticalTilt: verticalTilt,
        reduceMotion: reduceMotion
    )
    fill.addLine(to: CGPoint(x: size.width, y: size.height))
    fill.addLine(to: CGPoint(x: 0, y: size.height))
    fill.closeSubpath()
    return fill
}

private func matrixSurfaceY(
    xRatio: CGFloat,
    size: CGSize,
    baseSurface: CGFloat,
    time: TimeInterval,
    horizontalTilt: Double,
    verticalTilt: Double,
    reduceMotion: Bool
) -> CGFloat {
    baseSurface
        + (reduceMotion ? 0 : sin(time * 1.35 + Double(xRatio) * 8) * matrixWaveAmplitude)
        + horizontalTilt * (xRatio - 0.5) * size.width * 0.115
        + verticalTilt * 8
}

private func matrixGlyphFont(size: CGFloat) -> Font {
    .system(size: size, weight: .medium, design: .monospaced)
}

func matrixSpeedMultiplier(from start: Double, verticalTranslation: CGFloat) -> Double {
    clamp(start - Double(verticalTranslation / 240) * 0.5, lower: 0.5, upper: 1)
}

func matrixDensity(from start: Double, horizontalTranslation: CGFloat) -> Double {
    clamp(start + Double(horizontalTranslation / 260), lower: 0, upper: 1)
}

func matrixHorizontalTilt(for gravityX: Double) -> Double {
    clamp(-gravityX * 1.55, lower: -1, upper: 1)
}

func matrixColumnCount(maximum: Int, density: Double) -> Int {
    guard density > 0 else { return 0 }
    return max(1, Int((Double(maximum) * clamp(density, lower: 0, upper: 1)).rounded(.up)))
}

func matrixTrackGapRows(trackLength: Int, density: Double) -> Int {
    Int((Double(max(0, trackLength - 2)) * (1 - clamp(density, lower: 0, upper: 1))).rounded())
}

private func positiveModulo(_ value: Int, by modulus: Int) -> Int {
    let remainder = value % modulus
    return remainder >= 0 ? remainder : remainder + modulus
}

private let matrixGlyphs = Array("アカサタナハマヤラワ0123456789ABCDEF<>[]{}").map(String.init)
let matrixDefaultSpeedMultiplier = 1.0
let matrixDefaultDensity = 0.5
let matrixDisplayFPS = 120.0
let matrixRenderInterval = 1.0 / matrixDisplayFPS
let matrixMotionSamplingInterval = 1.0 / 30.0
let matrixGIFDropInterval = 0.15
let matrixWaveAmplitude = 6.5

private func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
    min(upper, max(lower, value))
}
