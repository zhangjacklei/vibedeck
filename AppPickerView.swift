//
//  AppPickerView.swift
//  vibedeck
//
//  「打开 App」的图形化选择器：搜索 + 图标列表，写入 bundle id。
//

import SwiftUI
import AppKit

struct AppPickerView: View {
    @ObservedObject private var catalog = AppCatalog.shared
    @Binding var selection: String

    @State private var query: String = ""

    private var filtered: [InstalledApp] {
        guard !query.isEmpty else { return catalog.apps }
        let q = query.lowercased()
        return catalog.apps.filter {
            $0.name.lowercased().contains(q) || $0.id.lowercased().contains(q)
        }
    }

    private var selectedApp: InstalledApp? {
        catalog.app(matching: selection)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textSecondary)
                TextField("搜索已安装的 App", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.textSecondary)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(white: 0.97))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color(white: 0.90), lineWidth: 1))
            )

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filtered) { app in
                        row(for: app)
                    }
                    if filtered.isEmpty {
                        Text(catalog.loading ? "正在读取应用列表…" : "没有匹配的应用")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 14)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: 208)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color(white: 0.99))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color(white: 0.91), lineWidth: 1))
            )

            HStack(spacing: 8) {
                if let app = selectedApp {
                    Image(nsImage: app.icon ?? NSImage())
                        .resizable()
                        .frame(width: 14, height: 14)
                    Text("已选择：\(app.name)")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.accent)
                } else {
                    Text("从上方列表里选择一个 App")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textSecondary)
                }
                Spacer()
                Button {
                    catalog.reload()
                } label: {
                    Label("重新扫描", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .onAppear { catalog.loadIfNeeded() }
        // popover 是独立窗口，固定浅色，避免深色模式下文字发白
        .environment(\.colorScheme, .light)
        .preferredColorScheme(.light)
    }

    private func row(for app: InstalledApp) -> some View {
        let isSelected = app.id == selection
        return Button {
            selection = app.id
        } label: {
            HStack(spacing: 8) {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 18, height: 18)
                }
                Text(app.name)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 6)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.accent)
                }
            }
            .foregroundStyle(isSelected ? Palette.accent : Color(white: 0.22))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Palette.accentSoft : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(app.path)
    }
}
