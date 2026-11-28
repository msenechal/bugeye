import AppKit
import BugeyeCore
import BugeyeFeatures
import BugeyeTestSupport
import EditorCore
import Foundation
import MacAdapters
import Testing

@testable import BugeyeApp

/// Prompts that answer from scripts and record what they were asked.
@MainActor
final class ScriptedPrompts: EditorPrompts {
    var saveAnswers: [SaveAnswer] = []
    var goneAnswers: [Bool] = []
    var urls: [URL?] = []
    var asked: [String] = []

    func askToSave(name: String, window: NSWindow?) async -> SaveAnswer {
        asked.append("ask \(name)")
        return saveAnswers.isEmpty ? .cancel : saveAnswers.removeFirst()
    }
    func goneAlert(name: String, window: NSWindow?) async -> Bool {
        asked.append("gone \(name)")
        return goneAnswers.isEmpty ? false : goneAnswers.removeFirst()
    }
    func saveAsURL(name: String, folder: URL, window: NSWindow?) async -> URL? {
        asked.append("panel \(name) in \(folder.lastPathComponent)")
        return urls.isEmpty ? nil : urls.removeFirst()
    }
    func saveFailed(name: String, message: String, window: NSWindow?) async {
        asked.append("failed \(name): \(message)")
    }
}

@MainActor
final class EditorAppFixture {
    let dir: TempDirectory
    let bus = CaptureEventBus()
    let metadata = XattrMetadataStore()
    let prompts = ScriptedPrompts()
    let clipboard = FakeClipboard()
    let notifier = FakeNotifier()
    var policies: [ActivationPolicy] = []
    var activations = 0
    var documentWindows: DocumentWindows!
    var manager: EditorManager!

    init() throws {
        _ = NSApplication.shared
        dir = try TempDirectory("editor-app")
        documentWindows = DocumentWindows(apply: { [unowned self] in self.policies.append($0) })
        let folder = dir.url
        manager = EditorManager(
            environment: EditorEnvironment(
                bus: bus, documentWindows: documentWindows, writer: CaptureFileWriter(metadata: metadata),
                clipboard: clipboard, notifier: notifier, saveFolder: { folder },
                dragFolder: dir.url.appendingPathComponent("Bugeye-Drag", isDirectory: true)),
            prompts: prompts, activate: { [unowned self] in self.activations += 1 })
    }

    /// A 40 × 30 PNG with an ID and a provenance attribute, announced on the bus.
    func makeCapture(_ name: String = "Shot.png") throws -> CaptureItem {
        let image = try EditorExportTests.topRedBottomBlue(40, 30)
        let url = dir.file(name)
        try #require(EditorImages.encodePNG(image)).write(to: url)
        let item = CaptureItem(
            id: CaptureID(), fileURL: url, isSaved: true, kind: .screenshot, createdAt: Date(), pixelsPerPoint: 2)
        try metadata.setValue(Data(item.id.description.utf8), CaptureFileWriter.identityAttribute, at: url)
        try metadata.setValue(Data("{\"app\":\"Arc\"}".utf8), "dev.msenechal.bugeye.provenance", at: url)
        bus.publish(CaptureEvent(change: .created, item: item, origin: "capture"))
        return item
    }

    func open(_ item: CaptureItem) async throws -> EditorWindowController {
        await manager.sessions.open(item)
        return try #require(manager.windows[item.id])
    }

    func edit(_ window: EditorWindowController) {
        window.controller.document.apply {
            $0.annotations.append(Annotation(shape: .step(center: Point2D(x: 5, y: 5))))
        }
        window.canvasDidChange()
    }

    func id(_ url: URL) throws -> String? {
        try metadata.value(CaptureFileWriter.identityAttribute, at: url).map { String(decoding: $0, as: UTF8.self) }
    }

    func tearDown() {
        for window in manager.windows.values { window.window.close() }
        dir.remove()
    }
}

@MainActor @Suite(.serialized) struct EditorWindowTests {
    @Test func openingShowsATitledWindowAndTheDockRoundTrips() async throws {
        let f = try EditorAppFixture()
        defer { f.tearDown() }
        let item = try f.makeCapture()
        let editor = try await f.open(item)
        #expect(editor.window.title == "Shot.png")
        #expect(editor.window.representedURL == item.fileURL)
        #expect(editor.window.isVisible)
        #expect(editor.window.tabbingMode == .disallowed)
        #expect(editor.window.contentMinSize == NSSize(width: 640, height: 420))
        #expect(editor.controller.tool == .arrow)
        #expect(f.policies == [.regular])
        #expect(f.activations == 1)
        _ = try await f.open(try f.makeCapture("Second.png"))
        #expect(f.activations == 2)  // every editor activates Bugeye, not only the first (final review C, I2)
        f.manager.windows.values.filter { $0 !== editor }.forEach { $0.window.close() }
        editor.window.close()
        #expect(f.policies == [.regular, .accessory])
        #expect(f.manager.windows.isEmpty)
    }

    @Test func saveKeepsTheIDAndTheOtherAttributes() async throws {
        let f = try EditorAppFixture()
        defer { f.tearDown() }
        let item = try f.makeCapture()
        let editor = try await f.open(item)
        f.edit(editor)
        #expect(editor.window.isDocumentEdited)
        #expect(await f.manager.sessions.save(item.id) == .saved)
        #expect(try f.id(item.fileURL) == item.id.description)
        #expect(
            try f.metadata.value("dev.msenechal.bugeye.provenance", at: item.fileURL) == Data("{\"app\":\"Arc\"}".utf8))
        let decoded = try EditorImages.decode(item.fileURL).get()
        #expect(decoded.width == 40 && decoded.height == 30)
        editor.canvasDidChange()
        #expect(!editor.window.isDocumentEdited)
    }

    @Test func saveAsGetsANewID() async throws {
        let f = try EditorAppFixture()
        defer { f.tearDown() }
        let item = try f.makeCapture()
        let editor = try await f.open(item)
        f.edit(editor)
        let copy = f.dir.file("Copy.png")
        f.prompts.urls = [copy]
        #expect(await f.manager.sessions.saveAs(item.id) == .saved)
        #expect(f.prompts.asked == ["panel Shot.png in \(f.dir.url.lastPathComponent)"])
        let newID = try #require(try f.id(copy))
        #expect(newID != item.id.description)
        #expect(try f.metadata.value("dev.msenechal.bugeye.provenance", at: copy) == Data("{\"app\":\"Arc\"}".utf8))
        #expect(editor.controller.document.isDirty)
    }

    @Test func theMenuIsValidatedForTheCanvas() async throws {
        let f = try EditorAppFixture()
        defer { f.tearDown() }
        let editor = try await f.open(try f.makeCapture())
        func enabled(_ action: Selector) -> Bool {
            editor.validateMenuItem(NSMenuItem(title: "", action: action, keyEquivalent: ""))
        }
        #expect(!enabled(NSSelectorFromString("cut:")))
        #expect(!enabled(NSSelectorFromString("paste:")))
        #expect(!enabled(NSSelectorFromString("selectAll:")))
        #expect(enabled(NSSelectorFromString("copy:")))
        #expect(!enabled(NSSelectorFromString("delete:")))
        #expect(!enabled(NSSelectorFromString("undo:")))
        #expect(enabled(NSSelectorFromString("saveDocument:")))
        #expect(enabled(NSSelectorFromString("zoomToFit:")))
        f.edit(editor)
        #expect(enabled(NSSelectorFromString("undo:")))
        editor.selectTool(.select)
        _ = editor.controller.mouseDown(at: Point2D(x: 5, y: 5), clickCount: 1, shift: false)
        editor.controller.mouseUp(at: Point2D(x: 5, y: 5), shift: false)
        #expect(enabled(NSSelectorFromString("delete:")))
        editor.delete(nil)
        #expect(editor.controller.document.state.annotations.isEmpty)
    }

    @Test func zoomCommandsStepAndClamp() async throws {
        let f = try EditorAppFixture()
        defer { f.tearDown() }
        let editor = try await f.open(try f.makeCapture())
        editor.zoomToActualSize(nil)
        #expect(editor.scrollView.magnification == 1)
        #expect(editor.controller.zoom == 1)
        editor.zoomIn(nil)
        #expect(abs(editor.scrollView.magnification - 1.25) < 0.001)
        #expect(abs(editor.controller.zoom - 1.25) < 0.001)
        for _ in 0..<20 { editor.zoomIn(nil) }
        #expect(abs(editor.scrollView.magnification - 8) < 0.001)
    }

    @Test func closingADirtyEditorAsksAndCancelKeepsItOpen() async throws {
        let f = try EditorAppFixture()
        defer { f.tearDown() }
        let editor = try await f.open(try f.makeCapture())
        f.edit(editor)
        f.prompts.saveAnswers = [.cancel]
        #expect(editor.windowShouldClose(editor.window) == false)
        for _ in 0..<200 where f.prompts.asked.isEmpty { await Task.yield() }
        #expect(f.prompts.asked == ["ask Shot.png"])
        for _ in 0..<50 { await Task.yield() }
        #expect(editor.window.isVisible)
        f.prompts.saveAnswers = [.dontSave]
        _ = editor.windowShouldClose(editor.window)
        for _ in 0..<500 where editor.window.isVisible { await Task.yield() }
        #expect(!editor.window.isVisible)
        #expect(f.manager.windows.isEmpty)
    }

    @Test func aCleanEditorClosesWithoutAsking() async throws {
        let f = try EditorAppFixture()
        defer { f.tearDown() }
        let editor = try await f.open(try f.makeCapture())
        #expect(editor.windowShouldClose(editor.window))
        #expect(f.prompts.asked.isEmpty)
    }

    @Test func quitAsksEveryDirtyEditorAndCancelStops() async throws {
        let f = try EditorAppFixture()
        defer { f.tearDown() }
        let a = try await f.open(try f.makeCapture("A.png"))
        let b = try await f.open(try f.makeCapture("B.png"))
        f.edit(a)
        f.edit(b)
        f.prompts.saveAnswers = [.dontSave, .cancel]
        #expect(await f.manager.sessions.shouldTerminate() == false)
        #expect(f.prompts.asked == ["ask A.png", "ask B.png"])
        f.prompts.saveAnswers = [.save, .dontSave]
        #expect(await f.manager.sessions.shouldTerminate() == true)
        #expect(try f.id(a.session.item.fileURL) == a.session.id.description)
    }

    @Test func aMissingFileOpensNothingAndPostsTheNotice() async throws {
        let f = try EditorAppFixture()
        defer { f.tearDown() }
        let item = try f.makeCapture()
        try FileManager.default.removeItem(at: item.fileURL)
        await f.manager.sessions.open(item)
        #expect(f.manager.windows.isEmpty)
        #expect(
            f.notifier.posts == [
                FakeNotifier.Post(title: "Couldn't open capture", body: "Shot.png is missing or unreadable.")
            ])
    }

    @Test func typedTextIsCommittedBeforeASave() async throws {
        let f = try EditorAppFixture()
        defer { f.tearDown() }
        let item = try f.makeCapture()
        let editor = try await f.open(item)
        editor.selectTool(.text)
        let result = editor.controller.mouseDown(at: Point2D(x: 4, y: 4), clickCount: 1, shift: false)
        guard case .beginTextEntry(let entry) = result else {
            Issue.record("no text entry")
            return
        }
        editor.canvas.showTextView(entry)
        editor.canvas.textView?.string = "Hi"
        #expect(editor.canvas.isEditingText)
        #expect(await f.manager.sessions.save(item.id) == .saved)
        #expect(!editor.canvas.isEditingText)
        #expect(editor.controller.document.state.annotations.count == 1)
    }

    @Test func aClosedEditorItsWindowAndItsCanvasAreFreed() async throws {
        let f = try EditorAppFixture()
        defer { f.tearDown() }
        weak var weakEditor: EditorWindowController?
        weak var weakWindow: NSWindow?
        weak var weakCanvas: EditorCanvasView?
        // The first build's canvas leak needed typing while another editor window was open (design/03 §3).
        _ = try await f.open(try f.makeCapture("Other.png"))
        do {
            let editor = try await f.open(try f.makeCapture())
            editor.selectTool(.text)
            let result = editor.controller.mouseDown(at: Point2D(x: 4, y: 4), clickCount: 1, shift: false)
            guard case .beginTextEntry(let entry) = result else {
                Issue.record("no text entry")
                return
            }
            editor.canvas.showTextView(entry)
            editor.canvas.textView?.string = "Hi"
            editor.canvas.commitText()
            weakEditor = editor
            weakWindow = editor.window
            weakCanvas = editor.canvas
            editor.controller.document.markSaved(editor.controller.document.state)
            editor.window.close()
        }
        for _ in 0..<30 where weakEditor != nil || weakWindow != nil || weakCanvas != nil {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(weakEditor == nil)
        #expect(weakWindow == nil)
        #expect(weakCanvas == nil)
    }

    // MARK: Final review C

    @Test func undoAndRedoThroughTheResponderChainReachTheDocument() async throws {
        let f = try EditorAppFixture()
        defer { f.tearDown() }
        let editor = try await f.open(try f.makeCapture())
        f.edit(editor)
        let undo = NSSelectorFromString("undo:")
        var responder: NSResponder? = editor.canvas
        while let current = responder, !current.responds(to: undo) { responder = current.nextResponder }
        #expect(responder === editor.canvas)
        #expect(editor.canvas.validateMenuItem(NSMenuItem(title: "", action: undo, keyEquivalent: "")))
        #expect(editor.canvas.tryToPerform(undo, with: nil))
        #expect(editor.controller.document.state.annotations.isEmpty)
        #expect(editor.canvas.tryToPerform(NSSelectorFromString("redo:"), with: nil))
        #expect(editor.controller.document.state.annotations.count == 1)
    }

    func startTyping(_ editor: EditorWindowController) throws -> NSTextView {
        editor.selectTool(.text)
        let result = editor.controller.mouseDown(at: Point2D(x: 4, y: 4), clickCount: 1, shift: false)
        guard case .beginTextEntry(let entry) = result else { throw FakeFailure() }
        editor.canvas.showTextView(entry)
        return try #require(editor.canvas.textView)
    }

    @Test func returnCommitsAndGivesTheCanvasItsFocusBack() async throws {
        let f = try EditorAppFixture()
        defer { f.tearDown() }
        let editor = try await f.open(try f.makeCapture())
        let text = try startTyping(editor)
        #expect(editor.window.firstResponder === text)
        text.string = "Hi"
        #expect(editor.canvas.textView(text, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        #expect(!editor.canvas.isEditingText)
        #expect(editor.window.firstResponder === editor.canvas)
        #expect(editor.controller.document.state.annotations.count == 1)
    }

    @Test func escapeCancelsAndOptionReturnAddsALine() async throws {
        let f = try EditorAppFixture()
        defer { f.tearDown() }
        let editor = try await f.open(try f.makeCapture())
        let text = try startTyping(editor)
        text.string = "one"
        text.setSelectedRange(NSRange(location: 3, length: 0))
        #expect(editor.canvas.textView(text, doCommandBy: #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:))))
        #expect(text.string == "one\n")
        #expect(editor.canvas.isEditingText)
        #expect(editor.canvas.undoManager(for: text) !== editor.window.undoManager)
        #expect(editor.canvas.textView(text, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        #expect(!editor.canvas.isEditingText)
        #expect(editor.window.firstResponder === editor.canvas)
        #expect(editor.controller.document.state.annotations.isEmpty)
    }

    @Test func theBaseIsRasterisedOnlyWhenItsListChanges() async throws {
        let f = try EditorAppFixture()
        defer { f.tearDown() }
        let editor = try await f.open(try f.makeCapture())
        let canvas = editor.canvas
        _ = canvas.baseImage(for: canvas.currentLists().base)
        let count = canvas.baseRenderCount
        _ = canvas.baseImage(for: canvas.currentLists().base)
        #expect(canvas.baseRenderCount == count)
        editor.selectTool(.rectangle)
        _ = editor.controller.mouseDown(at: Point2D(x: 2, y: 2), clickCount: 1, shift: false)
        editor.controller.mouseDragged(to: Point2D(x: 20, y: 20), shift: false)
        _ = canvas.baseImage(for: canvas.currentLists().base)
        #expect(canvas.baseRenderCount == count)  // the draft is drawn live, not in the base
        editor.controller.mouseUp(at: Point2D(x: 20, y: 20), shift: false)
        _ = canvas.baseImage(for: canvas.currentLists().base)
        #expect(canvas.baseRenderCount == count + 1)
    }

    @Test func pinchAndSmartMagnifyReachTheControllerThroughTheClipView() async throws {
        let f = try EditorAppFixture()
        defer { f.tearDown() }
        let editor = try await f.open(try f.makeCapture())
        editor.scrollView.magnification = 2
        #expect(editor.controller.zoom == 2)
    }

    @Test func openingZoomsToFitAfterLayout() async throws {
        let f = try EditorAppFixture()
        defer { f.tearDown() }
        let editor = try await f.open(try f.makeCapture())
        #expect(editor.scrollView.magnification == 1)  // a 20 × 15 pt canvas fits at 100 %
    }

    @Test func aSecondCloseWhileThePromptIsUpAsksOnce() async throws {
        let f = try EditorAppFixture()
        defer { f.tearDown() }
        let editor = try await f.open(try f.makeCapture())
        f.edit(editor)
        f.prompts.saveAnswers = [.cancel, .cancel]
        #expect(!editor.windowShouldClose(editor.window))
        #expect(!editor.windowShouldClose(editor.window))
        for _ in 0..<200 { await Task.yield() }
        #expect(f.prompts.asked == ["ask Shot.png"])
        #expect(editor.window.isVisible)
    }

    @Test func aSaveFromTheClosePromptClearsTheEditedDot() async throws {
        let f = try EditorAppFixture()
        defer { f.tearDown() }
        let editor = try await f.open(try f.makeCapture())
        f.edit(editor)
        #expect(editor.window.isDocumentEdited)
        f.prompts.saveAnswers = [.save, .cancel]
        _ = try await f.open(try f.makeCapture("Other.png"))
        f.edit(try #require(f.manager.windows.values.first { $0 !== editor }))
        #expect(await f.manager.sessions.shouldTerminate() == false)
        #expect(!editor.window.isDocumentEdited)
    }

    @Test func theRenderFailureMessageIsTheSettledString() {
        #expect(EditorImages.ExportFailed().localizedDescription == "The image couldn't be rendered.")
    }

    @Test func aLateExportFromAnEarlierPressNeverBecomesTheDraggedFile() async throws {
        _ = NSApplication.shared
        var gates: [CheckedContinuation<Void, Never>] = []
        var calls = 0
        let handle = EditorDragHandleView(writeFile: {
            calls += 1
            let n = calls
            if n == 1 { await withCheckedContinuation { gates.append($0) } }
            return URL(fileURLWithPath: "/tmp/drag-\(n).png")
        })
        handle.beginPress()  // slow export
        while gates.isEmpty { await Task.yield() }
        handle.endPress()
        handle.beginPress()  // fast export
        for _ in 0..<100 where handle.ready == nil { await Task.yield() }
        #expect(handle.ready?.lastPathComponent == "drag-2.png")
        gates.removeFirst().resume()
        for _ in 0..<100 { await Task.yield() }
        #expect(handle.ready?.lastPathComponent == "drag-2.png")
        handle.endPress()
        #expect(handle.ready == nil)
    }
}
