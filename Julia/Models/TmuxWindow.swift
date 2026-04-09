import Foundation

struct TmuxWindow: Identifiable, Hashable, Sendable {
    let id: String
    let index: Int
    let name: String
    let sessionName: String
    let isActive: Bool
    let lastActivity: Date?

    init(
        id: String,
        index: Int,
        name: String,
        sessionName: String,
        isActive: Bool = false,
        lastActivity: Date? = nil
    ) {
        self.id = id
        self.index = index
        self.name = name
        self.sessionName = sessionName
        self.isActive = isActive
        self.lastActivity = lastActivity
    }
}
