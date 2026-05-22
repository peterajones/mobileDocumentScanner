import Vision
import UIKit

protocol OCRProviding: Sendable {
    func recognizeText(in image: UIImage) async throws -> [String]
}

enum OCREngineError: Error {
    case invalidImage
}

struct OCREngine: OCRProviding {

    /// Recognize text in the supplied image. Returns one string per
    /// `VNRecognizedTextObservation`'s top candidate, in Vision's natural reading order.
    ///
    /// - Throws: `OCREngineError.invalidImage` if the image has no CGImage backing.
    ///   Other failures bubble up as the underlying error from Vision (typically the
    ///   `com.apple.Vision` error domain — recognizable via `(error as NSError).domain`).
    func recognizeText(in image: UIImage) async throws -> [String] {
        guard let cgImage = image.cgImage else { throw OCREngineError.invalidImage }

        return try await withCheckedThrowingContinuation { continuation in
            // VNRequest's completion handler fires for both success and error, but
            // VNImageRequestHandler.perform can also throw — and on some failure modes
            // both callbacks fire with the same error. The guard ensures the continuation
            // is resumed exactly once regardless of which path wins.
            let lock = NSLock()
            var hasResumed = false
            func tryResume(_ result: Result<[String], Error>) {
                lock.lock()
                defer { lock.unlock() }
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(with: result)
            }

            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    tryResume(.failure(error))
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let strings = observations.compactMap { $0.topCandidates(1).first?.string }
                tryResume(.success(strings))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    tryResume(.failure(error))
                }
            }
        }
    }
}
