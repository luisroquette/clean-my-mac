import CryptoKit
import Darwin
import Foundation

public enum BackupVerificationError: LocalizedError {
    case missingDirectory(String)
    case unreadableEntry(String)
    case entrySetMismatch(sourceOnly: [String], destinationOnly: [String])
    case entryTypeMismatch(String)
    case contentMismatch(String)
    case unsupportedEntry(String)
    case rollbackFailed(original: String, staging: String)

    public var errorDescription: String? {
        switch self {
        case let .missingDirectory(path): "Diretório ausente durante a verificação: \(path)"
        case let .unreadableEntry(message): "Entrada ilegível durante a verificação: \(message)"
        case .entrySetMismatch: "A lista de arquivos do backup diverge do original."
        case let .entryTypeMismatch(path): "O tipo da entrada diverge no backup: \(path)"
        case let .contentMismatch(path): "O conteúdo diverge no backup: \(path)"
        case let .unsupportedEntry(path): "Entrada não suportada no backup: \(path)"
        case let .rollbackFailed(original, staging):
            "Falha ao restaurar \(original); cópia recuperável preservada em \(staging)."
        }
    }
}

public enum BackupVerifier {
    public static func copyVerifiedAndStageRemoval(
        source: URL,
        backup: URL,
        removalStaging: URL
    ) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: removalStaging.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.moveItem(at: source, to: removalStaging)
        do {
            try fileManager.createDirectory(
                at: backup.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: removalStaging, to: backup)
            try verifyCopy(source: removalStaging, destination: backup)
        } catch {
            try? fileManager.removeItem(at: backup)
            do {
                try fileManager.moveItem(at: removalStaging, to: source)
            } catch {
                throw BackupVerificationError.rollbackFailed(
                    original: source.path,
                    staging: removalStaging.path
                )
            }
            throw error
        }
    }

    public static func verifyCopy(source: URL, destination: URL) throws {
        let sourceEntries = try entries(in: source)
        let destinationEntries = try entries(in: destination)
        guard sourceEntries.keys == destinationEntries.keys else {
            throw BackupVerificationError.entrySetMismatch(
                sourceOnly: sourceEntries.keys.filter { destinationEntries[$0] == nil }.sorted(),
                destinationOnly: destinationEntries.keys.filter { sourceEntries[$0] == nil }.sorted()
            )
        }

        for relativePath in sourceEntries.keys.sorted() {
            let sourceEntry = sourceEntries[relativePath]!
            let destinationEntry = destinationEntries[relativePath]!
            guard sourceEntry.kind == destinationEntry.kind else {
                throw BackupVerificationError.entryTypeMismatch(relativePath)
            }
            guard sourceEntry.size == destinationEntry.size else {
                throw BackupVerificationError.contentMismatch(relativePath)
            }

            switch sourceEntry.kind {
            case .directory:
                continue
            case .symbolicLink:
                guard sourceEntry.linkDestination == destinationEntry.linkDestination else {
                    throw BackupVerificationError.contentMismatch(relativePath)
                }
            case .file:
                let sourceHash = try sha256(source.appending(path: relativePath))
                let destinationHash = try sha256(destination.appending(path: relativePath))
                guard sourceHash == destinationHash else {
                    throw BackupVerificationError.contentMismatch(relativePath)
                }
            }
        }
    }

    private static func entries(in root: URL) throws -> [String: Entry] {
        let canonicalRoot = try canonicalDirectoryURL(root)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: canonicalRoot.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw BackupVerificationError.missingDirectory(root.path)
        }

        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
        ]
        var traversalError: Error?
        guard let enumerator = FileManager.default.enumerator(
            at: canonicalRoot,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, error in
                traversalError = error
                return false
            }
        ) else {
            throw BackupVerificationError.missingDirectory(root.path)
        }

        var result: [String: Entry] = [:]
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: keys)
            let relativePath = String(url.path.dropFirst(canonicalRoot.path.count + 1))
            if values.isSymbolicLink == true {
                result[relativePath] = Entry(
                    kind: .symbolicLink,
                    size: 0,
                    linkDestination: try FileManager.default.destinationOfSymbolicLink(atPath: url.path)
                )
            } else if values.isDirectory == true {
                result[relativePath] = Entry(kind: .directory, size: 0, linkDestination: nil)
            } else if values.isRegularFile == true {
                result[relativePath] = Entry(
                    kind: .file,
                    size: UInt64(values.fileSize ?? 0),
                    linkDestination: nil
                )
            } else {
                throw BackupVerificationError.unsupportedEntry(relativePath)
            }
        }
        if let traversalError {
            throw BackupVerificationError.unreadableEntry(traversalError.localizedDescription)
        }
        return result
    }

    private static func canonicalDirectoryURL(_ url: URL) throws -> URL {
        guard let pointer = realpath(url.path, nil) else {
            throw BackupVerificationError.missingDirectory(url.path)
        }
        defer { free(pointer) }
        return URL(filePath: String(cString: pointer), directoryHint: .isDirectory)
    }

    private static func sha256(_ url: URL) throws -> SHA256.Digest {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize()
    }

    private struct Entry {
        let kind: EntryKind
        let size: UInt64
        let linkDestination: String?
    }

    private enum EntryKind: Equatable {
        case directory
        case file
        case symbolicLink
    }
}
