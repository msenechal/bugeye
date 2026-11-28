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
        var request = RecognizeTextRequest()
        print("PROBE main devices:", request.supportedComputeDevices(for: .main))
        print("PROBE current main device:", String(describing: request.computeDevice(for: .main)))
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.automaticallyDetectsLanguage = true
        do {
            let out = try await request.perform(on: image)
            print("PROBE accurate default OK:", out.compactMap { $0.topCandidates(1).first?.string })
        } catch { print("PROBE accurate default FAILED:", String(reflecting: error)) }
        for device in request.supportedComputeDevices(for: .main) {
            var r = request
            r.setComputeDevice(device, for: .main)
            do {
                let out = try await r.perform(on: image)
                print("PROBE accurate on", device, "OK:", out.compactMap { $0.topCandidates(1).first?.string })
            } catch { print("PROBE accurate on", device, "FAILED:", String(reflecting: error)) }
        }
        var fast = RecognizeTextRequest()
        fast.recognitionLevel = .fast
        do {
            let out = try await fast.perform(on: image)
            print("PROBE fast default OK:", out.compactMap { $0.topCandidates(1).first?.string })
        } catch { print("PROBE fast default FAILED:", String(reflecting: error)) }
        let legacy = VNRecognizeTextRequest()
        legacy.recognitionLevel = .accurate
        legacy.usesCPUOnly = true
        do {
            try VNImageRequestHandler(cgImage: image).perform([legacy])
            print("PROBE legacy cpu OK:", legacy.results?.compactMap { $0.topCandidates(1).first?.string } ?? [])
        } catch { print("PROBE legacy cpu FAILED:", String(reflecting: error)) }
        let legacyDefault = VNRecognizeTextRequest()
        do {
            try VNImageRequestHandler(cgImage: image).perform([legacyDefault])
            print("PROBE legacy default OK:", legacyDefault.results?.compactMap { $0.topCandidates(1).first?.string } ?? [])
        } catch { print("PROBE legacy default FAILED:", String(reflecting: error)) }
    }
}
