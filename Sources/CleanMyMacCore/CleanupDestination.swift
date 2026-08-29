import Foundation

public enum CleanupDestination: String, CaseIterable, Sendable {
    case trash
    case deleteBatch
    case externalBackup
}

public enum CleanupDestinationPolicy {
    public static func isExternalBackupPath(_ path: String) -> Bool {
        let normalized = URL(filePath: path).standardizedFileURL.path
        return normalized.hasPrefix("/Volumes/") && normalized != "/Volumes"
    }
}
