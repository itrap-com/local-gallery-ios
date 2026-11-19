import LocalAuthentication
import Photos
import SwiftUI
import UIKit

/// The Hidden album: items hidden from Gallery's other views, behind Face ID or the passcode.
///
/// Hidden is a view filter, not encryption: the items stay in Photos, and other apps with photo
/// access can still see them. Unlocking needs a device passcode; without one, Hidden stays locked.
/// It locks again when Gallery goes to the background, when the owner leaves the album or switches
/// tabs; opening an item from it keeps it unlocked. The unlock state lives in the library model
/// so the privacy shield can read it.
struct HiddenScreen: View {
    @Environment(PhotoLibraryModel.self) private var library
    @Environment(\.scenePhase) private var scenePhase
    @State private var isAuthenticating = false
    @State private var message: String?
    @State private var feed = MediaFeed { MediaFetch.identifiers([], includeHidden: true) }

    var body: some View {
        Group {
            if library.isHiddenUnlocked {
                MediaGrid(feed: feed, title: "Hidden") {
                    MessageScreen(
                        symbol: "eye.slash",
                        title: "Nothing hidden",
                        message: "Hide a photo or video from the viewer or in select mode. It stays in Photos; Gallery just stops showing it anywhere else."
                    )
                }
            } else {
                MessageScreen(
                    symbol: "lock",
                    title: "Hidden is locked",
                    message: message ?? "Items here are hidden from Gallery's other views. They stay in Photos and aren't encrypted.",
                    actionTitle: isAuthenticating ? nil : "Unlock",
                    action: unlock
                )
                .navigationTitle("Hidden")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if library.isHiddenUnlocked {
                load(library.hidden.list.ids)
            } else {
                unlock()
            }
        }
        .onChange(of: library.hidden.list) { _, list in
            if library.isHiddenUnlocked {
                load(list.ids)
            }
        }
    }

    private func unlock() {
        guard !library.isHiddenUnlocked, !isAuthenticating, scenePhase == .active else { return }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            message = "Set a passcode in Settings to open Hidden. Without one, Gallery keeps it locked."
            return
        }
        isAuthenticating = true
        Task {
            let ok: Bool
            do {
                ok = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Open your Hidden album")
            } catch {
                ok = false
            }
            isAuthenticating = false
            if ok {
                message = nil
                load(library.hidden.list.ids)
                library.isHiddenUnlocked = true
            }
        }
    }

    private func load(_ ids: [String]) {
        feed.update { MediaFetch.identifiers(ids, includeHidden: true) }
    }
}

/// Covers every window while Gallery isn't active and Hidden is open, so the app switcher's
/// snapshot never shows hidden items, including from the viewer or a share sheet over them.
@MainActor
final class PrivacyShield {
    private var cover: UIView?
    private var observers: [NSObjectProtocol] = []

    init(isNeeded: @escaping @MainActor () -> Bool) {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                if isNeeded() {
                    self?.show()
                }
            }
        })
        observers.append(center.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.hide()
            }
        })
    }

    private func show() {
        guard cover == nil else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first
        else { return }
        let view = UIView(frame: window.bounds)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.backgroundColor = .systemBackground
        let icon = UIImageView(image: UIImage(systemName: "lock.fill"))
        icon.tintColor = .secondaryLabel
        icon.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(icon)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        window.addSubview(view)
        cover = view
    }

    private func hide() {
        cover?.removeFromSuperview()
        cover = nil
    }
}
