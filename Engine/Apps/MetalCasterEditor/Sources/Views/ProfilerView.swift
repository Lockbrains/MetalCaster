import SwiftUI
import MetalCasterCore

struct ProfilerView: View {
    @Environment(EditorState.self) private var state
    @State private var selectedTab = 0

    private var profiler: MCProfiler { MCProfiler.shared }

    var body: some View {
        VStack(spacing: 0) {
            profilerToolbar
            Rectangle()
                .fill(MCTheme.panelBorder)
                .frame(height: 1)

            if profiler.isEnabled {
                if selectedTab == 0 {
                    overviewTab
                } else {
                    passBreakdownTab
                }
            } else {
                disabledPlaceholder
            }
        }
        .background(MCTheme.background)
    }

    // MARK: - Toolbar

    private var profilerToolbar: some View {
        HStack(spacing: 8) {
            Button {
                MCProfiler.shared.isEnabled.toggle()
            } label: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(profiler.isEnabled ? MCTheme.statusGreen : MCTheme.statusGray)
                        .frame(width: 6, height: 6)
                    Text(profiler.isEnabled ? "Recording" : "Paused")
                        .font(MCTheme.fontCaption)
                        .foregroundStyle(MCTheme.textSecondary)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Picker("", selection: $selectedTab) {
                Text("Overview").tag(0)
                Text("Passes").tag(1)
            }
            .pickerStyle(.segmented)
            .frame(width: 160)

            Button {
                MCProfiler.shared.clearHistory()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundStyle(MCTheme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Overview Tab

    private var overviewTab: some View {
        let frames = profiler.recentFrames(count: 120)

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                fpsGraph(frames: frames)

                if let latest = frames.last {
                    statsGrid(latest)
                    systemTimingsList(latest)
                }
            }
            .padding(8)
        }
    }

    private func fpsGraph(frames: [ProfileFrameData]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Frame Time")
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textSecondary)

            GeometryReader { geo in
                let maxMs = max(frames.map(\.deltaTimeMs).max() ?? 16.67, 16.67)
                Path { path in
                    guard frames.count > 1 else { return }
                    let step = geo.size.width / CGFloat(frames.count - 1)
                    for (i, frame) in frames.enumerated() {
                        let x = step * CGFloat(i)
                        let y = geo.size.height * (1.0 - CGFloat(frame.deltaTimeMs / maxMs))
                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(MCTheme.statusGreen, lineWidth: 1)

                Path { path in
                    let y = geo.size.height * (1.0 - 16.67 / maxMs)
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geo.size.width, y: y))
                }
                .stroke(MCTheme.statusOrange.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .frame(height: 60)
        }
    }

    private func statsGrid(_ data: ProfileFrameData) -> some View {
        let memoryMB = String(format: "%.1f", Double(data.allocatedGPUMemoryBytes) / (1024.0 * 1024.0))
        return LazyVGrid(columns: [
            GridItem(.flexible()), GridItem(.flexible()),
            GridItem(.flexible()), GridItem(.flexible())
        ], spacing: 8) {
            statCell("FPS", value: String(format: "%.0f", data.fps))
            statCell("CPU", value: String(format: "%.1fms", data.totalCpuTimeMs))
            statCell("Draw Calls", value: "\(data.drawCallCount)")
            statCell("Triangles", value: formatCount(data.triangleCount))
            statCell("State Changes", value: "\(data.stateChangeCount)")
            statCell("GPU Memory", value: "\(memoryMB) MB")
            if let gpu = data.totalGpuTimeMs {
                statCell("GPU", value: String(format: "%.1fms", gpu))
            }
        }
    }

    private func statCell(_ label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(MCTheme.fontMono)
                .foregroundStyle(MCTheme.textPrimary)
            Text(label)
                .font(MCTheme.fontSmall)
                .foregroundStyle(MCTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(MCTheme.inputBackground)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func systemTimingsList(_ data: ProfileFrameData) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("System Timings")
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textSecondary)
            ForEach(data.systemTimings, id: \.name) { timing in
                HStack {
                    Text(timing.name)
                        .font(MCTheme.fontMono)
                        .foregroundStyle(MCTheme.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text(String(format: "%.2fms", timing.timeMs))
                        .font(MCTheme.fontMono)
                        .foregroundStyle(barColor(timing.timeMs))
                }
            }
        }
    }

    // MARK: - Pass Breakdown Tab

    private var passBreakdownTab: some View {
        let frames = profiler.recentFrames(count: 1)
        return ScrollView {
            if let latest = frames.last {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Render Pass Breakdown (Frame \(latest.frameNumber))")
                        .font(MCTheme.fontCaption)
                        .foregroundStyle(MCTheme.textSecondary)
                        .padding(.bottom, 4)

                    ForEach(latest.passTimings, id: \.name) { pass in
                        HStack {
                            Text(pass.name)
                                .font(MCTheme.fontMono)
                                .foregroundStyle(MCTheme.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            if let gpu = pass.gpuTimeMs {
                                Text(String(format: "GPU %.2fms", gpu))
                                    .font(MCTheme.fontMono)
                                    .foregroundStyle(MCTheme.statusBlue)
                            }
                            Text(String(format: "CPU %.2fms", pass.cpuTimeMs))
                                .font(MCTheme.fontMono)
                                .foregroundStyle(barColor(pass.cpuTimeMs))
                        }
                    }
                }
                .padding(8)
            } else {
                Text("No pass data recorded")
                    .font(MCTheme.fontCaption)
                    .foregroundStyle(MCTheme.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Disabled State

    private var disabledPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "gauge.with.dots.needle.0percent")
                .font(.system(size: 24))
                .foregroundStyle(MCTheme.textTertiary)
            Text("Profiler is paused")
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textTertiary)
            Text("Click Recording to start")
                .font(MCTheme.fontSmall)
                .foregroundStyle(MCTheme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func barColor(_ ms: Double) -> Color {
        if ms > 8.0 { return MCTheme.statusRed }
        if ms > 4.0 { return MCTheme.statusOrange }
        return MCTheme.statusGreen
    }

    private func formatCount(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000.0) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000.0) }
        return "\(n)"
    }
}
