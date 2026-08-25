import Foundation

struct A1CellReference: Equatable, Sendable {
    let row: Int
    let column: Int

    static func parse(_ value: String) -> A1CellReference? {
        let letters = value.prefix { $0.isLetter }
        let digits = value.dropFirst(letters.count)
        guard !letters.isEmpty,
              !digits.isEmpty,
              let row = Int(digits),
              row > 0,
              digits.allSatisfy(\.isNumber) else {
            return nil
        }

        let column = letters.uppercased().unicodeScalars.reduce(0) { result, scalar in
            result * 26 + Int(scalar.value - 64)
        }
        return column > 0 ? A1CellReference(row: row, column: column) : nil
    }
}

enum WebSheetURLPolicy {
    static func isSupported(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host.hasSuffix(".feishu.cn") && url.path.hasPrefix("/sheets/")
    }
}
