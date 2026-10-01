import CleanupCore
import SwiftUI

/// One bar for the whole scan, a rail of the steps and an elapsed clock. No time-left estimate.
struct ScanStatusView: View {
    let progress: ScanProgress
    let startedAt: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ProgressView(value: progress.overall)
                .animation(reduceMotion ? nil : .linear(duration: 0.25), value: progress.overall)
                .accessibilityLabel("Scan progress")
            VStack(alignment: .leading, spacing: 10) {
                ForEach(ScanStage.allCases, id: \.self) { stage in
                    StepRow(stage: stage, progress: progress)
                }
            }
            HStack {
                Text("Elapsed")
                Spacer()
                Text(startedAt, style: .timer)
                    .monospacedDigit()
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
        .padding(.horizontal)
    }
}

private struct StepRow: View {
    let stage: ScanStage
    let progress: ScanProgress

    private enum State { case done, current, pending }

    private var state: State {
        if stage.rawValue < progress.stage.rawValue { return .done }
        return stage == progress.stage ? .current : .pending
    }

    private var count: String? {
        guard state == .current, progress.total > 0 else { return nil }
        return "\(progress.done.formatted()) of \(progress.total.formatted())"
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 22)
                .foregroundStyle(state == .pending ? .tertiary : .secondary)
            Text(stage.stepTitle)
                .fontWeight(state == .current ? .semibold : .regular)
                .foregroundStyle(state == .pending ? .secondary : .primary)
            Spacer()
            if let count {
                Text(count)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(spokenState))
    }

    private var symbol: String {
        switch state {
        case .done: "checkmark.circle.fill"
        case .current: "circle.inset.filled"
        case .pending: "circle"
        }
    }

    private var spokenState: String {
        switch state {
        case .done: "done"
        case .current: "in progress"
        case .pending: "waiting"
        }
    }
}
