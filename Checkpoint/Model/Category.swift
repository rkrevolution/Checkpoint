import Foundation

struct Category: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    var isEnabled: Bool
    let isCustom: Bool
}
