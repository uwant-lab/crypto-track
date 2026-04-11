import Foundation

struct PagedResult<T: Sendable>: Sendable {
    let items: [T]
    let hasMore: Bool
    let progress: Double?
}
