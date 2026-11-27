import Foundation
import Testing
@testable import Khisso

/// `box://` links as messages carry them, the same as thaali writes and reads.
struct BoxLinkTests {
    @Test func writesEachSegmentEncodedAndAFolderWithATrailingSlash() {
        #expect(BoxLink(path: "/var/home/dadi/Inbox/2026-11/My Photo (1).jpg", folder: false).href == "box:///var/home/dadi/Inbox/2026-11/My%20Photo%20%281%29.jpg")
        #expect(BoxLink(path: "/var/home/dadi/Docs", folder: true).href == "box:///var/home/dadi/Docs/")
        #expect(BoxLink(path: "/var/home/dadi/Docs/", folder: true).href == "box:///var/home/dadi/Docs/")
    }

    @Test func readsWhatItWrites() {
        for link in [BoxLink(path: "/var/home/dadi/a b/c+d (2).pdf", folder: false), BoxLink(path: "/var/home/dadi/Résumé", folder: true), BoxLink(path: "/", folder: true)] {
            #expect(BoxLink(href: link.href) == link)
        }
    }

    @Test func refusesWhatIsNotAnAbsoluteBoxPath() {
        #expect(BoxLink(href: "https://example.com/a") == nil)
        #expect(BoxLink(href: "box://relative/a") == nil)
        #expect(BoxLink(href: "box:///var/home/dadi/../../etc/passwd") == nil)
        #expect(BoxLink(href: "box:///var/./home") == nil)
        #expect(BoxLink(href: "box:///bad%ZZ") == nil)
    }

    @Test func writesMarkdownWithTheNameAsItsTextAndBracketsEscaped() {
        #expect(BoxLink(path: "/var/home/dadi/a [1].txt", folder: false).markdown == "[a \\[1\\].txt](box:///var/home/dadi/a%20%5B1%5D.txt)")
    }

    @Test func putsUploadsInTheMonthsInboxInLocalTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Detroit"))
        let lateOnTheLastDay = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 23, minute: 30)))
        #expect(BoxLink.inboxFolder(lateOnTheLastDay, calendar: calendar) == "/var/home/dadi/Inbox/2026-10")
        #expect(BoxLink.inboxFolder(lateOnTheLastDay.addingTimeInterval(3_600), calendar: calendar) == "/var/home/dadi/Inbox/2026-11")
    }

    @Test func splitsTheLinksAMessageOpensWithFromTheText() {
        let one = BoxLink(path: "/var/home/dadi/Inbox/2026-11/a.pdf", folder: false)
        let two = BoxLink(path: "/var/home/dadi/Inbox/2026-11/b (2).jpg", folder: false)
        let opening = BoxLink.leading(in: "\(one.markdown)\n\(two.markdown)\nsee these\nand \(one.markdown)")
        #expect(opening.links == [one, two])
        #expect(opening.rest == "see these\nand \(one.markdown)")
        #expect(BoxLink.leading(in: "just words").links.isEmpty)
        #expect(BoxLink.leading(in: one.markdown).rest.isEmpty)
    }

    @Test func keepsBoxLinksWhenWordingMarkdownLinks() {
        let link = BoxLink(path: "/var/home/dadi/a b.pdf", folder: false).markdown
        #expect(LinkFormat.normalize("see \(link) and [x](javascript:alert(1))") == "see \(link) and x")
    }

    @Test func tellsAGonePathFromAFailure() {
        #expect(BoxFiles.isGone(ServiceError(status: 404, type: "not_found", message: "gone")))
        #expect(!BoxFiles.isGone(ServiceError(status: 403, type: "forbidden", message: "no")))
        #expect(!BoxFiles.isGone(URLError(.timedOut)))
    }
}

/// Files go to the Inbox through Nas, and the message carries a link to where each landed.
@MainActor
struct InboxTests {
    private struct Refused: LocalizedError { var errorDescription: String? { "disk full" } }

    private func file(_ name: String) -> DraftFile {
        DraftFile(name: name, mediaType: "application/pdf", url: URL(filePath: "/tmp/\(name)"))
    }

    private let now = Date(timeIntervalSince1970: 1_795_000_000)

    @Test func linksEachUploadedFileThenTheTypedWords() {
        let paths = ["/var/home/dadi/Inbox/2026-11/a.pdf", "/var/home/dadi/Inbox/2026-11/b (2).pdf"]
        #expect(Inbox.message(paths: paths, typed: "  here you go \n") == "[a.pdf](box:///var/home/dadi/Inbox/2026-11/a.pdf)\n[b (2).pdf](box:///var/home/dadi/Inbox/2026-11/b%20%282%29.pdf)\nhere you go")
        #expect(Inbox.message(paths: paths.dropLast(), typed: " ") == "[a.pdf](box:///var/home/dadi/Inbox/2026-11/a.pdf)")
        #expect(Inbox.message(paths: [], typed: "hi") == "hi")
    }

    @Test func uploadsToTheMonthsFolderAndLinksWhereNasPutThem() async throws {
        var files = [file("a.pdf"), file("b.pdf")]
        var folders: [String] = []
        let paths = try await Inbox.upload(files, now: now, put: { folder, file in
            folders.append(folder)
            return NasUploaded(path: "\(folder)/\(file.name == "b.pdf" ? "b (2).pdf" : file.name)", name: file.name, size: 1)
        }, report: { files.setUpload($0, $1) })
        let folder = BoxLink.inboxFolder(now)
        #expect(folders == [folder, folder])
        #expect(paths == ["\(folder)/a.pdf", "\(folder)/b (2).pdf"])
        #expect(files.map(\.upload) == [.uploaded(path: paths[0]), .uploaded(path: paths[1])])
    }

    @Test func aFailureTriesEveryFileKeepsEachStateAndThrows() async {
        var files = [file("a.pdf"), file("b.pdf"), file("c.pdf")]
        var tried: [String] = []
        var thrown: UploadFailed?
        do {
            _ = try await Inbox.upload(files, now: now, put: { folder, file in
                tried.append(file.name)
                if file.name == "b.pdf" { throw Refused() }
                return NasUploaded(path: "\(folder)/\(file.name)", name: file.name, size: 1)
            }, report: { files.setUpload($0, $1) })
        } catch let error as UploadFailed {
            thrown = error
        } catch {
            Issue.record("unexpected \(error)")
        }
        #expect(thrown == UploadFailed(failed: 1))
        #expect(tried == ["a.pdf", "b.pdf", "c.pdf"])
        #expect(files.map(\.upload) == [.uploaded(path: "\(BoxLink.inboxFolder(now))/a.pdf"), .failed("disk full"), .uploaded(path: "\(BoxLink.inboxFolder(now))/c.pdf")])
        #expect(UploadFailed(failed: 1).localizedDescription == "1 file did not upload")
        #expect(UploadFailed(failed: 2).localizedDescription == "2 files did not upload")
    }

    @Test func aRetrySkipsFilesAlreadyOnTheBox() async throws {
        let folder = BoxLink.inboxFolder(now)
        var files = [file("a.pdf"), file("b.pdf")]
        files[0].upload = .uploaded(path: "\(folder)/a.pdf")
        files[1].upload = .failed("disk full")
        var tried: [String] = []
        let paths = try await Inbox.upload(files, now: now, put: { folder, file in
            tried.append(file.name)
            return NasUploaded(path: "\(folder)/\(file.name)", name: file.name, size: 1)
        }, report: { files.setUpload($0, $1) })
        #expect(tried == ["b.pdf"])
        #expect(paths == ["\(folder)/a.pdf", "\(folder)/b.pdf"])
    }

    @Test func aStagedFileAloneIsAMessageToSend() {
        #expect(ThreadDraft.canSend(text: "", files: 1, sending: false))
        let draft = ThreadDraft()
        draft.text = "words"
        draft.files = [file("a.pdf")]
        #expect(draft.canSend)
    }
}

/// What Nas answers for a file, read as the app's types.
struct NasFileDecodingTests {
    @Test func decodesAnEntryWithOrWithoutFractionalSeconds() throws {
        for modified in ["2026-11-26T15:38:54Z", "2026-11-26T15:38:54.123456789Z"] {
            let json = #"{"name":"a.pdf","path":"/var/home/dadi/a.pdf","kind":"file","size":10,"modified":"\#(modified)","media_type":"application/pdf"}"#
            let entry = try ServiceJSON.decoder.decode(NasFileEntry.self, from: Data(json.utf8))
            #expect(entry.kind == .file && entry.mediaType == "application/pdf" && entry.size == 10)
        }
    }

    @Test func decodesWhereAnUploadLanded() throws {
        let uploaded = try ServiceJSON.decoder.decode(NasUploaded.self, from: Data(#"{"path":"/var/home/dadi/Inbox/2026-11/a (2).pdf","name":"a (2).pdf","size":4}"#.utf8))
        #expect(uploaded.path.hasSuffix("a (2).pdf") && uploaded.size == 4)
    }
}
