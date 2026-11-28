import BugeyeCore
import BugeyeTestSupport
import Testing

@Suite struct FixtureContentTests {
    @Test func threeHundredNumberedLines() {
        #expect(FixtureContent.lines.count == 300)
        #expect(FixtureContent.lines.first == "Line 1")
        #expect(FixtureContent.lines.last == "Line 300")
    }

    @Test func controlsMatchTheSpec() {
        #expect(FixtureContent.buttons.count == 3)
        #expect(FixtureContent.checkboxes.count == 2)
        #expect(FixtureContent.swatches.count == 4)
        #expect(Set(FixtureContent.swatches.map(\.color)).count == 4)
    }

    @Test func secretsHaveTheirRealShapes() throws {
        let values = Dictionary(uniqueKeysWithValues: FixtureContent.secrets.map { ($0.label, $0.value) })
        let aws = try #require(values["AWS access key"])
        #expect(aws.hasPrefix("AKIA") && aws.count == 20 && aws.allSatisfy { $0.isUppercase || $0.isNumber })
        let github = try #require(values["GitHub token"])
        #expect(
            github.hasPrefix("ghp_") && github.count == 40
                && github.dropFirst(4).allSatisfy { $0.isLetter || $0.isNumber })
        let email = try #require(values["Email"])
        #expect(email.hasSuffix("@example.invalid"))
        let card = try #require(values["Card number"])
        #expect(luhnValid(card.filter(\.isNumber)))
    }

    /// The card is the public test number: it passes Luhn, so the sweep's card rule finds it.
    func luhnValid(_ digits: String) -> Bool {
        let values = digits.reversed().compactMap { $0.wholeNumberValue }
        let sum = values.enumerated().reduce(0) { total, item in
            let (index, digit) = item
            guard index % 2 == 1 else { return total + digit }
            let doubled = digit * 2
            return total + (doubled > 9 ? doubled - 9 : doubled)
        }
        return values.count == 16 && sum % 10 == 0
    }
}

/// What the Wave 1 Mac batches drive in the fixture app (contracts §4.6).
@Suite struct FixtureWaveOneContentTests {
    @Test func theNewControlsHaveTheirLabels() {
        #expect(FixtureContent.passwordPlaceholder == "Password")
        #expect(FixtureContent.playClickButton == "Play Click")
        #expect(FixtureContent.windowMenu == "Window")
        #expect(FixtureContent.smallWindowItem == "Small Window")
        #expect(FixtureContent.smallWindowTitle == "Bugeye Fixture Small")
        #expect(FixtureContent.smallWindowSize == Size2D(width: 400, height: 300))
    }
}
