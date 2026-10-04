import XCTest
@testable import Flione

/// 封面下載失敗會重試：前兩次失敗（逾時、503），第三次成功
final class ImagePipelineRetryTests: XCTestCase {
    final class FlakyProtocol: URLProtocol {
        nonisolated(unsafe) static var attempts = 0
        nonisolated(unsafe) static var failures: [Int?] = []   // nil = 網路錯誤，數字 = HTTP 狀態碼

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            defer { Self.attempts += 1 }
            if Self.attempts < Self.failures.count {
                if let status = Self.failures[Self.attempts] {
                    client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
                    client?.urlProtocolDidFinishLoading(self)
                } else {
                    client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
                }
                return
            }
            let png = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in NSColor.red.setFill(); rect.fill(); return true }
            let data = NSBitmapImageRep(data: png.tiffRepresentation!)!.representation(using: .png, properties: [:])!
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    private func pipeline() -> (ImagePipeline, URL) {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FlakyProtocol.self]
        let dir = FileManager.default.temporaryDirectory.appending(path: "flione-art-\(UUID().uuidString)")
        return (ImagePipeline(urlProvider: { _, _ in URL(string: "https://example.invalid/cover.png")! }, configuration: config, diskDirectory: dir), dir)
    }

    func testRetriesTransientFailures() async {
        FlakyProtocol.attempts = 0
        FlakyProtocol.failures = [nil, 503]
        let (images, dir) = pipeline()
        defer { try? FileManager.default.removeItem(at: dir) }
        let image = await images.image(ArtworkRef(itemID: "a", tag: "t", blurHash: nil), pixelSize: 64)
        XCTAssertNotNil(image)
        XCTAssertEqual(FlakyProtocol.attempts, 3)
    }

    func testDoesNotRetryNotFound() async {
        FlakyProtocol.attempts = 0
        FlakyProtocol.failures = [404]
        let (images, dir) = pipeline()
        defer { try? FileManager.default.removeItem(at: dir) }
        let image = await images.image(ArtworkRef(itemID: "b", tag: "t", blurHash: nil), pixelSize: 64)
        XCTAssertNil(image)
        XCTAssertEqual(FlakyProtocol.attempts, 1)
    }
}
