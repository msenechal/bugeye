import BugeyeCore
import Foundation
import Testing

@Suite struct CaptureIDTests {
    @Test func canonicalFormIsLowercase() throws {
        let id = try #require(CaptureID(string: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"))
        #expect(id.description == "e621e1f8-c36c-495a-93fc-0c247a3e6e5f")
    }

    @Test func parsingIsCaseInsensitive() {
        #expect(
            CaptureID(string: "e621e1f8-c36c-495a-93fc-0c247a3e6e5f")
                == CaptureID(string: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"))
    }

    @Test func rejectsAnythingThatIsNotAUUID() {
        #expect(CaptureID(string: "") == nil)
        #expect(CaptureID(string: "not-a-uuid") == nil)
        #expect(CaptureID(string: "e621e1f8c36c495a93fc0c247a3e6e5f") == nil)
    }

    @Test func encodesAsOneJSONString() throws {
        let id = try #require(CaptureID(string: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"))
        let json = String(decoding: try JSONEncoder().encode([id]), as: UTF8.self)
        #expect(json == #"["e621e1f8-c36c-495a-93fc-0c247a3e6e5f"]"#)
        #expect(try JSONDecoder().decode([CaptureID].self, from: Data(json.utf8)) == [id])
    }

    @Test func decodingGarbageFails() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([CaptureID].self, from: Data(#"["nope"]"#.utf8))
        }
    }

    @Test func freshIDsDiffer() {
        #expect(CaptureID() != CaptureID())
    }
}
