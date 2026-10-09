import XCTest

@testable import PremiumShotCore

final class M12MigrationTests: XCTestCase {
    func data(_ object: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: object) }
    let v1: [String: Any] = [
        "version": 1, "look": "tide", "shape": "16:9", "space": 20, "radius": 30, "shadow": 70,
    ]

    func testV1MigrationAndFrameRemovalRules() throws {
        for frame in [nil, "none", "window", "browser", "alien"] as [String?] {
            var object = v1
            object["frame"] = frame
            let bytes = try data(object)
            let lenient = Recipe.decodeLenient(bytes)
            XCTAssertEqual(lenient, Recipe(look: .tide, shape: .wide, space: 20, radius: 30, shadow: 70))
            if frame == nil || frame == "none" {
                XCTAssertEqual(try Recipe.decodeStrict(bytes), lenient)
            } else {
                XCTAssertThrowsError(try Recipe.decodeStrict(bytes)) {
                    XCTAssertTrue($0.localizedDescription.contains("Frame was removed"))
                }
            }
        }
        var custom = v1
        custom["look"] = "custom"
        XCTAssertThrowsError(try Recipe.decodeStrict(data(custom))) {
            XCTAssertTrue($0.localizedDescription.contains("look"))
        }
        XCTAssertEqual(Recipe.decodeLenient(try data(custom)).look, .dawn)
    }

    func testV2StrictRequiredHueFieldsLenientClampAndFutureFallback() throws {
        var object = v1
        object["version"] = 2
        object["look"] = "custom"
        object["gradientFrom"] = 360
        object["gradientTo"] = 0
        XCTAssertEqual(try Recipe.decodeStrict(data(object)).gradientFrom, 360)
        for key in ["gradientFrom", "gradientTo"] {
            var missing = object
            missing.removeValue(forKey: key)
            XCTAssertThrowsError(try Recipe.decodeStrict(data(missing))) {
                XCTAssertTrue($0.localizedDescription.contains(key))
            }
        }
        object["gradientFrom"] = -1
        object["gradientTo"] = 999
        XCTAssertThrowsError(try Recipe.decodeStrict(data(object)))
        let clamped = Recipe.decodeLenient(try data(object))
        XCTAssertEqual(clamped.gradientFrom, 0)
        XCTAssertEqual(clamped.gradientTo, 360)
        for version in [0, 3, 99] {
            object["version"] = version
            XCTAssertEqual(Recipe.decodeLenient(try data(object)), .default)
            XCTAssertThrowsError(try Recipe.decodeStrict(data(object))) {
                XCTAssertTrue($0.localizedDescription.contains("versions 1 and 2"))
            }
        }
        let encoded = try Recipe(look: .custom).encoded()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(json["version"] as? Int, 2)
        XCTAssertNil(json["frame"])
        XCTAssertEqual(try Recipe.decodeStrict(encoded), Recipe(look: .custom))
    }
}
