import Foundation
import SwiftData
import TrainingLoopCore

/// A template: list fields + the whole structure as one JSON value (TECH T2, ADR 0001).
@Model
final class Template {
    var id: UUID = UUID()
    var name: String = ""
    var sortIndex: Int = 0
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    /// Cache for the template card (DESIGN V5).
    var lastPerformedAt: Date?
    var definitionData: Data = Data()
    /// Key in `ExampleTemplates` of the example it was created as (SPEC D18); nil for the user's own
    /// templates and for copies. Finds the examples each device creates on its first launch (TECH T13).
    var exampleKey: String?

    init(name: String, definition: TemplateDefinition, sortIndex: Int) {
        self.name = name
        self.sortIndex = sortIndex
        self.definition = definition
    }

    var definition: TemplateDefinition {
        get {
            do {
                return try JSONDecoder().decode(TemplateDefinition.self, from: definitionData)
            } catch {
                // Logged only: a damaged template shows up empty instead of stopping the app.
                Persistence.logger.error("Template definition can't be decoded: \(String(describing: error), privacy: .public)")
                return TemplateDefinition()
            }
        }
        set {
            definitionData = (try? JSONEncoder().encode(newValue)) ?? Data()
            updatedAt = .now
        }
    }
}
