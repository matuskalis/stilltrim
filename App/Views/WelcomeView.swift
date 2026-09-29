import Photos
import SwiftUI

struct WelcomeView: View {
    @Environment(AppModel.self) private var model

    private var accessRefused: Bool {
        model.access.status == .denied || model.access.status == .restricted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                Text("Photo Cleanup")
                    .font(.largeTitle.bold())
                Text("Finds screenshots, duplicates and bad shots, and lets you delete them in a few taps.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 16) {
                PromiseRow(symbol: "iphone", text: "Every photo is checked on this phone.")
                PromiseRow(symbol: "icloud.slash", text: "Nothing is uploaded. No account, no analytics, no ads.")
                PromiseRow(symbol: "hand.tap", text: "Nothing is deleted until you confirm.")
            }
            Spacer()
            if accessRefused {
                Text("Photo access is off. Turn it on in Settings to scan your library.")
                    .foregroundStyle(.secondary)
                Button("Open Settings") { model.access.openSystemSettings() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            } else {
                Button("Allow photo access") { Task { await model.access.request() } }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PromiseRow: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(.tint)
            Text(text)
        }
    }
}
