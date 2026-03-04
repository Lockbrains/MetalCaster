import SwiftUI
import MetalCasterAsset

/// Reusable asset picker that shows assets from a specific category with search.
/// Use this anywhere an inspector field needs to reference a project asset by name.
///
///     MCAssetPicker(
///         label: "Audio File",
///         category: .audio,
///         extensions: ["wav", "mp3", "aac"],
///         selection: $audioFile
///     )
struct MCAssetPicker: View {
    let label: String
    let category: AssetCategory
    var extensions: Set<String>? = nil
    @Binding var selection: String
    @Environment(EditorState.self) private var state

    @State private var showPopover = false
    @State private var search = ""

    private var assets: [AssetEntry] {
        let all = state.assetDatabase.allFiles(in: category)
        let filtered: [AssetEntry]
        if let exts = extensions {
            filtered = all.filter { exts.contains($0.fileExtension.lowercased()) }
        } else {
            filtered = all
        }
        if search.isEmpty { return filtered }
        let q = search.lowercased()
        return filtered.filter {
            $0.name.lowercased().contains(q) || $0.fileExtension.lowercased().contains(q)
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textSecondary)
                .frame(width: 70, alignment: .leading)

            Button {
                showPopover.toggle()
            } label: {
                HStack(spacing: 4) {
                    Text(selection.isEmpty ? "None" : selection)
                        .font(MCTheme.fontCaption)
                        .foregroundStyle(selection.isEmpty ? MCTheme.textTertiary : MCTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8))
                        .foregroundStyle(MCTheme.textTertiary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(MCTheme.inputBackground)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(MCTheme.inputBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                popoverContent
            }
        }
    }

    private var popoverContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(MCTheme.textTertiary)
                TextField("Search \(category.directoryName)…", text: $search)
                    .textFieldStyle(.plain)
                    .font(MCTheme.fontCaption)
                    .foregroundStyle(MCTheme.textPrimary)
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(MCTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider().background(MCTheme.panelBorder)

            if selection.isEmpty {
                EmptyView()
            } else {
                Button {
                    selection = ""
                    showPopover = false
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9))
                            .foregroundStyle(MCTheme.statusRed)
                        Text("Clear Selection")
                            .font(MCTheme.fontCaption)
                            .foregroundStyle(MCTheme.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(AssetPickerRowStyle())

                Divider().background(MCTheme.panelBorder)
            }

            ScrollView {
                let items = assets
                if items.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16, weight: .thin))
                            .foregroundStyle(MCTheme.textTertiary)
                        Text("No matching assets")
                            .font(MCTheme.fontCaption)
                            .foregroundStyle(MCTheme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(items) { asset in
                            let filename = "\(asset.name).\(asset.fileExtension)"
                            let isActive = selection == filename
                            Button {
                                selection = filename
                                showPopover = false
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: iconFor(asset))
                                        .font(.system(size: 10))
                                        .foregroundStyle(isActive ? MCTheme.statusBlue : MCTheme.textSecondary)
                                        .frame(width: 14)
                                    Text(filename)
                                        .font(MCTheme.fontCaption)
                                        .foregroundStyle(isActive ? MCTheme.textPrimary : MCTheme.textSecondary)
                                    Spacer()
                                    if isActive {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(MCTheme.statusBlue)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(AssetPickerRowStyle())
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .frame(width: 240, height: min(CGFloat(assets.count + 2) * 26 + 50, 300))
        .background(Color(white: 0.1))
    }

    private func iconFor(_ asset: AssetEntry) -> String {
        switch asset.fileExtension.lowercased() {
        case "wav", "mp3", "aac", "m4a", "ogg": return "speaker.wave.2"
        case "png", "jpg", "jpeg", "tiff", "exr", "hdr": return "photo"
        case "metal": return "function"
        case "usdz", "usda", "obj": return "cube"
        case "mcmat": return "paintpalette"
        default: return "doc"
        }
    }
}

private struct AssetPickerRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(configuration.isPressed ? Color.white.opacity(0.08) : Color.clear)
            )
    }
}
