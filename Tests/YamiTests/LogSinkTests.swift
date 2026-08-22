import Foundation
import Testing
@testable import Yami

/// LogSink turns a byte stream into the one line worth showing in a 280pt
/// popover. The stream arrives in arbitrary chunks, so line reassembly is the
/// part most likely to be wrong — and it is the part never exercised by hand.
@Suite("LogSink")
struct LogSinkTests {
    private func makeSink() -> (LogSink, URL) {
        let url = URL(filePath: NSTemporaryDirectory())
            .appending(path: "yami-log-\(UUID().uuidString).log")
        return (LogSink(url: url), url)
    }

    private func line(_ level: String, _ message: String) -> String {
        "time=\"2026-08-21T16:00:00-07:00\" level=\(level) msg=\"\(message)\"\n"
    }

    @Test("reassembles a line split across two writes")
    func reassemblesSplitLine() {
        let (sink, url) = makeSink()
        defer { sink.close(); try? FileManager.default.removeItem(at: url) }

        let whole = line("fatal", "listen tcp 127.0.0.1:7890: bind: address already in use")
        let split = whole.index(whole.startIndex, offsetBy: 40)
        sink.write(Data(whole[..<split].utf8))
        sink.write(Data(whole[split...].utf8))

        #expect(sink.lastError() == "listen tcp 127.0.0.1:7890: bind: address already in use")
    }

    @Test("holds back a line that has not ended yet")
    func withholdsIncompleteLine() {
        let (sink, url) = makeSink()
        defer { sink.close(); try? FileManager.default.removeItem(at: url) }

        sink.write(Data("time=\"x\" level=error msg=\"half a mes".utf8))
        #expect(sink.lastError() == nil)
    }

    /// The failure cause is what the user needs, and mihomo logs plenty of
    /// chatter after it.
    @Test("prefers an error over later noise")
    func prefersErrorOverNoise() {
        let (sink, url) = makeSink()
        defer { sink.close(); try? FileManager.default.removeItem(at: url) }

        sink.write(Data(line("error", "the actual problem").utf8))
        sink.write(Data(line("info", "unrelated chatter").utf8))
        sink.write(Data(line("info", "more chatter").utf8))

        #expect(sink.lastError() == "the actual problem")
    }

    @Test("treats fatal the same as error")
    func prefersFatal() {
        let (sink, url) = makeSink()
        defer { sink.close(); try? FileManager.default.removeItem(at: url) }

        sink.write(Data(line("fatal", "could not start").utf8))
        sink.write(Data(line("info", "chatter").utf8))

        #expect(sink.lastError() == "could not start")
    }

    @Test("falls back to the last line when nothing failed")
    func fallsBackToLastLine() {
        let (sink, url) = makeSink()
        defer { sink.close(); try? FileManager.default.removeItem(at: url) }

        sink.write(Data(line("info", "first").utf8))
        sink.write(Data(line("info", "second").utf8))

        #expect(sink.lastError() == "second")
    }

    @Test("returns a non-mihomo line unchanged")
    func passesThroughPlainText() {
        let (sink, url) = makeSink()
        defer { sink.close(); try? FileManager.default.removeItem(at: url) }

        sink.write(Data("dyld: Library not loaded\n".utf8))
        #expect(sink.lastError() == "dyld: Library not loaded")
    }

    @Test("keeps only the tail of a long stream")
    func evictsOldLines() {
        let (sink, url) = makeSink()
        defer { sink.close(); try? FileManager.default.removeItem(at: url) }

        // An error older than the ring must fall out rather than being reported
        // forever after the core recovered.
        sink.write(Data(line("error", "ancient history").utf8))
        for index in 0..<40 {
            sink.write(Data(line("info", "line \(index)").utf8))
        }

        #expect(sink.lastError() == "line 39")
    }

    @Test("blank lines never become the reported error")
    func ignoresBlankLines() {
        let (sink, url) = makeSink()
        defer { sink.close(); try? FileManager.default.removeItem(at: url) }

        sink.write(Data(line("info", "real line").utf8))
        sink.write(Data("\n   \n\n".utf8))

        #expect(sink.lastError() == "real line")
    }
}
