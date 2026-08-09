import CoreMotion
import Observation
import SwiftUI
import CodexMeterCore

@MainActor
@Observable
final class CodexiOSMatrixMotion {
    private let manager = CMMotionManager()

    var horizontal = 0.0
    var vertical = 0.0
    var isAvailable = false

    func start() {
        guard manager.isDeviceMotionAvailable else {
            isAvailable = false
            return
        }

        isAvailable = true
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, _ in
            guard let self, let gravity = motion?.gravity else { return }
            horizontal = clamp(gravity.x * 1.55, lower: -1, upper: 1)
            vertical = clamp((gravity.y + 0.35) * 1.35, lower: -1, upper: 1)
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}

struct CodexiOSMatrixQuotaView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var model: CodexiOSModel
    @State private var motion = CodexiOSMatrixMotion()
    @State private var speedMultiplier = 1.0
    @State private var dragStartSpeed = 1.0

    private var weeklyRemaining: Double? {
        guard let snapshot = model.snapshot else { return nil }
        guard let limit = CodexQuotaPresentationRules.orderedLimits(snapshot.limits).first(where: { $0.bucket == .codex }) else {
            return nil
        }
        return CodexiOSQuotaPresentation.weeklyWindow(for: limit)?.remainingPercent
    }

    private var percentText: String {
        guard let weeklyRemaining else { return "--" }
        return "\(Int(weeklyRemaining.rounded()))"
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                    .ignoresSafeArea()

                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    Canvas { context, size in
                        drawMatrix(
                            context: &context,
                            size: size,
                            date: timeline.date,
                            remaining: weeklyRemaining,
                            horizontalTilt: motion.horizontal,
                            verticalTilt: motion.vertical,
                            speedMultiplier: speedMultiplier,
                            reduceMotion: reduceMotion
                        )
                    }
                    .accessibilityHidden(true)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { value in
                                speedMultiplier = matrixSpeedMultiplier(
                                    from: dragStartSpeed,
                                    verticalTranslation: value.translation.height
                                )
                            }
                            .onEnded { _ in
                                dragStartSpeed = speedMultiplier
                            }
                    )
                }

                VStack(spacing: 0) {
                    HStack {
                        Button {
                            dismiss()
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
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(weeklyRemaining.map { "\(Int($0.rounded())) percent remaining" } ?? "Weekly quota unavailable")
                    .padding(.top, 50)

                    Spacer()
                }
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .task {
            motion.start()
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
    remaining: Double?,
    horizontalTilt: Double,
    verticalTilt: Double,
    speedMultiplier: Double,
    reduceMotion: Bool
) {
    guard let remaining else { return }

    let time = reduceMotion ? 0 : date.timeIntervalSinceReferenceDate
    let clampedRemaining = clamp(remaining, lower: 0, upper: 100)
    let baseSurface = size.height * (1 - clampedRemaining / 100)
    let columnCount = max(24, Int(size.width / 13))
    let columnWidth = size.width / CGFloat(columnCount)
    let fontSize = max(10, min(14, size.width / 30))
    let lineHeight = fontSize * 1.3
    let glyphs = Array("アカサタナハマヤラワ0123456789ABCDEF<>[]{}")

    for column in 0..<columnCount {
        let x = (CGFloat(column) + 0.45) * columnWidth
        let xRatio = CGFloat(column) / CGFloat(max(1, columnCount - 1))
        let phase = Double(column) * 0.61
        let surface = baseSurface
            + (reduceMotion ? 0 : sin(time * 1.35 + phase) * 3.5)
            + horizontalTilt * (xRatio - 0.5) * size.width * 0.115
            + verticalTilt * 8
        let travel = max(size.height - surface + 70, 120)
        let speed = (260 + seeded(Double(column) * 0.7) * 420) * speedMultiplier
        let offset = ((time * speed + phase * travel).truncatingRemainder(dividingBy: travel + 80)) - 50
        let rowCount = Int((size.height - surface) / lineHeight) + 10

        for row in 0..<rowCount {
            let y = surface + offset + CGFloat(row) * lineHeight
            guard y > surface - fontSize, y < size.height + fontSize else { continue }

            let distance = max(0, min(1, (y - surface) / max(1, size.height - surface)))
            let flicker = 0.88 + sin(time * 2.4 + phase + Double(row)) * 0.10
            let lead = !reduceMotion && (Int(time * (4 + speedMultiplier * 4)) + column * 3) % max(7, rowCount) == row
            let opacity = min(0.98, max(0.08, (0.78 - distance * 0.52) * flicker * (lead ? 1.5 : 1)))
            let glyphIndex = abs(column * 31 + row * 17 + (reduceMotion ? 0 : Int(time * (4 + speedMultiplier * 8)))) % glyphs.count
            let glyph = String(glyphs[glyphIndex])

            context.draw(
                Text(glyph)
                    .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                    .foregroundStyle(
                        lead
                            ? Color(red: 0.9, green: 1, blue: 0.92).opacity(opacity)
                            : Color(red: 0.03, green: 0.94, blue: 0.16).opacity(opacity)
                    ),
                at: CGPoint(x: x, y: y),
                anchor: .topLeading
            )
        }
    }

    var wave = Path()
    let samples = 36
    for sample in 0...samples {
        let xRatio = CGFloat(sample) / CGFloat(samples)
        let x = xRatio * size.width
        let y = baseSurface
            + (reduceMotion ? 0 : sin(time * 1.35 + Double(sample) * 0.42) * 3.5)
            + horizontalTilt * (xRatio - 0.5) * size.width * 0.115
            + verticalTilt * 8
        if sample == 0 {
            wave.move(to: CGPoint(x: x, y: y))
        } else {
            wave.addLine(to: CGPoint(x: x, y: y))
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

func matrixSpeedMultiplier(from start: Double, verticalTranslation: CGFloat) -> Double {
    clamp(start - Double(verticalTranslation / 240) * 0.5, lower: 0.5, upper: 1)
}

private func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
    min(upper, max(lower, value))
}
