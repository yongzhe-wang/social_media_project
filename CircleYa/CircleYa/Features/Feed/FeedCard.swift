// Features/Feed/FeedCard.swift
import SwiftUI

struct FeedCard: View {
    var post: Post
    var showActions: Bool = true
    var captionLines: Int = 2

    // clamp portrait/square variety
    private let aspectRange: ClosedRange<CGFloat> = 1.9...2.5
    // clamp absolute height (tweak to taste)
    private let minImageH: CGFloat = 160
    private let maxImageH: CGFloat = 320
    private let corner: CGFloat = 3

    private var clampedAspect: CGFloat {
        guard let m = post.media.first else { return 1.25 }
        let raw = max(CGFloat(m.height), 1) / max(CGFloat(m.width), 1)
        return min(max(raw, aspectRange.lowerBound), aspectRange.upperBound)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            // IMAGE (fixed width by MasonryLayout, height clamped)
            AsyncImage(url: post.media.first?.thumbURL ?? post.media.first?.url) { phase in
                switch phase {
                case .empty:
                    Rectangle()
                        .fill(.gray.opacity(0.12))
                        .aspectRatio(clampedAspect, contentMode: .fit)
                        .frame(minHeight: minImageH)
                        .clipShape(RoundedRectangle(cornerRadius: corner))

                case .success(let img):
                    img.resizable()
                        .scaledToFill()
                        .aspectRatio(clampedAspect, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: corner))
                        .clipped()
                        .overlay(
                            LinearGradient(colors: [.clear, .black.opacity(0.55)],
                                           startPoint: .top, endPoint: .bottom)
                                .clipShape(RoundedRectangle(cornerRadius: corner))
                        )
                        .overlay(alignment: .topTrailing) {
                            if post.media.count > 1 {
                                HStack(spacing: 4) {
                                    Image(systemName: "photo.on.rectangle")
                                    Text("\(post.media.count)").fontWeight(.semibold)
                                }
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.ultraThinMaterial, in: Capsule())
                                .padding(10)
                            }
                        }

                case .failure:
                    Rectangle()
                        .fill(.gray.opacity(0.12))
                        .aspectRatio(clampedAspect, contentMode: .fit)
                        .frame(minHeight: minImageH)
                        .clipShape(RoundedRectangle(cornerRadius: corner))
                        .overlay(Image(systemName: "photo").foregroundColor(.gray))

                @unknown default:
                    EmptyView()
                }
            }
            .transaction { $0.animation = nil }

            Text(post.text)
                .font(.caption)                // smaller than subheadline
                .foregroundStyle(.primary)
                .lineLimit(2)                  // maximum 2 lines
                .truncationMode(.tail)         // truncate with "..."
                .padding(.horizontal, 6)

            // FOOTER
            // FOOTER
            HStack(spacing: 10) {
                // ⬇️ Avatar + name open OtherUserProfileView
                NavigationLink(value: post.author) {
                    HStack(spacing: 10) {
                        AvatarView(user: post.author, size: 15)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(post.author.displayName)
                                .font(.caption2).fontWeight(.semibold)
                                .lineLimit(1).truncationMode(.tail)
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer(minLength: 6)

                if showActions {
                    PostActionsView(post: post)
                }
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(UIColor.secondarySystemBackground)))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }
}

private struct IconCount: View {
    let name: String
    let count: Int
    init(_ name: String, _ count: Int) { self.name = name; self.count = count }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: name).imageScale(.small)
            Text("\(count)")
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

// MARK: - Like / Save Buttons
struct PostActionsView: View {
    @State private var isLiked = false
    @State private var isSaved = false
    @State private var likeCount: Int
    @State private var saveCount: Int

    let post: Post
    let api = FirebaseFeedAPI()

    init(post: Post) {
        self.post = post
        _likeCount = State(initialValue: post.likeCount)
        _saveCount = State(initialValue: post.saveCount)
    }

    var body: some View {
        HStack(spacing: 14) {
            Button {
                Task {
                    do {
                        let newState = try await api.toggleLike(for: post.id)
                        await MainActor.run {
                            isLiked = newState
                            likeCount += newState ? 1 : -1
                        }
                    } catch {
                        print("❌ Like failed:", error)
                    }
                }
            } label: {
                Label("\(likeCount)", systemImage: isLiked ? "heart.fill" : "heart")
                    .labelStyle(.iconOnly)
                    .foregroundColor(isLiked ? .red : .secondary)
            }
            .buttonStyle(.plain)

            Button {
                Task {
                    do {
                        let newState = try await api.toggleSave(for: post.id)
                        await MainActor.run {
                            isSaved = newState
                            saveCount += newState ? 1 : -1
                        }
                    } catch {
                        print("❌ Save failed:", error)
                    }
                }
            } label: {
                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                    .foregroundColor(isSaved ? .blue : .secondary)
            }
            .buttonStyle(.plain)
        }
        .font(.caption)
        .task {
            isLiked = await api.isPostLiked(post.id)
            isSaved = await api.isPostSaved(post.id)
        }
    }
}

