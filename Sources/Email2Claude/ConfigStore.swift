import Foundation
import Email2ClaudeCore

/// The live configuration. Every change is written to disk straight away.
@MainActor
final class ConfigStore: ObservableObject {
    @Published var config: Config {
        didSet { try? config.save(to: url) }
    }

    private let url: URL

    init() {
        url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Email2Claude/config.json")
        config = Config.load(from: url)
    }
}
