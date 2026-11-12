import Foundation
import PDFKit
import UIKit
import UniformTypeIdentifiers

/// A file someone picked to set up their routine from, already read into memory.
public enum RoutineDocument: Sendable, Equatable {
    case pdf(Data)
    case image(Data)
    case text(String)

    /// The file types setup accepts.
    public static let supportedTypes: [UTType] = [.pdf, .image, .plainText, .rtf]

    /// Reads a picked file. Handles security-scoped URLs from the Files picker.
    public init(contentsOf url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let type = UTType(filenameExtension: url.pathExtension),
              let data = try? Data(contentsOf: url) else {
            throw ParsingError.unreadableFile
        }
        if type.conforms(to: .pdf) {
            self = .pdf(data)
        } else if type.conforms(to: .image) {
            self = .image(data)
        } else if type.conforms(to: .rtf) {
            guard let text = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            ).string else { throw ParsingError.unreadableFile }
            self = .text(text)
        } else if type.conforms(to: .text) {
            self = .text(String(decoding: data, as: UTF8.self))
        } else {
            throw ParsingError.unreadableFile
        }
    }
}

extension RoutineParser {
    /// The most PDF pages read from one file; handouts are a few pages at most.
    static let maxPDFPages = 20

    /// Picked files, in order, read as one routine.
    public func parse(fileURLs: [URL]) async throws -> ParsedRoutine {
        let documents = try fileURLs.map(RoutineDocument.init(contentsOf:))
        return try await parse(documents: documents)
    }

    /// Documents, in order, read as one routine.
    public func parse(documents: [RoutineDocument]) async throws -> ParsedRoutine {
        var pages: [[String]] = []
        for document in documents {
            pages += try await self.pages(in: document)
        }
        return try await extract(fromPages: pages)
    }

    /// A document's text, one array of lines per page.
    func pages(in document: RoutineDocument) async throws -> [[String]] {
        switch document {
        case .text(let text):
            return [Self.nonEmptyLines(in: text)]
        case .image(let data):
            guard let image = UIImage(data: data) else { throw ParsingError.unreadableFile }
            return [try await ocr.recognizeLines(in: image)]
        case .pdf(let data):
            guard let pdf = PDFDocument(data: data) else { throw ParsingError.unreadableFile }
            var pages: [[String]] = []
            for index in 0..<min(pdf.pageCount, Self.maxPDFPages) {
                guard let page = pdf.page(at: index) else { continue }
                // Use the page's own text when it has some; scanned pages have
                // none, so read those like a photo.
                let text = Self.nonEmptyLines(in: page.string ?? "")
                if !text.isEmpty {
                    pages.append(text)
                } else {
                    pages.append(try await ocr.recognizeLines(in: Self.render(page)))
                }
            }
            return pages
        }
    }

    static func nonEmptyLines(in text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Renders a PDF page large enough for OCR (longest side 2000 points).
    static func render(_ page: PDFPage) -> UIImage {
        let bounds = page.bounds(for: .mediaBox)
        let longest = max(bounds.width, bounds.height, 1)
        let scale = 2000 / longest
        return page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale),
                              for: .mediaBox)
    }
}
