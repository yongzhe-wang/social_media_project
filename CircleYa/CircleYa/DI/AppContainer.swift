
import Foundation

// MARK: - Protocols
protocol FeedAPI {
    func fetchFeed(cursor: String?) async throws -> FeedPage
    func fetchNearby(cursor: String?) async throws -> FeedPage   // NEW
}


final class AppContainer {
    let feedAPI: FeedAPI

    init(feedAPI: FeedAPI) {
        self.feedAPI = feedAPI
    }
}

extension AppContainer {
    static var live: AppContainer {
        .init(feedAPI: FirebaseFeedAPI())
    }
}

// MARK: - SwiftUI EnvironmentKey
import SwiftUI
private struct ContainerKey: EnvironmentKey {
    static let defaultValue: AppContainer = .live
}

extension EnvironmentValues {
    var container: AppContainer {
        get { self[ContainerKey.self] }
        set { self[ContainerKey.self] = newValue }
    }
}
