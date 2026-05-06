import AppKit
import Foundation

/// Operation subclass that guarantees its continuation is resumed
/// even when cancelled, unlike `BlockOperation` whose execution blocks
/// are skipped entirely for cancelled operations.
final class ArtworkLoadOperation: Operation, @unchecked Sendable {
    private let continuation: CheckedContinuation<NSImage?, Never>
    private let work: () -> NSImage?

    init(continuation: CheckedContinuation<NSImage?, Never>, work: @escaping () -> NSImage?) {
        self.continuation = continuation
        self.work = work
        super.init()
    }

    override func main() {
        continuation.resume(returning: isCancelled ? nil : work())
    }
}

extension OperationQueue {
    /// Enqueues a render and resumes its continuation when complete.
    /// Cancelling the awaiting task cancels the queued operation; cancelled
    /// operations resume with `nil` without rendering.
    func renderArtwork(_ work: @escaping () -> NSImage?) async -> NSImage? {
        final class Holder: @unchecked Sendable {
            var operation: ArtworkLoadOperation?
        }
        let holder = Holder()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let operation = ArtworkLoadOperation(continuation: continuation, work: work)
                holder.operation = operation
                self.addOperation(operation)
            }
        } onCancel: {
            holder.operation?.cancel()
        }
    }
}
