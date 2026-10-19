import GalleryCore
import Photos
import SwiftUI

/// The read-only timeline: every visible photo and video, newest first, grouped by month. Tapping
/// an item opens it in the full-screen viewer.
struct TimelineScreen: View {
    @Environment(PhotoLibraryModel.self) private var library
    @State private var viewer: ViewerStart?

    private let columns = [GridItem(.adaptive(minimum: 96, maximum: 180), spacing: 2)]

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Photos")
        }
        .fullScreenCover(item: $viewer) { start in
            ViewerScreen(startIndex: start.index)
                .environment(library)
        }
    }

    @ViewBuilder
    private var content: some View {
        if library.content == .unavailable {
            MessageScreen(
                symbol: "exclamationmark.triangle",
                title: "The photo library isn't available",
                message: "iOS reports that the library can't be read right now. Gallery shows it again as soon as it's available."
            )
        } else if library.content == .loaded, let assets = library.assets {
            if assets.count == 0 {
                EmptyLibraryView(limited: library.access == .limited)
            } else {
                grid(assets)
            }
        } else {
            ProgressView("Loading photos")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func grid(_ assets: PHFetchResult<PHAsset>) -> some View {
        ScrollView {
            if library.access == .limited {
                LimitedAccessBanner()
            }
            LazyVGrid(columns: columns, spacing: 2, pinnedViews: [.sectionHeaders]) {
                ForEach(library.sections) { section in
                    Section {
                        ForEach(section.range, id: \.self) { index in
                            if index < assets.count {
                                Button {
                                    viewer = ViewerStart(index: index)
                                } label: {
                                    AssetTile(asset: assets.object(at: index), imageManager: library.imageManager)
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Opens full screen")
                            }
                        }
                    } header: {
                        SectionHeader(title: Self.title(for: section.month))
                    }
                }
            }
        }
    }

    private static func title(for month: MonthKey?) -> String {
        guard let month,
              let date = Calendar.current.date(from: DateComponents(year: month.year, month: month.month))
        else {
            return "Unknown date"
        }
        return date.formatted(.dateTime.month(.wide).year())
    }
}

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)
            .accessibilityAddTraits(.isHeader)
    }
}
