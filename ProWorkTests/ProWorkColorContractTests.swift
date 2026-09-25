import XCTest
@testable import ProWork

final class ProWorkColorContractTests: XCTestCase {
    func test_pickerColors_areSupportedByColorResolver() {
        for option in ProWorkColorPickerOptions.canonical {
            XCTAssertNotNil(
                ProWorkColors.Named(rawValue: option.id),
                "Picker color '\(option.id)' must be supported by ProWorkColors"
            )
        }
    }
}
