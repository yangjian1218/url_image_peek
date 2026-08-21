import Foundation

enum ImageSource: Equatable {
    case remote(URL)
    case local(URL)
}

struct ImageSourceResolver {
    func resolve(_ rawValue: String) -> ImageSource? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if value == "~" || value.hasPrefix("~/") {
            let expandedPath = (value as NSString).expandingTildeInPath
            return .local(URL(fileURLWithPath: expandedPath).standardizedFileURL)
        }

        if value.hasPrefix("/") {
            return .local(URL(fileURLWithPath: value).standardizedFileURL)
        }

        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased() else {
            return nil
        }

        switch scheme {
        case "http", "https":
            return url.host == nil ? nil : .remote(url)
        case "file":
            return url.isFileURL ? .local(url.standardizedFileURL) : nil
        default:
            return nil
        }
    }
}
