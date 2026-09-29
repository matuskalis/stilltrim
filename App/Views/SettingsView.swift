import Photos
import SwiftUI

struct DeletionSummaryView: View {
    let summary: DeletionSummary
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("\(summary.count.formatted()) deleted")
                .font(.title.bold())
            Text("They moved to Recently Deleted. The \(summary.bytes.formatted(.byteCount(style: .file))) comes back once you empty it.")
            VStack(alignment: .leading, spacing: 8) {
                Text("To empty it")
                    .font(.headline)
                Text("1. Open Photos, then Albums.")
                Text("2. Scroll down to Recently Deleted.")
                Text("3. Tap Select, then Delete All.")
            }
            Spacer()
            Button("Done") { model.dismissDeletionSummary() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.medium])
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmErase = false

    private var accessText: String {
        switch model.access.status {
        case .authorized: "Full access"
        case .limited: "Selected photos only"
        case .denied, .restricted: "Off"
        default: "Not asked yet"
        }
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Privacy") {
                    Text("Your photos never leave this phone. This app has no account, no server, no analytics and no ads, and it contains no networking code.")
                    DisclosureGroup("Check it yourself") {
                        Text("Turn on airplane mode and scan: everything still works. Or open the iOS Settings app, then Privacy & Security, then App Privacy Report: this app shows no network activity.")
                            .font(.subheadline)
                    }
                }
                Section("Photo access") {
                    LabeledContent("Access", value: accessText)
                    if model.access.status == .limited {
                        Button("Choose more photos") { model.access.presentLimitedPicker() }
                    }
                    Button("Open iOS Settings") { model.access.openSystemSettings() }
                }
                Section {
                    Button("Erase app data", role: .destructive) { confirmErase = true }
                } footer: {
                    Text("Removes the scan cache and the list of photos you chose to keep. Your photos are not touched.")
                }
                Section("About") {
                    LabeledContent("Version", value: version)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Erase app data?", isPresented: $confirmErase, titleVisibility: .visible) {
                Button("Erase", role: .destructive) { Task { await model.eraseAppData() } }
            }
        }
    }
}
