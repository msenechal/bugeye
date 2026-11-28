#if DEBUG
    import BugeyeCore
    import BugeyeFeatures
    import BugeyeTestSupport
    import Foundation
    import Testing

    @MainActor @Suite struct DebugCommandHandlerTests {
        let router = ActionRouter()
        let settings = InMemorySettingsStore()
        let bus = CaptureEventBus()

        func handler(
            moduleIDs: [String] = ["general"],
            registered: @escaping @MainActor (String) -> (@MainActor (String) -> String)? = { _ in nil }
        ) -> DebugCommandHandler {
            DebugCommandHandler(
                moduleIDs: moduleIDs, router: router, settings: settings, bus: bus, registered: registered)
        }

        func publish(_ change: CaptureChange, _ name: String, origin: String = "capture") -> CaptureID {
            let id = CaptureID()
            bus.publish(
                CaptureEvent(
                    change: change,
                    item: CaptureItem(
                        id: id, fileURL: URL(fileURLWithPath: "/tmp/\(name)"), isSaved: false, kind: .screenshot,
                        createdAt: Date(), pixelsPerPoint: 2),
                    origin: origin))
            return id
        }

        @Test func pingAnswersPong() {
            #expect(handler().respond(to: "ping\n") == "pong")
        }

        @Test func modulesListsTheRegisteredIDs() {
            #expect(handler().respond(to: "modules") == "general")
            #expect(handler(moduleIDs: ["general", "capture"]).respond(to: " modules\r\n") == "general,capture")
        }

        @Test func unknownCommandsAreErrors() {
            #expect(handler().respond(to: "rm -rf /") == "error: unknown command rm -rf /")
            #expect(handler().respond(to: "") == "error: unknown command ")
        }

        @Test func hotkeyAndMenuGoThroughTheRouter() {
            var log: [String] = []
            router.onHotkey("capture.area") { log.append("hotkey") }
            router.onMenuItem("capture.window") { log.append("menu") }
            let h = handler()
            #expect(h.respond(to: "hotkey capture.area") == "ok")
            #expect(h.respond(to: "menu capture.window") == "ok")
            #expect(h.respond(to: "hotkey nope") == "error: no hotkey nope")
            #expect(h.respond(to: "menu nope") == "error: no menu item nope")
            #expect(h.respond(to: "hotkey") == "error: usage: hotkey <id>")
            #expect(h.respond(to: "menu") == "error: usage: menu <id>")
            #expect(log == ["hotkey", "menu"])
        }

        @Test func getPrintsTheStoredValueAsJSON() {
            settings.setValue(.string("say \"hi\""), forKey: "s")
            settings.setValue(.bool(true), forKey: "b")
            settings.setValue(.int(3), forKey: "i")
            settings.setValue(.double(2), forKey: "d")
            let h = handler()
            #expect(h.respond(to: "get s") == #""say \"hi\"""#)
            #expect(h.respond(to: "get b") == "true")
            #expect(h.respond(to: "get i") == "3")
            #expect(h.respond(to: "get d") == "2.0")
            #expect(h.respond(to: "get missing") == "null")
            #expect(h.respond(to: "get") == "error: usage: get <key>")
        }

        @Test func setStoresEachKindOfValue() {
            let h = handler()
            #expect(h.respond(to: #"set capture.hotkey.area "⌃⌥A""#) == "ok")
            #expect(settings.value(forKey: "capture.hotkey.area") == .string("⌃⌥A"))
            #expect(h.respond(to: "set capture.saveToFolder false") == "ok")
            #expect(settings.value(forKey: "capture.saveToFolder") == .bool(false))
            #expect(h.respond(to: "set n 12") == "ok")
            #expect(settings.value(forKey: "n") == .int(12))
            #expect(h.respond(to: "set x 0.5") == "ok")
            #expect(settings.value(forKey: "x") == .double(0.5))
            #expect(h.respond(to: "set n null") == "ok")
            #expect(settings.value(forKey: "n") == nil)
            #expect(h.respond(to: "set n {oops") == "error: invalid value {oops")
            #expect(h.respond(to: "set n") == "error: usage: set <key> <json>")
            #expect(h.respond(to: "get capture.hotkey.area") == #""⌃⌥A""#)
        }

        @Test func eventsListsTheLast50OldestFirst() throws {
            let h = handler()
            #expect(h.respond(to: "events") == "[]")
            let first = publish(.created, "a.png")
            #expect(
                h.respond(to: "events")
                    == #"[{"change":"created","file":"a.png","id":"\#(first)","origin":"capture"}]"#)
            for n in 0..<60 { _ = publish(.edited, "\(n).png", origin: "editor") }
            let reply = h.respond(to: "events")
            let decoded = try JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [[String: String]]
            #expect(decoded?.count == 50)
            #expect(decoded?.first?["file"] == "10.png")
            #expect(decoded?.last?["file"] == "59.png")
            #expect(!reply.contains("\n"))
        }

        @Test func registeredCommandsGetTheRestOfTheLine() {
            let stack: @MainActor (String) -> String = { "stack[\($0)]" }
            let h = handler(registered: { prefix in prefix == "quickAccess.stack" ? stack : nil })
            #expect(h.respond(to: "quickAccess.stack") == "stack[]")
            #expect(h.respond(to: "quickAccess.stack  top  3 ") == "stack[top  3]")
            #expect(h.respond(to: "recording.state") == "error: unknown command recording.state")
        }

        @Test func builtInCommandsAreListed() {
            #expect(
                DebugCommandHandler.builtInCommands == ["ping", "modules", "hotkey", "menu", "get", "set", "events"])
        }
    }
#endif
