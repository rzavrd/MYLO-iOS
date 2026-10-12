import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// Add VLESS / VMess / Trojan links, subscriptions and OpenVPN (.ovpn) files.
struct ConfigsView: View {
    var onBack: () -> Void
    @State private var text = ""
    @State private var items = ConfigStore.list()
    @State private var message: String?
    @State private var pickFolder = false
    @State private var pickFile = false
    @State private var active = Store.shared.activeOvpn
    @State private var authFor: ImportedConfig?

    private var engineNote: String {
        #if OPENVPN
        return "OpenVPN profiles can connect: tap Use, then the power button. VLESS, VMess and Trojan are saved only; they need a different tunnel core that is not included yet."
        #else
        return "Saved configurations can't connect in this build. OpenVPN needs the MYLO-OpenVPN target (Network Extension, paid developer account); VLESS, VMess and Trojan need a core that is not included yet. See docs/OPENVPN.md."
        #endif
    }

    @ViewBuilder
    private func extra(_ c: ImportedConfig) -> some View {
        #if OPENVPN
        if c.kind == .openvpn {
            if ConfigParser.needsAuth(ConfigStore.raw(c.id) ?? "") {
                Button { authFor = c } label: {
                    Image(systemName: ConfigStore.auth(c.id) == nil ? "key" : "key.fill").foregroundColor(C.teal)
                }
            }
            Button {
                active = (active == c.id) ? "" : c.id
                Store.shared.activeOvpn = active
            } label: {
                Text(active == c.id ? "Active" : "Use").font(.mylo(13, weight: .semibold))
                    .foregroundColor(active == c.id ? (Pal.shared.cur.dark ? Color.black : Color.white) : C.teal)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(active == c.id ? C.teal : Color.clear))
                    .overlay(Capsule().stroke(C.teal, lineWidth: active == c.id ? 0 : 1.2))
            }
        }
        #else
        EmptyView()
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            SubHeader("Add configuration", onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Paste vless://, vmess:// or trojan:// links (one per line, or a whole subscription). For OpenVPN, pick many .ovpn files at once or a whole folder.")
                        .font(.mylo(13)).foregroundColor(C.muted)

                    TextEditor(text: $text)
                        .scrollContentBackground(.hidden)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .foregroundColor(C.ink)
                        .frame(height: 130).padding(8)
                        .background(RoundedRectangle(cornerRadius: 14).fill(C.card))

                    HStack(spacing: 10) {
                        pill("Paste") { text = UIPasteboard.general.string ?? text }
                        pill("Add links", filled: true) { importBatch([(text, nil)]); }
                    }
                    HStack(spacing: 10) {
                        pill(".ovpn files") { pickFolder = false; pickFile = true }
                        pill("OpenVPN folder") { pickFolder = true; pickFile = true }
                    }

                    if let m = message {
                        Text(m).font(.mylo(13)).foregroundColor(C.ink)
                    }

                    Text(engineNote).font(.mylo(12)).foregroundColor(C.muted)

                    if !items.isEmpty {
                        HStack {
                            Text("Saved (\(items.count))").foregroundColor(C.muted)
                            Spacer()
                            Button("Delete all") {
                                items.forEach { ConfigStore.remove($0.id) }
                                items = ConfigStore.list(); message = nil; active = Store.shared.activeOvpn
                            }.foregroundColor(C.danger).font(.mylo(14))
                        }
                        .padding(.top, 6)
                        ForEach(items) { c in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.name).font(.mylo(16, weight: .semibold)).foregroundColor(C.ink).lineLimit(1)
                                    Text(c.kind.title).font(.mylo(12)).foregroundColor(C.muted).lineLimit(1)
                                }
                                Spacer()
                                extra(c)
                                Button { ConfigStore.remove(c.id); items = ConfigStore.list(); active = Store.shared.activeOvpn } label: {
                                    Image(systemName: "trash").foregroundColor(C.danger)
                                }
                            }
                            .card(12)
                        }
                    }
                }
                .padding(20)
            }
        }
        .sheet(item: $authFor) { c in OpenVPNLoginSheet(config: c) }
        .fileImporter(isPresented: $pickFile,
                      allowedContentTypes: pickFolder ? [.folder] : [UTType(filenameExtension: "ovpn") ?? .plainText, .plainText, .data],
                      allowsMultipleSelection: !pickFolder) { result in
            guard case let .success(urls) = result else { return }
            var batch: [(String, String?)] = []
            var unreadable = 0
            func read(_ u: URL) {
                if let t = try? String(contentsOf: u, encoding: .utf8) { batch.append((t, u.lastPathComponent)) } else { unreadable += 1 }
            }
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    if let en = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) {
                        for case let f as URL in en where f.pathExtension.lowercased() == "ovpn" { read(f) }
                    }
                } else {
                    read(url)
                }
            }
            if batch.isEmpty { message = unreadable > 0 ? "Could not read the selected files." : "No .ovpn files found."; return }
            importBatch(batch, unreadable: unreadable)
        }
    }

    /// Imports many texts/files at once and reports one summary.
    private func importBatch(_ inputs: [(String, String?)], unreadable: Int = 0) {
        var added = 0, dup = 0, failed = unreadable
        var firstError: String?
        for (t, name) in inputs {
            let r = ConfigParser.parseAll(t, filename: name)
            for p in r.ok { if ConfigStore.add(p) { added += 1 } else { dup += 1 } }
            failed += r.errors.count
            if firstError == nil { firstError = r.errors.first }
        }
        items = ConfigStore.list()
        var parts: [String] = []
        if added > 0 { parts.append("\(added) added") }
        if dup > 0 { parts.append("\(dup) already saved") }
        if failed > 0 { parts.append("\(failed) failed" + (firstError.map { " (\($0))" } ?? "")) }
        message = parts.isEmpty ? "Nothing to import." : parts.joined(separator: " - ")
        if added > 0, inputs.count == 1, inputs[0].1 == nil { text = "" }
    }

    private func pill(_ title: String, filled: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.mylo(15, weight: .semibold))
                .foregroundColor(filled ? (Pal.shared.cur.dark ? Color.black : Color.white) : C.teal)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12).fill(filled ? C.teal : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(C.teal, lineWidth: filled ? 0 : 1.5))
        }
    }
}


/// Username/password for an OpenVPN profile that uses `auth-user-pass`.
struct OpenVPNLoginSheet: View {
    let config: ImportedConfig
    @Environment(\.dismiss) private var dismiss
    @State private var user = ""
    @State private var pass = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text(config.name)) {
                    TextField("Username", text: $user).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Password", text: $pass)
                }
                Section(footer: Text("Stored in the Keychain on this device.")) { EmptyView() }
            }
            .navigationTitle("OpenVPN login").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { ConfigStore.setAuth(config.id, user: user, pass: pass); dismiss() }
                }
            }
            .onAppear { if let a = ConfigStore.auth(config.id) { user = a.user; pass = a.pass } }
        }
    }
}
