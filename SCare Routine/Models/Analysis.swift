import Foundation
import SwiftData

/// AI analiz cache'i (local). Server taraflı `analyses` tablosunun aynası.
/// `inputHash` ile dedup — aynı INCI listesi için bir kez AI sorgu.
@Model
final class Analysis {
    @Attribute(.unique) var id: String
    var scope: AnalysisScope
    @Attribute(.unique) var inputHash: String
    var userID: String?                      // nil = paylaşımlı (product/ingredient analizi)
    var subjectID: String?
    var model: String                        // "gemini-2.5-flash"
    var promptVersion: String
    var content: String                      // JSON string (server'dan geldiği gibi)
    var language: String                     // "tr" | "en"
    var tokensIn: Int?
    var tokensOut: Int?
    var costUSD: Double?
    var disclaimerVersion: String
    var createdAt: Date
    var expiresAt: Date?

    init(
        id: String = UUID().uuidString,
        scope: AnalysisScope,
        inputHash: String,
        model: String,
        promptVersion: String,
        content: String,
        language: String,
        disclaimerVersion: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.scope = scope
        self.inputHash = inputHash
        self.model = model
        self.promptVersion = promptVersion
        self.content = content
        self.language = language
        self.disclaimerVersion = disclaimerVersion
        self.createdAt = createdAt
    }
}
