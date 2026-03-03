#if os(macOS)
import Foundation

/// Installs .prompt syntax highlighting into Xcode's SourceModel framework.
/// Requires Xcode.app in /Applications and admin privileges (prompts via osascript).
enum XcodePromptIntegration {

    private static let installedVersionKey = "MetalCaster.XcodePromptSpec.version"
    private static let currentVersion = 1

    static var isInstalled: Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: specDestination) && fm.fileExists(atPath: metaDestination)
    }

    static var needsUpdate: Bool {
        let stored = UserDefaults.standard.integer(forKey: installedVersionKey)
        return stored < currentVersion
    }

    static var shouldPrompt: Bool {
        !isInstalled || needsUpdate
    }

    /// Attempts to install the spec files into Xcode with admin privileges.
    /// Returns nil on success or an error message on failure.
    @discardableResult
    static func install() -> String? {
        let fm = FileManager.default

        guard fm.fileExists(atPath: xcodeApp) else {
            return "Xcode.app not found at \(xcodeApp)"
        }

        let tmpSpec = NSTemporaryDirectory() + "MCPrompt.xclangspec"
        let tmpMeta = NSTemporaryDirectory() + "Xcode.SourceCodeLanguage.MCPrompt.plist"

        do {
            try xclangspecContent.write(toFile: tmpSpec, atomically: true, encoding: .utf8)
            try metadataPlistContent.write(toFile: tmpMeta, atomically: true, encoding: .utf8)
        } catch {
            return "Failed to write temp files: \(error.localizedDescription)"
        }

        let script = """
        do shell script "cp '\(tmpSpec)' '\(specDestination)' && cp '\(tmpMeta)' '\(metaDestination)'" with administrator privileges
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let pipe = Pipe()
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return "Failed to run installer: \(error.localizedDescription)"
        }

        if process.terminationStatus != 0 {
            let errData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errMsg = String(data: errData, encoding: .utf8) ?? "unknown error"
            return "Installation failed (exit \(process.terminationStatus)): \(errMsg)"
        }

        UserDefaults.standard.set(currentVersion, forKey: installedVersionKey)

        try? fm.removeItem(atPath: tmpSpec)
        try? fm.removeItem(atPath: tmpMeta)

        return nil
    }

    // MARK: - Paths

    private static let xcodeApp = "/Applications/Xcode.app"

    private static let specDestination =
        "\(xcodeApp)/Contents/SharedFrameworks/SourceModel.framework/Versions/A/Resources/LanguageSpecifications/MCPrompt.xclangspec"

    private static let metaDestination =
        "\(xcodeApp)/Contents/SharedFrameworks/SourceModel.framework/Versions/A/Resources/LanguageMetadata/Xcode.SourceCodeLanguage.MCPrompt.plist"

    // MARK: - Embedded Spec Content

    private static let xclangspecContent = """
    // MetalCaster Prompt Script — Xcode Syntax Coloring

    (

        {
            Identifier = "xcode.lang.mcprompt.comment.singleline";
            Syntax = {
                Start = "//";
                End = "\\n";
                IncludeRules = (
                    "xcode.lang.url",
                    "xcode.lang.url.mail",
                    "xcode.lang.comment.mark",
                );
                Type = "xcode.syntax.comment";
            };
        },

        {
            Identifier = "xcode.lang.mcprompt.header";
            Syntax = {
                Start = "---";
                End = "---";
                Type = "xcode.syntax.preprocessor";
            };
        },

        {
            Identifier = "xcode.lang.mcprompt.bracket";
            Syntax = {
                Start = "[";
                End = "]";
                Recursive = YES;
                Type = "xcode.syntax.string";
            };
        },

        {
            Identifier = "xcode.lang.mcprompt.identifier";
            Syntax = {
                StartChars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";
                Chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -";
                Words = (
                    "Name",
                    "Initial State",
                    "Per-Frame Behavior",
                    "Public Interface",
                );
                Type = "xcode.syntax.keyword";
                AltType = "xcode.syntax.plain";
            };
        },

        {
            Identifier = "xcode.lang.mcprompt.lexer";
            Syntax = {
                IncludeRules = (
                    "xcode.lang.mcprompt.comment.singleline",
                    "xcode.lang.mcprompt.header",
                    "xcode.lang.mcprompt.bracket",
                    "xcode.lang.mcprompt.identifier",
                );
            };
        },

        {
            Identifier = "xcode.lang.mcprompt";
            Description = "MetalCaster Prompt Script";
            BasedOn = "xcode.lang.simpleColoring";
            IncludeInMenu = YES;
            Name = "MetalCaster Prompt";
            Syntax = {
                Tokenizer = "xcode.lang.mcprompt.lexer";
                IncludeRules = (
                    "xcode.lang.mcprompt.bracket",
                );
                Type = "xcode.syntax.plain";
            };
        },

    )
    """

    private static let metadataPlistContent = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>commentSyntaxes</key>
        <array>
            <dict>
                <key>prefix</key>
                <string>//</string>
            </dict>
        </array>
        <key>conformsToLanguageIdentifiers</key>
        <array>
            <string>Xcode.SourceCodeLanguage.Generic</string>
        </array>
        <key>fileDataTypeIdentifiers</key>
        <array>
            <string>dyn.ah62d4rv4ge81a6xtrz2hk</string>
        </array>
        <key>identifier</key>
        <string>Xcode.SourceCodeLanguage.MCPrompt</string>
        <key>isHidden</key>
        <false/>
        <key>languageName</key>
        <string>MetalCaster Prompt</string>
        <key>languageSpecification</key>
        <string>xcode.lang.mcprompt</string>
        <key>supportsIndentation</key>
        <false/>
        <key>allowWhitespaceTrimming</key>
        <true/>
        <key>requiresHardTabs</key>
        <false/>
    </dict>
    </plist>
    """
}
#endif
