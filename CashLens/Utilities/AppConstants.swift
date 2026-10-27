import Foundation

/// App-wide constants that must stay identical across every surface
/// (About, store-recovery, App Store metadata, website).
enum AppConstants {
    /// The single support address. Used everywhere the app offers a
    /// way to reach the developer; the website and App Store listing
    /// must match.
    static let supportEmail = "rjadeja053@gmail.com"

    /// `mailto:` URL for `supportEmail`, optionally with a subject
    /// line. Falls back to the bare address if the subject fails to
    /// percent-encode (it never should for plain ASCII).
    static func supportMailURL(subject: String? = nil) -> URL {
        var string = "mailto:\(supportEmail)"
        if let subject,
           let encoded = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            string += "?subject=\(encoded)"
        }
        return URL(string: string) ?? URL(string: "mailto:\(supportEmail)")!
    }
}
