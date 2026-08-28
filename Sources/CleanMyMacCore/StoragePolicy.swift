import Darwin
import Foundation

public enum StorageLevel: String, Sendable {
    case normal
    case warning
    case critical
}

public struct StorageSnapshot: Equatable, Sendable {
    public let totalBytes: UInt64
    public let availableBytes: UInt64

    public init(totalBytes: UInt64, availableBytes: UInt64) {
        self.totalBytes = totalBytes
        self.availableBytes = min(availableBytes, totalBytes)
    }

    public var usedBytes: UInt64 { totalBytes - availableBytes }
    public var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }
    public var usedPercent: Int { Int((usedFraction * 100).rounded()) }
}

public enum StoragePolicy {
    public static let warningThreshold = 0.75
    public static let cleanupThreshold = 0.78
    public static let hardLimit = 0.80
    public static let warningResetThreshold = 0.73
    public static let cleanupCooldown: TimeInterval = 15 * 60

    public static func level(for usedFraction: Double) -> StorageLevel {
        if usedFraction >= cleanupThreshold { return .critical }
        if usedFraction >= warningThreshold { return .warning }
        return .normal
    }

    public static func shouldResetWarning(for usedFraction: Double) -> Bool {
        usedFraction < warningResetThreshold
    }

    public static func shouldRunAutomaticCleanup(
        usedFraction: Double,
        enabled: Bool,
        isCleaning: Bool,
        lastCleanupAt: Date?,
        now: Date = Date()
    ) -> Bool {
        guard enabled, !isCleaning, usedFraction >= cleanupThreshold else { return false }
        guard let lastCleanupAt else { return true }
        return now.timeIntervalSince(lastCleanupAt) >= cleanupCooldown
    }
}

public enum StorageReader {
    public static func read(path: String = "/System/Volumes/Data") throws -> StorageSnapshot {
        var statistics = statfs()
        guard statfs(path, &statistics) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        let blockSize = UInt64(statistics.f_bsize)
        return StorageSnapshot(
            totalBytes: UInt64(statistics.f_blocks) * blockSize,
            availableBytes: UInt64(statistics.f_bavail) * blockSize
        )
    }
}
