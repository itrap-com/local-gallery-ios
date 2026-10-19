import Photos
import SwiftUI

/// The Library tab: every visible photo and video, newest first, grouped by month.
struct TimelineScreen: View {
    @Environment(PhotoLibraryModel.self) private var library
    @State private var filter: MediaFilter = .all
    @State private var feed = MediaFeed { MediaFetch.all() }

    var body: some View {
        @Bindable var library = library
        NavigationStack {
            Group {
                if library.isUnavailable {
                    MessageScreen(
                        symbol: "exclamationmark.triangle",
                        title: "The photo library isn't available",
                        message: "iOS reports that the library can't be read right now. Gallery shows it again as soon as it's available."
                    )
                } else {
                    MediaGrid(feed: feed, title: filter == .all ? "Library" : filter.title) {
                        if library.access == .limited {
                            LimitedAccessBanner()
                        }
                    } empty: {
                        if filter == .all {
                            EmptyLibraryView(limited: library.access == .limited)
                        } else {
                            MessageScreen(
                                symbol: filter == .videos ? "video" : "photo",
                                title: filter == .videos ? "No visible videos" : "No visible photos",
                                message: "Gallery shows only what iOS lets it see. Choose All items to see everything visible."
                            )
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Show", selection: $filter) {
                            ForEach(MediaFilter.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        Picker("Columns", selection: $library.gridColumns) {
                            ForEach(2...7, id: \.self) { count in
                                Text("\(count) columns").tag(count)
                            }
                        }
                    } label: {
                        Image(systemName: filter == .all
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill")
                    }
                    .accessibilityLabel("View options")
                }
            }
        }
        .onChange(of: library.accessGeneration) { feed.reload() }
        .onChange(of: filter) { _, next in
            feed.update { MediaFetch.all(next) }
        }
    }
}
