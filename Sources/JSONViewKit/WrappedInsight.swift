import Foundation

/// A presentation value shared by browsing analytics and host-specific summaries.
public struct WrappedInsight: Identifiable, Equatable, Sendable {
    public let id: String
    public let eyebrow: String
    public let value: String
    public let detail: String

    public init(id: String, eyebrow: String, value: String, detail: String) {
        self.id = id
        self.eyebrow = eyebrow
        self.value = value
        self.detail = detail
    }
}
