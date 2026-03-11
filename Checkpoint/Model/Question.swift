import Foundation

struct Question: Codable, Identifiable, Equatable {
    let id: String
    let text: String
    var isEnabled: Bool
    let isCustom: Bool
    let categoryId: String
}
