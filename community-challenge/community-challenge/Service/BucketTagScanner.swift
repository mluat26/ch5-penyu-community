import Foundation
#if canImport(CoreNFC)
import CoreNFC
#endif

/// How a bucket's sensor ID is written onto its NFC tag.
enum BucketTagFormat {
    /// An NFC external-type record, deliberately not a URI and not bare text.
    ///
    /// A URI record makes any passing iPhone offer to open something when it
    /// touches a bucket. A plain text record makes every tag in the world look
    /// like one of ours. The namespaced type is checked before the payload is
    /// parsed, so a foreign tag is refused without the database being asked
    /// about it at all.
    static let recordType = "com.penyu:sensor"
}

/// Reads the `device.id` of the logger sealed inside a bucket off the NFC tag
/// stuck to its lid.
///
/// The same UUID is flashed into the firmware and sent as `iotdata.sensor_id`,
/// so a scan is what lets a nest be attached to real hardware without anybody
/// typing a UUID on a beach.
///
/// Scanning is never a precondition for creating a nest. It is unavailable on
/// the simulator and on iPhones without a reader, a tag can be missing or
/// unreadable, and the nest is the record that actually matters -- so every
/// failure here is reported and stepped over rather than blocking the flow.
@MainActor
final class BucketTagScanner: NSObject {
    enum Failure: LocalizedError {
        case unsupported
        case notABucketTag
        /// Carries what actually went wrong, rather than collapsing every
        /// failure into one sentence. Three different faults -- a tag Core NFC
        /// cannot read, a read that errored, a payload with no UUID -- all
        /// looked identical on screen, which is why diagnosing this took
        /// guesswork instead of evidence.
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .unsupported:
                "This iPhone cannot scan NFC tags."
            case .notABucketTag:
                "That tag does not carry a bucket's sensor ID."
            case .unreadable(let detail):
                detail
            }
        }
    }

    /// False on the simulator and on iPhones with no NFC reader. This is the
    /// reason the scan cannot be a gate: the app has to stay usable where
    /// scanning simply does not exist.
    static var isSupported: Bool {
        #if canImport(CoreNFC)
        return NFCNDEFReaderSession.readingAvailable
        #else
        return false
        #endif
    }

    #if canImport(CoreNFC)
    private var session: NFCNDEFReaderSession?
    private var continuation: CheckedContinuation<UUID, any Error>?
    #endif

    /// Presents the system scan sheet and returns the sensor ID on the tag.
    ///
    /// Throws `CancellationError` when the person dismisses the sheet, which
    /// callers treat as "no tag offered" rather than as a fault.
    func scan() async throws -> UUID {
        #if canImport(CoreNFC)
        guard Self.isSupported else { throw Failure.unsupported }

        // A session left open by an abandoned scan would keep its continuation
        // suspended forever, so the previous one is always retired first.
        cancel()

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            // `NFCNDEFReaderSession`, not `NFCTagReaderSession`.
            //
            // The tag reader is what the `TAG` entitlement authorises, and
            // `TAG` is what App Store Connect requires on this SDK -- but it
            // silently filters out MIFARE Classic, which is what the tags in
            // hand are. The scan sheet opened and then ignored the tag
            // entirely: no callback, no error, nothing to diagnose.
            //
            // This session reads NDEF from Classic because iOS handles that
            // case itself. It works on the hardware that exists today, at the
            // cost of an entitlement App Store Connect rejects. NTAG213/215/216
            // tags would satisfy both; until there are some, working beats
            // uploadable.
            let session = NFCNDEFReaderSession(
                delegate: self,
                queue: .main,
                invalidateAfterFirstRead: true
            )
            session.alertMessage = "Hold your iPhone near the tag on the bucket."
            self.session = session
            session.begin()
        }
        #else
        throw Failure.unsupported
        #endif
    }

    func cancel() {
        #if canImport(CoreNFC)
        session?.invalidate()
        session = nil
        finish(.failure(CancellationError()))
        #endif
    }

    #if canImport(CoreNFC)
    /// Resumes at most once. `didInvalidateWithError` also fires after a
    /// successful read -- the session ends either way -- and resuming a
    /// continuation twice is a trap, not an error.
    private func finish(_ result: Result<UUID, any Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
    #endif
}

#if canImport(CoreNFC)
extension BucketTagScanner: NFCNDEFReaderSessionDelegate {
    nonisolated func readerSession(
        _ session: NFCNDEFReaderSession,
        didDetectNDEFs messages: [NFCNDEFMessage]
    ) {
        // Parsed before hopping actors so only a `UUID` crosses.
        let sensorID = Self.sensorID(in: messages)

        MainActor.assumeIsolated {
            guard let sensorID else {
                // Names what was actually on the tag. Three different faults
                // used to read as one sentence, which is what made this take
                // guesswork instead of evidence.
                let found = messages
                    .flatMap(\.records)
                    .map { "tnf \($0.typeNameFormat.rawValue)" }
                    .joined(separator: ", ")
                let failure = Failure.unreadable(
                    found.isEmpty
                        ? "That tag is empty."
                        : "That tag holds no sensor ID (\(found))."
                )
                session.invalidate(errorMessage: failure.localizedDescription)
                finish(.failure(failure))
                return
            }

            session.alertMessage = "Bucket detected."
            finish(.success(sensorID))
        }
    }

    nonisolated func readerSession(
        _ session: NFCNDEFReaderSession,
        didInvalidateWithError error: any Error
    ) {
        MainActor.assumeIsolated {
            self.session = nil
            // A user-dismissed sheet is not a fault. Reported as cancellation
            // so the caller stays quiet instead of showing an error for a
            // deliberate action.
            if let readerError = error as? NFCReaderError,
               readerError.code == .readerSessionInvalidationErrorUserCanceled {
                finish(.failure(CancellationError()))
            } else {
                finish(.failure(error))
            }
        }
    }

    private nonisolated static func sensorID(in messages: [NFCNDEFMessage]) -> UUID? {
        for message in messages {
            for record in message.records {
                if let sensorID = payloadText(of: record).flatMap(sensorID(inText:)) {
                    return sensorID
                }
            }
        }
        return nil
    }

    /// The first UUID anywhere in the payload.
    ///
    /// Not `UUID(uuidString:)` on the whole string. A tag written by hand or by
    /// an off-the-shelf writer carries something like
    /// `penyu:sensor:<uuid>` -- readable, and useful to whoever writes it -- and
    /// parsing the whole payload rejected that outright. What identifies the
    /// logger is the UUID; anything wrapped around it is a label.
    nonisolated static func sensorID(inText text: String) -> UUID? {
        let pattern = "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
        guard
            let range = text.range(of: pattern, options: .regularExpression)
        else { return nil }

        return UUID(uuidString: String(text[range]))
    }

    /// The text a record carries, for the formats a writer might reasonably use.
    ///
    /// `.nfcExternal` is what this app writes: namespaced, so a foreign tag is
    /// refused before the database is asked about it. The other two are what an
    /// off-the-shelf writer produces -- a Well-Known Text record, or a
    /// `text/plain` MIME record -- and both are accepted so the first tags can
    /// be written before a provisioning screen exists. Narrower than it looks:
    /// the payload still has to contain a UUID that names a device this account
    /// can see.
    private nonisolated static func payloadText(of record: NFCNDEFPayload) -> String? {
        let raw: String?

        switch record.typeNameFormat {
        case .nfcExternal:
            guard
                String(data: record.type, encoding: .utf8) == BucketTagFormat.recordType
            else { return nil }
            raw = String(data: record.payload, encoding: .utf8)

        case .nfcWellKnown:
            raw = record.wellKnownTypeTextPayload().0

        case .media:
            guard
                let mime = String(data: record.type, encoding: .utf8),
                mime.hasPrefix("text/")
            else { return nil }
            raw = String(data: record.payload, encoding: .utf8)

        default:
            return nil
        }

        return raw?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
#endif
