import SwiftUI

struct FeedView: View {
    @StateObject private var vm: FeedVM
    @State private var scrollProxy: ScrollViewProxy?
    private let topAnchorID = "top-anchor"

    init(container: AppContainer = .live) {
        _vm = StateObject(wrappedValue: FeedVM(api: container.feedAPI))
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: 0)
                        .id(topAnchorID)
                        .onAppear { scrollProxy = proxy }

                    if let updated = vm.lastUpdated {
                        Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }

                    ScrollView {
                        MasonryLayout(columns: 2, spacing: 1) {
                            ForEach(vm.items) { post in
                                NavigationLink(value: post) {
                                    FeedCard(post: post)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                    }
                    .refreshable { await vm.refresh() }
                }
                // ⬇️ Listen for tab selection event
                .onReceive(NotificationCenter.default.publisher(for: .refreshDiscover)) { _ in
                    withAnimation(.easeInOut) {
                        scrollProxy?.scrollTo(topAnchorID, anchor: .top)
                    }
                    Task { await vm.refresh() }
                }
            }
            .navigationTitle("Discover")
            .navigationBarTitleDisplayMode(.large)
            .task { await vm.loadInitial() }
            .toolbar {
                // keep only search on the right
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: SearchView(api: AppContainer.live.feedAPI)) {
                        Image(systemName: "magnifyingglass")
                    }
                }
            }
            .navigationDestination(for: Post.self) { post in
                PostDetailView(post: post)
            }
            .navigationDestination(for: User.self) { user in
                OtherUserProfileView(userId: user.id)
            }
            .overlay { if vm.isLoading { ProgressView() } }
        }
    }
}
