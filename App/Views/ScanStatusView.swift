import CleanupCore
import SwiftUI

/// One bar for the whole scan, a rail of the steps and an estimate of the time left. The estimate comes from
/// `ScanEstimator`, is smoothed by `ScanTimeLeft`, and counts down once a second between progress updates.
struct ScanStatusView: View {
    let progress: ScanProgress
    let startedAt: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var smoother = ScanTimeLeft()
    @State private var trackedStage = ScanStage.listing
    @State private var stageStartedAt = Date()
    @State private var anchor: (secondsLeft: Double?, at: Date) = (nil, Date())
    @State private var timeLeftText = ScanEstimator.text(secondsLeft: nil, elapsed: 0)

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
            Text(timeLeftText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .contentTransition(.identity)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal)
        .onChange(of: progress) { reanchor() }
        .task {
            while !Task.isCancelled {
                refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func reanchor() {
        let now = Date()
        if progress.stage != trackedStage {
            trackedStage = progress.stage
            stageStartedAt = now
        }
        anchor = (
            ScanEstimator.secondsLeft(
                plan: progress.plan, stage: progress.stage, done: progress.done, total: progress.total,
                secondsInStage: now.timeIntervalSince(stageStartedAt)),
            now
        )
        refresh()
    }

    private func refresh() {
        let now = Date()
        let elapsed = now.timeIntervalSince(startedAt)
        let counted = anchor.secondsLeft.map { max($0 - now.timeIntervalSince(anchor.at), 0) }
        let shown = smoother.update(raw: counted, elapsed: elapsed)
        let text = ScanEstimator.text(secondsLeft: shown, elapsed: elapsed)
        if text != timeLeftText { timeLeftText = text }
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
