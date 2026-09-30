import Photos
import SwiftUI

struct WelcomeView: View {
    @Environment(AppModel.self) private var model


    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                Text("Stilltrim")
                    .font(.largeTitle.bold())
                Text("Finds screenshots, similar shots, blurry photos and big videos. You choose what to delete.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 16) {
                PromiseRow(symbol: "iphone", text: "Stilltrim checks photos on this phone only.")
                PromiseRow(symbol: "icloud.slash", text: "Stilltrim uploads nothing. No account, no analytics, no ads.")
                PromiseRow(symbol: "hand.tap", text: "Stilltrim deletes only what you select and confirm. Deleted photos stay in Recently Deleted for 30 days.")
            }
            Spacer()
            switch model.access.status {
            case .denied:
                Text("Photo access is off. Turn it on in iOS Settings to scan.")
                    .foregroundStyle(.secondary)
                Button("Open iOS Settings") { model.access.openSystemSettings() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("open-ios-settings")
            case .restricted:
                Text("Photo access is restricted on this phone, for example by Screen Time. Stilltrim cannot scan until that changes.")
                    .foregroundStyle(.secondary)
            default:
                Text("Next, iOS asks how much of your library Stilltrim may see.")
                    .foregroundStyle(.secondary)
                Button("Continue") { Task { await model.access.request() } }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("request-photo-access")
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
