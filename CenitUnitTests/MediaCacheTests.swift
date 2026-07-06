import XCTest
@testable import Cenit

final class MediaCacheTests: XCTestCase {
    func testStoreThumbThenHasThumb() throws {
        let cache = try MediaCache()
        let id = "MediaCacheTests-\(UUID().uuidString)"
        defer { try? cache.deleteAll() }

        XCTAssertFalse(cache.hasThumb(for: id))
        try cache.storeThumb(Data("fake-jpeg".utf8), for: id)
        XCTAssertTrue(cache.hasThumb(for: id))
    }

    func testDeleteAllClearsCachedThumbs() throws {
        let cache = try MediaCache()
        let id = "MediaCacheTests-\(UUID().uuidString)"
        try cache.storeThumb(Data("fake-jpeg".utf8), for: id)
        XCTAssertTrue(cache.hasThumb(for: id))

        try cache.deleteAll()
        XCTAssertFalse(cache.hasThumb(for: id))
    }

    func testVideoURLIsNilWhenNotCached() throws {
        let cache = try MediaCache()
        XCTAssertNil(cache.videoURL(for: "MediaCacheTests-never-cached"))
    }
}
