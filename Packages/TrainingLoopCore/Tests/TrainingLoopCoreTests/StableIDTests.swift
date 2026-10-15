import Foundation
import Testing
@testable import TrainingLoopCore

struct StableIDTests {
    /// RFC 9562 test vector: DNS namespace + "www.example.com".
    @Test func matchesVersion5Reference() throws {
        let dns = try #require(UUID(uuidString: "6ba7b810-9dad-11d1-80b4-00c04fd430c8"))
        #expect(UUID.stable("www.example.com", namespace: dns)
            == UUID(uuidString: "2ed6657d-e927-568b-95e1-2665a8aea6a2"))
    }

    @Test func builtinIDsAreUnique() {
        let ids = BuiltinExercises.all.map(\.exerciseID)
        #expect(Set(ids).count == ids.count)
    }

    /// Stored rows and templates refer to these IDs: they must never change.
    @Test func builtinIDIsFixed() throws {
        let squat = try #require(BuiltinExercises.exercise(key: "barbell_back_squat"))
        #expect(squat.exerciseID == UUID.stable("barbell_back_squat", namespace: BuiltinExercises.namespace))
        #expect(squat.exerciseID.uuidString == "F885CC89-B733-5B68-A0C8-AAD391FC6CA1")
    }
}
