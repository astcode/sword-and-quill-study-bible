import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import UIKit

// MARK: - Portable .sqstudy Lesson Package (AirDrop, Files, Clickable Link & Classroom QR Code)

public struct StudyShareTrailItem: Codable, Hashable, Sendable {
    public let k: String      // StudyTrailKind.rawValue
    public let t: String      // title
    public let d: String?     // detail (omitted when empty for compact QR)
    public let b: Int?        // bookId
    public let c: Int?        // chapter
    public let v: Int?        // verse
    public let r: String?     // refKey (e.g. Strong's ID)

    public init(k: String, t: String, d: String?, b: Int?, c: Int?, v: Int?, r: String?) {
        self.k = k
        self.t = t
        self.d = (d?.isEmpty == false) ? d : nil
        self.b = b
        self.c = c
        self.v = v
        self.r = (r?.isEmpty == false) ? r : nil
    }
}

public struct StudyShareMarginNote: Codable, Hashable, Sendable {
    public let b: Int
    public let c: Int
    public let v: Int?
    public let n: String
}

public struct StudySharePackage: Codable, Hashable, Identifiable, Sendable {
    public var id: String { "\(name)-\(startBookId)-\(startChapter)-\(entries.count)" }
    public let v: Int
    public let name: String
    public let author: String?
    public let startBookId: Int
    public let startChapter: Int
    public let startVerse: Int?
    public let summary: String?
    public let entries: [StudyShareTrailItem]
    public let marginNotes: [StudyShareMarginNote]?

    public init(
        v: Int = 1,
        name: String,
        author: String?,
        startBookId: Int,
        startChapter: Int,
        startVerse: Int?,
        summary: String?,
        entries: [StudyShareTrailItem],
        marginNotes: [StudyShareMarginNote]?
    ) {
        self.v = v
        self.name = name
        self.author = (author?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? author?.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        self.startBookId = startBookId
        self.startChapter = startChapter
        self.startVerse = startVerse
        self.summary = (summary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? summary?.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        self.entries = entries
        self.marginNotes = (marginNotes?.isEmpty == false) ? marginNotes : nil
    }
}

public enum StudyPackageCodec {
    public static let urlScheme = "swordandquill"
    public static let maxQRPayloadBytes = 1900

    public static func buildPackage(
        study: StudySession,
        author: String?,
        trail: [StudyTrailEntry],
        marginLinks: [StudyMarginLink],
        includeMarginNotes: Bool
    ) -> StudySharePackage {
        // Store in chronological order (oldest -> newest) so students follow the teacher's trail in order
        let ordered = trail.reversed().map { e in
            StudyShareTrailItem(
                k: e.kind.rawValue,
                t: e.title,
                d: e.detail,
                b: e.bookId,
                c: e.chapter,
                v: e.verse,
                r: e.refKey
            )
        }
        let notes: [StudyShareMarginNote]? = includeMarginNotes
            ? marginLinks.map { StudyShareMarginNote(b: $0.bookId, c: $0.chapter, v: $0.verse, n: $0.noteText) }
            : nil
        return StudySharePackage(
            name: study.name,
            author: author,
            startBookId: study.startBookId,
            startChapter: study.startChapter,
            startVerse: study.startVerse,
            summary: study.summaryNote,
            entries: ordered,
            marginNotes: notes
        )
    }

    // MARK: - .sqstudy File Export

    public static func exportFile(package: StudySharePackage) -> URL? {
        let safe = package.name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let fileName = (safe.isEmpty ? "Study-Lesson" : safe) + ".sqstudy"
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: dest)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(package) else { return nil }
        do {
            try data.write(to: dest, options: .atomic)
            return dest
        } catch {
            return nil
        }
    }

    // MARK: - Clickable Link & Classroom QR Code (zlib + base64url, Zero Server)

    public static func makeShareURL(package: StudySharePackage, compactForQR: Bool = false) -> (url: URL, wasTrimmedForQR: Bool)? {
        func encodeURL(_ pkg: StudySharePackage) -> (URL, Int)? {
            guard let json = try? JSONEncoder().encode(pkg),
                  let compressed = try? (json as NSData).compressed(using: .zlib) as Data else { return nil }
            let b64 = compressed.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
            let urlStr = "\(urlScheme)://study?d=\(b64)"
            guard let url = URL(string: urlStr) else { return nil }
            return (url, urlStr.utf8.count)
        }

        if let (fullURL, size) = encodeURL(package) {
            if !compactForQR || size <= maxQRPayloadBytes {
                return (fullURL, false)
            }
        }

        // Compact fallback so large studies still produce a crisp, fast-scanning classroom QR code
        let trimmedEntries = package.entries.prefix(24).map { e in
            StudyShareTrailItem(
                k: e.k,
                t: e.t,
                d: e.d.map { String($0.prefix(48)) },
                b: e.b,
                c: e.c,
                v: e.v,
                r: e.r
            )
        }
        let compactPkg = StudySharePackage(
            name: package.name,
            author: package.author,
            startBookId: package.startBookId,
            startChapter: package.startChapter,
            startVerse: package.startVerse,
            summary: package.summary.map { String($0.prefix(160)) },
            entries: Array(trimmedEntries),
            marginNotes: nil
        )
        if let (url, _) = encodeURL(compactPkg) {
            return (url, true)
        }
        return nil
    }

    public static func generateQRImage(from text: String) -> UIImage? {
        guard let data = text.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scale = 10.0
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    // MARK: - Decode Incoming URL or .sqstudy File

    public static func decode(from url: URL) -> StudySharePackage? {
        if url.scheme?.lowercased() == urlScheme {
            guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let dVal = comps.queryItems?.first(where: { $0.name == "d" })?.value,
                  !dVal.isEmpty else { return nil }
            var b64 = dVal
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
            let rem = b64.count % 4
            if rem > 0 { b64 += String(repeating: "=", count: 4 - rem) }
            guard let compressed = Data(base64Encoded: b64),
                  let raw = try? (compressed as NSData).decompressed(using: .zlib) as Data,
                  let pkg = try? JSONDecoder().decode(StudySharePackage.self, from: raw) else {
                return nil
            }
            return pkg
        }

        // File URL (.sqstudy or .json from AirDrop / Mail / Files)
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let pkg = try? JSONDecoder().decode(StudySharePackage.self, from: data) else {
            return nil
        }
        return pkg
    }
}
