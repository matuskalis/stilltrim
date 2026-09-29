import Observation
import Photos
import PhotosUI
import UIKit

@MainActor @Observable
final class LibraryAccess {
    private(set) var status: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

    var canRead: Bool { status == .authorized || status == .limited }

    func request() async {
        status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    func refresh() {
        status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func presentLimitedPicker() {
        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first?.keyWindow?.rootViewController
        else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: root)
    }

    func openSystemSettings() {
        if let settings = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(settings) }
    }
}
