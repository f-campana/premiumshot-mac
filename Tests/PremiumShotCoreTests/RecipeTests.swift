import XCTest
@testable import PremiumShotCore

final class RecipeTests: XCTestCase {
    func json(_ s: String) -> Data { Data(s.utf8) }
    let good = #"{ "version": 1, "look": "tide", "shape": "16:9", "space": 40, "radius": 20, "shadow": 70, "frame": "none" }"#

    func testStrictDecodeAcceptsAValidRecipe() throws {
        let r = try Recipe.decodeStrict(json(good))
        XCTAssertEqual(r.look, .tide); XCTAssertEqual(r.shape, .wide)
        XCTAssertEqual([r.space, r.radius, r.shadow], [40, 20, 70]); XCTAssertTrue(r.redactions.isEmpty)
    }

    func testRoundTripThroughJSON() throws {
        var r = Recipe.default; r.look = .graphite; r.shape = .link; r.space = 12
        XCTAssertEqual(try Recipe.decodeStrict(r.encoded()), r)
    }

    func testStrictDecodeRejectsBadInputWithAMessage() {
        let cases: [(String, String)] = [
            (#"{ "version": 3, "look": "dawn", "shape": "fit", "space": 1, "radius": 1, "shadow": 1, "frame": "none" }"#, "version"),
            (#"{ "version": 1, "look": "neon", "shape": "fit", "space": 1, "radius": 1, "shadow": 1, "frame": "none" }"#, "look"),
            (#"{ "version": 1, "look": "dawn", "shape": "3:2", "space": 1, "radius": 1, "shadow": 1, "frame": "none" }"#, "shape"),
            (#"{ "version": 1, "look": "dawn", "shape": "fit", "space": 101, "radius": 1, "shadow": 1, "frame": "none" }"#, "space"),
            (#"{ "version": 1, "look": "dawn", "shape": "fit", "space": -1, "radius": 1, "shadow": 1, "frame": "none" }"#, "space"),
            (#"{ "version": 1, "look": "dawn", "shape": "fit", "space": 1, "radius": 1, "frame": "none" }"#, "shadow"),
            (#"{ "version": 1, "look": "dawn", "shape": "fit", "space": 1, "radius": 1, "shadow": 1, "frame": "none", "redactions": [{"x":0,"y":0,"width":1,"height":1}] }"#, "redactions"),
            ("not json", ""),
        ]
        for (text, mention) in cases {
            XCTAssertThrowsError(try Recipe.decodeStrict(json(text)), text) { error in
                guard case PremiumShotError.invalidRecipe(let message) = error else { return XCTFail("wrong error \(error)") }
                if !mention.isEmpty { XCTAssertTrue(message.contains(mention), "\"\(message)\" should mention \(mention)") }
                XCTAssertEqual((error as? PremiumShotError)?.exitCode, 2)
            }
        }
    }

    func testLenientDecodeClampsAndFallsBack() {
        let r = Recipe.decodeLenient(json(#"{ "version": 1, "look": "neon", "shape": "16:9", "space": 500, "radius": -5, "shadow": 30, "frame": "none" }"#))
        XCTAssertEqual(r.look, .dawn)                       // unknown id replaced
        XCTAssertEqual(r.shape, .wide)
        XCTAssertEqual([r.space, r.radius, r.shadow], [100, 0, 30])   // clamped
        XCTAssertEqual(Recipe.decodeLenient(json("garbage")), .default)
        XCTAssertEqual(Recipe.decodeLenient(json(#"{ "version": 9, "look": "tide" }"#)), .default)   // newer version ignored
    }
}
