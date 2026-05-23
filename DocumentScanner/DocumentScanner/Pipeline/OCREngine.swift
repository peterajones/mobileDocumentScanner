@preconcurrency import Vision
import UIKit

/// A single OCR result: the recognized string plus its bounding box on the
/// source image, expressed in Vision's normalized coordinates (0…1 with
/// origin bottom-left, y-up).
///
/// PDFAssembler uses the bounding box to position the invisible text layer
/// over the visible content, so that search highlights align with the
/// scanned text.
struct OCRObservation: Sendable, Equatable {
    let string: String
    let boundingBox: CGRect
}

protocol OCRProviding: Sendable {
    func recognizeText(in image: UIImage) async throws -> [OCRObservation]
}

enum OCREngineError: Error {
    case invalidImage
}

struct OCREngine: OCRProviding {

    /// Recognize text in the supplied image. Returns one `OCRObservation` per
    /// `VNRecognizedTextObservation`'s top candidate, in Vision's natural reading order.
    ///
    /// - Throws: `OCREngineError.invalidImage` if the image has no CGImage backing.
    ///   Other failures bubble up as the underlying error from Vision (typically the
    ///   `com.apple.Vision` error domain — recognizable via `(error as NSError).domain`).
    func recognizeText(in image: UIImage) async throws -> [OCRObservation] {
        guard let cgImage = image.cgImage else { throw OCREngineError.invalidImage }

        return try await withCheckedThrowingContinuation { continuation in
            // VNRequest's completion handler fires for both success and error, but
            // VNImageRequestHandler.perform can also throw — and on some failure modes
            // both callbacks fire with the same error. The guard ensures the continuation
            // is resumed exactly once regardless of which path wins.
            let lock = NSLock()
            var hasResumed = false
            func tryResume(_ result: Result<[OCRObservation], Error>) {
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
                let mapped: [OCRObservation] = observations.compactMap { obs in
                    guard let top = obs.topCandidates(1).first else { return nil }
                    return OCRObservation(string: top.string, boundingBox: obs.boundingBox)
                }
                tryResume(.success(mapped))
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
