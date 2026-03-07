import SwiftUI
import MetalCasterCore

struct FrameDebuggerView: View {
    @Environment(EditorState.self) private var state
    @State private var isPaused = false
    @State private var frozenFrame: ProfileFrameData?

    private var profiler: MCProfiler { MCProfiler.shared }

    private var displayFrame: ProfileFrameData? {
        if isPaused { return frozenFrame }
        return profiler.latestFrame
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Rectangle()
                .fill(MCTheme.panelBorder)
                .frame(height: 1)

            if let frame = displayFrame {
                frameContent(frame)
            } else {
                emptyState
            }
        }
        .background(MCTheme.background)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                if !isPaused {
                    frozenFrame = profiler.latestFrame
                }
                isPaused.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 9))
                    Text(isPaused ? "Resume" : "Capture")
                        .font(MCTheme.fontCaption)
                }
                .foregroundStyle(MCTheme.textSecondary)
            }
            .buttonStyle(.plain)

            if let frame = displayFrame {
                Text("Frame \(frame.frameNumber)")
                    .font(MCTheme.fontMono)
                    .foregroundStyle(MCTheme.textTertiary)
            }

            Spacer()

            if !profiler.isEnabled {
                HStack(spacing: 4) {
                    Circle()
                        .fill(MCTheme.statusRed)
                        .frame(width: 5, height: 5)
                    Text("Profiler disabled")
                        .font(MCTheme.fontSmall)
                        .foregroundStyle(MCTheme.statusRed)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Frame Content

    private func frameContent(_ frame: ProfileFrameData) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                frameSummary(frame)
                renderPassList(frame)
                drawCallSection(frame)
                resourceSection(frame)
            }
            .padding(8)
        }
    }

    private func frameSummary(_ frame: ProfileFrameData) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Frame Summary")

            HStack(spacing: 16) {
                summaryItem("Delta", String(format: "%.2fms", frame.deltaTimeMs))
                summaryItem("CPU", String(format: "%.2fms", frame.totalCpuTimeMs))
                if let gpu = frame.totalGpuTimeMs {
                    summaryItem("GPU", String(format: "%.2fms", gpu))
                }
                summaryItem("FPS", String(format: "%.0f", frame.fps))
            }
        }
    }

    private func renderPassList(_ frame: ProfileFrameData) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Render Passes (\(frame.passTimings.count))")

            if frame.passTimings.isEmpty {
                Text("No pass data")
                    .font(MCTheme.fontCaption)
                    .foregroundStyle(MCTheme.textTertiary)
            } else {
                let totalCpu = frame.passTimings.map(\.cpuTimeMs).reduce(0, +)
                ForEach(Array(frame.passTimings.enumerated()), id: \.offset) { index, pass in
                    passRow(index: index, pass: pass, totalCpu: totalCpu)
                }
            }
        }
    }

    private func passRow(index: Int, pass: ProfilePassTiming, totalCpu: Double) -> some View {
        let fraction = totalCpu > 0 ? pass.cpuTimeMs / totalCpu : 0

        return VStack(spacing: 2) {
            HStack {
                Text("\(index)")
                    .font(MCTheme.fontMono)
                    .foregroundStyle(MCTheme.textTertiary)
                    .frame(width: 20, alignment: .trailing)
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

            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 2)
                    .fill(passBarColor(fraction))
                    .frame(width: geo.size.width * fraction)
            }
            .frame(height: 3)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(Color.white.opacity(index % 2 == 0 ? 0.02 : 0))
    }

    private func drawCallSection(_ frame: ProfileFrameData) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Draw Statistics")

            HStack(spacing: 16) {
                summaryItem("Draw Calls", "\(frame.drawCallCount)")
                summaryItem("Triangles", formatCount(frame.triangleCount))
                summaryItem("State Changes", "\(frame.stateChangeCount)")
            }
        }
    }

    private func resourceSection(_ frame: ProfileFrameData) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Resources")

            let memoryMB = String(format: "%.1f MB", Double(frame.allocatedGPUMemoryBytes) / (1024.0 * 1024.0))
            HStack(spacing: 16) {
                summaryItem("GPU Memory", memoryMB)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "cpu")
                .font(.system(size: 24))
                .foregroundStyle(MCTheme.textTertiary)
            Text("No frame data captured")
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textTertiary)
            Text("Enable the profiler and run the scene to begin")
                .font(MCTheme.fontSmall)
                .foregroundStyle(MCTheme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Components

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(MCTheme.textTertiary)
            .textCase(.uppercase)
            .tracking(0.8)
            .padding(.bottom, 2)
    }

    private func summaryItem(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(MCTheme.fontMono)
                .foregroundStyle(MCTheme.textPrimary)
            Text(label)
                .font(MCTheme.fontSmall)
                .foregroundStyle(MCTheme.textTertiary)
        }
        .frame(minWidth: 60)
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(MCTheme.inputBackground)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Helpers

    private func barColor(_ ms: Double) -> Color {
        if ms > 8.0 { return MCTheme.statusRed }
        if ms > 4.0 { return MCTheme.statusOrange }
        return MCTheme.statusGreen
    }

    private func passBarColor(_ fraction: Double) -> Color {
        if fraction > 0.5 { return MCTheme.statusRed }
        if fraction > 0.25 { return MCTheme.statusOrange }
        return MCTheme.statusGreen.opacity(0.6)
    }

    private func formatCount(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000.0) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000.0) }
        return "\(n)"
    }
}
