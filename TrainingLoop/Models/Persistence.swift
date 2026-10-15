import Foundation
import os
import SwiftData

/// Store errors are logged, not swallowed; in debug builds they stop at once.
enum Persistence {
    static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TrainingLoop", category: "Persistence")

    static func report(_ message: String, _ error: any Error) {
        logger.error("\(message, privacy: .public): \(String(describing: error), privacy: .public)")
        assertionFailure("\(message): \(error)")
    }
}

extension ModelContext {
    /// Explicit save (TECH T1) that reports a failure instead of dropping it.
    func saveOrReport() {
        do {
            try save()
        } catch {
            Persistence.report("Saving failed", error)
        }
    }
}
