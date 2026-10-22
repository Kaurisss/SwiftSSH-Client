import Foundation
import SwiftData

@MainActor
enum LocalStore {
    static func open(at url: URL) throws -> ModelContainer {
        // Keep the upstream schema so existing local stores remain readable.
        let schema = Schema([
            ConnectionProfile.self,
            SSHKey.self,
            KnownHost.self,
            Snippet.self,
            PortForward.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            url: url,
            cloudKitDatabase: .none
        )
        // Propagate failures; never delete stores or silently switch to memory.
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
