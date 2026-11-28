import BugeyeCore
import CoreGraphics
import CoreML
import Foundation
import Testing
import Vision

@testable import MacAdapters

// Temporary diagnostic on a throwaway branch: which Vision setups work on the hosted macOS runner.
@Suite struct VisionProbeTests {
    @Test func probe() async throws {
        let drawn = try DrawnText.draw([("let x = foo(bar)", 40, 40)], width: 800, height: 120)
        let image = try #require(PixelBufferImages.cgImage(drawn.image))
        print("PROBE all devices:", MLComputeDevice.allComputeDevices)
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.automaticallyDetectsLanguage = true
        do {
            let out = try await request.perform(on: image)
            print("PROBE new accurate OK:", out.compactMap { $0.topCandidates(1).first?.string })
        } catch { print("PROBE new accurate FAILED:", String(reflecting: error)) }
        var fast = RecognizeTextRequest()
        fast.recognitionLevel = .fast
        do {
            let out = try await fast.perform(on: image)
            print("PROBE new fast OK:", out.compactMap { $0.topCandidates(1).first?.string })
        } catch { print("PROBE new fast FAILED:", String(reflecting: error)) }

        let legacy = VNRecognizeTextRequest()
        legacy.recognitionLevel = .accurate
        legacy.usesLanguageCorrection = false
        do {
            print("PROBE legacy stage devices:", try legacy.supportedComputeStageDevices())
        } catch { print("PROBE legacy stage devices FAILED:", String(reflecting: error)) }
        do {
            try VNImageRequestHandler(cgImage: image).perform([legacy])
            print("PROBE legacy default OK:", legacy.results?.compactMap { $0.topCandidates(1).first?.string } ?? [])
        } catch { print("PROBE legacy default FAILED:", String(reflecting: error)) }
        for device in MLComputeDevice.allComputeDevices {
            let r = VNRecognizeTextRequest()
            r.recognitionLevel = .accurate
            r.setComputeDevice(device, for: .main)
            do {
                try VNImageRequestHandler(cgImage: image).perform([r])
                print("PROBE legacy on", device, "OK:", r.results?.compactMap { $0.topCandidates(1).first?.string } ?? [])
            } catch { print("PROBE legacy on", device, "FAILED:", String(reflecting: error)) }
        }
    }
}
