import AppKit
import Foundation
import UniformTypeIdentifiers

enum AttachmentManagerError: LocalizedError {
    case unsupportedFile(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFile(let fileName):
            return "仅支持上传 PDF 和截图/图片：\(fileName)"
        }
    }
}

enum AttachmentManager {
    static func appSupportDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("TravelExpenseDesk", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func dataFileURL() throws -> URL {
        try appSupportDirectory().appendingPathComponent("projects.json")
    }

    static func attachmentDirectory(for projectID: UUID) throws -> URL {
        let directory = try appSupportDirectory()
            .appendingPathComponent("Attachments", isDirectory: true)
            .appendingPathComponent(projectID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func copyAttachments(from urls: [URL], projectID: UUID) throws -> [AttachmentItem] {
        let directory = try attachmentDirectory(for: projectID)
        return try urls.map { url in
            let fileName = uniqueFileName(for: url.lastPathComponent, in: directory)
            let destination = directory.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: url, to: destination)
            let attachmentKind = kind(for: destination)
            guard attachmentKind == .pdf || attachmentKind == .image else {
                try? FileManager.default.removeItem(at: destination)
                throw AttachmentManagerError.unsupportedFile(url.lastPathComponent)
            }
            return AttachmentItem(
                fileName: fileName,
                storedPath: destination.path,
                originalPath: url.path,
                kind: attachmentKind
            )
        }
    }

    static func remove(_ attachment: AttachmentItem) {
        try? FileManager.default.removeItem(atPath: attachment.storedPath)
    }

    private static func uniqueFileName(for originalName: String, in directory: URL) -> String {
        let originalURL = URL(fileURLWithPath: originalName)
        let baseName = originalURL.deletingPathExtension().lastPathComponent
        let ext = originalURL.pathExtension
        var candidate = originalName
        var index = 1
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            let suffix = ext.isEmpty ? "" : ".\(ext)"
            candidate = "\(baseName)-\(index)\(suffix)"
            index += 1
        }
        return candidate
    }

    private static func kind(for url: URL) -> AttachmentKind {
        guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
            return .file
        }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .image) { return .image }
        return .file
    }
}
