import Foundation
import Sparkle

@MainActor
final class AppUpdater {
    private let controller: SPUStandardUpdaterController?

    init(bundle: Bundle = .main) {
        let feedURL = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String
        let publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        if feedURL?.isEmpty == false, publicKey?.isEmpty == false {
            controller = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
        } else {
            controller = nil
        }
    }

    var isConfigured: Bool {
        controller != nil
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
