import Foundation
import PackagePlugin

/// Compiles app sources into a target as the Android stage does: each file listed in the
/// target's `staged-sources.txt` (paths relative to the repository root) is copied into the
/// build with every rule of `android/substitutions.txt` applied, so `@Model` classes carry the
/// `@Observable` the stage adds and a test exercises the code the Android app runs.
@main
struct StageSources: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard let target = target as? SourceModuleTarget else { return [] }
        let directory = target.directoryURL
        let repository = directory.appending(path: "../../../..").standardizedFileURL
        let list = directory.appending(path: "staged-sources.txt")
        let substitutions = repository.appending(path: "android/substitutions.txt")
        let script = directory.appending(path: "stage_file.py")
        let paths = try String(contentsOf: list, encoding: .utf8)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        return paths.map { path in
            let input = repository.appending(path: path)
            let output = context.pluginWorkDirectoryURL.appending(path: input.lastPathComponent)
            return .buildCommand(
                displayName: "Staging \(path)",
                executable: URL(fileURLWithPath: "/usr/bin/python3"),
                arguments: [script.path, substitutions.path, input.path, output.path],
                inputFiles: [script, substitutions, input, list],
                outputFiles: [output],
            )
        }
    }
}
