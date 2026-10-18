import Photos

/// What iOS currently lets Gallery read. A missing grant never means an empty library.
enum LibraryAccess: Equatable {
    case notDetermined
    case denied
    case restricted
    case limited
    case full

    init(_ status: PHAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .restricted: self = .restricted
        case .denied: self = .denied
        case .limited: self = .limited
        case .authorized: self = .full
        @unknown default: self = .denied
        }
    }

    /// Whether the library can be fetched at all.
    var canRead: Bool { self == .full || self == .limited }
}
