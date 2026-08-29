import Foundation

public enum CleanupPolicy {
    private static let excludedDirectoryNames = Set([
        ".git", ".claude", ".codex", ".npm", ".npm-global", ".9router", ".vscode",
        ".Trash", "Library", "Arquivos Públicos", "Arquivos Públicos",
    ])

    public static func pathsOverlap(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalized(lhs)
        let right = normalized(rhs)
        return left == right || left.hasPrefix(right + "/") || right.hasPrefix(left + "/")
    }

    public static func artifactScanRoots(homePath: String) -> [String] {
        ["Projects", "Projetos", "Developer", "Code"]
            .map { URL(filePath: homePath).appending(path: $0).path }
            + ["/private/tmp"]
    }

    public static func isProtected(_ path: String, protectedPaths: [String]) -> Bool {
        isInsideWarningDefault(path) || protectedPaths.contains { pathsOverlap(path, $0) }
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

    public static func shouldExcludeDirectory(named name: String) -> Bool {
        excludedDirectoryNames.contains(name) || name.hasPrefix("claude-")
    }

    public static var excludedDirectoryPatterns: [String] {
        excludedDirectoryNames.sorted() + ["claude-*"]
    }

    public static func isProjectActive(_ gitRoot: String, activeDirectories: [String]) -> Bool {
        activeDirectories.contains { pathsOverlap($0, gitRoot) }
    }

    private static func normalized(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func isInsideWarningDefault(_ path: String) -> Bool {
        let components = normalized(path).split(separator: "/")
        return components.indices.dropLast().contains {
            components[$0] == "Warning" && components[components.index(after: $0)] == "Default"
        }
    }
}
