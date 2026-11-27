#if DEBUG
    import BugeyeFeatures
    import Testing

    @Suite struct DebugCommandHandlerTests {
        let handler = DebugCommandHandler(moduleIDs: ["general"])

        @Test func pingAnswersPong() {
            #expect(handler.respond(to: "ping\n") == "pong")
        }

        @Test func modulesListsTheRegisteredIDs() {
            #expect(handler.respond(to: "modules") == "general")
            #expect(
                DebugCommandHandler(moduleIDs: ["general", "capture"]).respond(to: " modules\r\n") == "general,capture")
        }

        @Test func unknownCommandsAreErrors() {
            #expect(handler.respond(to: "rm -rf /") == "error: unknown command rm -rf /")
            #expect(handler.respond(to: "") == "error: unknown command ")
        }
    }
#endif
