import Foundation

public enum CleanupPolicy {
    public static func pathsOverlap(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalized(lhs)
        let right = normalized(rhs)
        return left == right || left.hasPrefix(right + "/") || right.hasPrefix(left + "/")
    }

    public static func isProtected(_ path: String, protectedPaths: [String]) -> Bool {
        protectedPaths.contains { pathsOverlap(path, $0) }
    }

    public static func isEligibleArtifact(
        name: String,
        sizeKiB: Int,
        isSymbolicLink: Bool,
        minimumKiB: Int
    ) -> Bool {
        !isSymbolicLink
            && (name == "node_modules" || name == ".next")
            && sizeKiB >= minimumKiB
    }

    private static func normalized(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
