import UIKit
import SwiftUI

struct LoginView: View {
    @EnvironmentObject var auth: AuthModel
    @State private var user = ""
    @State private var pass = ""
    @State private var reveal = false
    @FocusState private var focus: Int?

    var body: some View {
        ZStack {
            C.bg.ignoresSafeArea()
            RadialGradient(colors: [C.glow, .clear], center: .init(x: 0.5, y: 0.18), startRadius: 0, endRadius: 420)
                .ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    Spacer().frame(height: 70)
                    Image("Logo").resizable().scaledToFit().frame(width: 150)
                    Text("MYLO VPN").font(.mylo(30, weight: .bold)).foregroundColor(C.ink)
                    Text("Sign in to continue").font(.mylo(15)).foregroundColor(C.muted)
                    Spacer().frame(height: 10)

                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "person.fill").foregroundColor(C.muted)
                            TextField("Username", text: $user)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .textContentType(.username).submitLabel(.next)
                                .focused($focus, equals: 0)
                                .onSubmit { focus = 1 }
                        }
                        .padding(16).background(RoundedRectangle(cornerRadius: 16).fill(C.card))

                        HStack(spacing: 12) {
                            Image(systemName: "lock.fill").foregroundColor(C.muted)
                            Group {
                                if reveal { TextField("Password", text: $pass) } else { SecureField("Password", text: $pass) }
                            }
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .textContentType(.password).submitLabel(.go)
                            .focused($focus, equals: 1)
                            .onSubmit { submit() }
                            Button { reveal.toggle() } label: {
                                Image(systemName: reveal ? "eye.slash" : "eye").foregroundColor(C.muted)
                            }
                        }
                        .padding(16).background(RoundedRectangle(cornerRadius: 16).fill(C.card))
                    }
                    .foregroundColor(C.ink)

                    if let e = auth.error {
                        Text(e).font(.mylo(13)).foregroundColor(C.danger).multilineTextAlignment(.center)
                    }

                    Button(action: submit) {
                        Group {
                            if auth.busy { ProgressView().tint(Pal.shared.cur.dark ? Color.black : Color.white) }
                            else { Text("Sign in").font(.mylo(18, weight: .bold)) }
                        }
                        .foregroundColor(Pal.shared.cur.dark ? Color.black : Color.white)
                        .frame(maxWidth: .infinity).frame(height: 54)
                        .background(RoundedRectangle(cornerRadius: 16).fill(C.teal))
                    }
                    .disabled(auth.busy)

                    Text("Access is limited to approved accounts.")
                        .font(.mylo(12)).foregroundColor(C.muted).padding(.top, 6)
                }
                .padding(.horizontal, 28)
            }
        }
    }

    private func submit() {
        focus = nil
        Task { await auth.login(user, pass) }
    }
}
