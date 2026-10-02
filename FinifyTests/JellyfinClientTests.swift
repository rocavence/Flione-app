import XCTest
@testable import Finify

final class JellyfinClientTests: XCTestCase {
    func testCandidateURLsForBareHostTryDefaultPortFirst() {
        XCTAssertEqual(JellyfinClient.candidateURLs(for: "mediabox").map(\.absoluteString), [
            "http://mediabox:8096", "http://mediabox", "https://mediabox:8920", "https://mediabox",
        ])
    }

    func testCandidateURLsKeepExplicitURL() {
        XCTAssertEqual(JellyfinClient.candidateURLs(for: " http://mediabox:8096/ ").map(\.absoluteString), ["http://mediabox:8096"])
    }

    func testCandidateURLsKeepExplicitPort() {
        XCTAssertEqual(JellyfinClient.candidateURLs(for: "10.0.0.2:9000").map(\.absoluteString), ["http://10.0.0.2:9000", "https://10.0.0.2:9000"])
    }

    func testAuthorizationHeaderIncludesToken() {
        let header = JellyfinClient.authorizationHeader(token: "abc")
        XCTAssertTrue(header.hasPrefix("MediaBrowser Client=\"Finify\""))
        XCTAssertTrue(header.contains("Token=\"abc\""))
    }

    func testDecodesTrackWithSevenDigitFractionalDate() throws {
        let json = """
        {"Items":[{"Id":"t1","Name":"Time","Type":"Audio","Album":"The Dark Side of the Moon","AlbumId":"a1",
        "AlbumArtist":"Pink Floyd","ArtistItems":[{"Name":"Pink Floyd","Id":"ar1"}],"AlbumPrimaryImageTag":"tag1",
        "IndexNumber":3,"ParentIndexNumber":1,"RunTimeTicks":4249000000,"Container":"m4a",
        "DateCreated":"2023-05-01T12:34:56.1234567Z","ImageBlurHashes":{"Primary":{"tag1":"LKO2?U%2Tw=w]~RBVZRi};RPxuwH"}}}],
        "TotalRecordCount":1}
        """.data(using: .utf8)!
        let response = try JellyfinClient.decoder.decode(ItemsResponse.self, from: json)
        let track = response.items[0].toTrack()
        XCTAssertEqual(track.name, "Time")
        XCTAssertEqual(track.artistName, "Pink Floyd")
        XCTAssertEqual(track.duration, 424.9, accuracy: 0.001)
        XCTAssertEqual(track.container, "m4a")
        XCTAssertEqual(track.artwork, ArtworkRef(itemID: "a1", tag: "tag1", blurHash: "LKO2?U%2Tw=w]~RBVZRi};RPxuwH"))
        XCTAssertNotNil(response.items[0].dateCreated)
    }

    func testDecodesAlbumFallsBackToAlbumArtistsList() throws {
        let json = """
        {"Id":"a1","Name":"Discovery","AlbumArtists":[{"Name":"Daft Punk","Id":"dp"}],"ProductionYear":2001,"ImageTags":{"Primary":"p"}}
        """.data(using: .utf8)!
        let album = try JellyfinClient.decoder.decode(BaseItemDTO.self, from: json).toAlbum()
        XCTAssertEqual(album.artistName, "Daft Punk")
        XCTAssertEqual(album.artistID, "dp")
        XCTAssertEqual(album.year, 2001)
        XCTAssertEqual(album.artwork?.tag, "p")
    }

    func testFormattedDuration() {
        XCTAssertEqual(TimeInterval(187).formattedDuration, "3:07")
        XCTAssertEqual(TimeInterval(3765).formattedDuration, "1:02:45")
        XCTAssertEqual(TimeInterval.nan.formattedDuration, "0:00")
    }
}

final class ArtworkTests: XCTestCase {
    func testBlurHashDecodesToRequestedSize() throws {
        let image = try XCTUnwrap(BlurHash.decode("LKO2?U%2Tw=w]~RBVZRi};RPxuwH", width: 16, height: 16))
        XCTAssertEqual(image.width, 16)
        XCTAssertEqual(image.height, 16)
    }

    func testBlurHashRejectsInvalidHash() {
        XCTAssertNil(BlurHash.decode("bad", width: 16, height: 16))
    }

    func testBlurHashAverageColorIsInUnitRange() throws {
        let c = try XCTUnwrap(BlurHash.averageColor("LKO2?U%2Tw=w]~RBVZRi};RPxuwH"))
        for v in [c.r, c.g, c.b] { XCTAssert((0...1).contains(v)) }
    }

    func testImageBucketsRoundUp() {
        XCTAssertEqual(ImagePipeline.bucket(1), 96)
        XCTAssertEqual(ImagePipeline.bucket(296), 320)
        XCTAssertEqual(ImagePipeline.bucket(5000), 1600)
    }

    func testBlurHashDecodeIsFastEnoughForScrolling() {
        // 捲動時每 frame 可能要解碼數十個 placeholder
        measure {
            for _ in 0..<200 { _ = BlurHash.decode("LKO2?U%2Tw=w]~RBVZRi};RPxuwH", width: 16, height: 16) }
        }
    }
}

final class RequestEncodingTests: XCTestCase {
    func testPlusSignIsPercentEncoded() {
        let client = JellyfinClient(serverURL: URL(string: "http://mediabox:8096")!)
        let url = client.url("/Items", query: [URLQueryItem(name: "SearchTerm", value: "C++ & A+B")])
        XCTAssertEqual(url.query, "SearchTerm=C%2B%2B%20%26%20A%2BB")
    }
}
