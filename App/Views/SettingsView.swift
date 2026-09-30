import Photos
import SwiftUI

struct DeletionSummaryView: View {
    let summary: DeletionSummary
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("\(summary.count.formatted()) \(summary.count == 1 ? "item" : "items") deleted")
                .font(.title.bold())
                .accessibilityIdentifier("deletion-title")
            Text("Deleted items stay in Recently Deleted for 30 days. You can recover them there.")
            if summary.bytes > 0 {
                Text("The \(summary.bytes.formatted(.byteCount(style: .file))) comes back when you empty Recently Deleted.")
            }
            Text("With iCloud Photos on, deleted items also leave your other devices.")
            VStack(alignment: .leading, spacing: 8) {
                Text("To empty Recently Deleted")
                    .font(.headline)
                Text("Open Photos. Recently Deleted is under Utilities. Unlock it, tap Select, then delete the items.")
            }
            Spacer()
            Button("Done") { model.dismissDeletionSummary() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.medium, .large])
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
        let info = Bundle.main
        let short = info.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = info.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Privacy") {
                    Text("Stilltrim sends nothing off this phone. It has no account, no server, no analytics, no ads and no networking code.")
                    Text("To scan faster next time, it keeps a small record per photo on this phone. The record holds numbers and labels only: file size, whether the photo is edited, quality scores, a similarity fingerprint and, for screenshots, the kind. It holds no pictures and no text, and it is left out of backups.")
                    Text("To sort screenshots, it reads their text on this phone and keeps only the kind, such as Receipts.")
                    DisclosureGroup("Check it yourself") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("1. Open iOS Settings, then Privacy & Security, then App Privacy Report. Turn it on.")
                            Text("2. Come back and scan.")
                            Text("3. Open App Privacy Report again. Under App Network Activity, Stilltrim is not listed. Under Data & Sensor Access it lists Photos, as expected.")
                            Text("Or scan in airplane mode. The scan still works.")
                        }
                        .font(.subheadline)
                    }
                }
                Section {
                    LabeledContent("Access", value: accessText)
                    if model.access.status == .limited {
                        Button("Choose more photos") { model.access.presentLimitedPicker() }
                    }
                    Button("Open iOS Settings") { model.access.openSystemSettings() }
                } header: {
                    Text("Photo access")
                } footer: {
                    if model.access.status == .limited {
                        Text("Stilltrim scans only the photos you chose.")
                    }
                }
                Section {
                    Button("Erase app data", role: .destructive) { confirmErase = true }
                } footer: {
                    Text("Removes the scan cache and the list of photos you chose to keep. Your photos are not touched. Photos you kept can show up in the lists again.")
                }
                Section("About") {
                    LabeledContent("Version", value: version)
                    LabeledContent("Similarity check", value: model.similarityMethod)
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
