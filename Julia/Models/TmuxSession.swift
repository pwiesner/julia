import Foundation

struct TmuxSession: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    var windows: [TmuxWindow]
    let isAttached: Bool

    init(id: String, name: String, windows: [TmuxWindow] = [], isAttached: Bool = false) {
        self.id = id
        self.name = name
        self.windows = windows
        self.isAttached = isAttached
    }
}
