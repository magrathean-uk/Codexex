#if os(macOS)
import AppKit
import SwiftUI

struct SettingsAboutCard: View {
    var body: some View {
        GlassCard(style: .secondary) {
            VStack(alignment: .leading, spacing: 16) {
                Text("About")
                    .font(.headline)

                HStack(alignment: .center, spacing: 14) {
                    Image(nsImage: appIconImage)
                        .renderingMode(.original)
                        .resizable()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.10), radius: 8, y: 2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Codexex")
                            .font(.title3.weight(.semibold))

                        Text("Version \(Bundle.main.codexexVersionString)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text("Menu bar meter for Codex usage.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Button("Terms of Use") {
                        NSWorkspace.shared.open(CodexAppLinks.termsURL)
                    }
                    .buttonStyle(.bordered)

                    Button("Privacy Policy") {
                        NSWorkspace.shared.open(CodexAppLinks.privacyURL)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var appIconImage: NSImage {
        let image = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        image.size = NSSize(width: 256, height: 256)
        image.isTemplate = false
        return image
    }
}
#endif
