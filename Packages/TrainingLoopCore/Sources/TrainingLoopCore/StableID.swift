import CryptoKit
import Foundation

extension UUID {
    /// Name-based UUID (RFC 9562 version 5): the same name always gives the same ID,
    /// on every device and in every app version.
    static func stable(_ name: String, namespace: UUID) -> UUID {
        let namespaceBytes = withUnsafeBytes(of: namespace.uuid) { Array($0) }
        var bytes = Array(Insecure.SHA1.hash(data: namespaceBytes + Array(name.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
