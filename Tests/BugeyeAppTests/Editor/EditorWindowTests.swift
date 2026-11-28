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
            prompts: prompts)
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
        do {
            let editor = try await f.open(try f.makeCapture())
            // type in it, as the first build's leak needed
            editor.selectTool(.text)
            if case .beginTextEntry(let entry) = editor.controller.mouseDown(
                at: Point2D(x: 4, y: 4), clickCount: 1, shift: false)
            {
                editor.canvas.showTextView(entry)
                editor.canvas.textView?.string = "Hi"
                editor.canvas.commitText()
            }
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
}
