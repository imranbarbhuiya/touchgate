import AppKit
import SwiftUI
import LocalAuthenticationEmbeddedUI
import TouchGateCore

struct SettingsView: View {
    @ObservedObject var gate: GateController

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "touchid").font(.system(size: 42, weight: .light)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("TouchGate").font(.system(size: 26, weight: .semibold, design: .rounded))
                    Text("Touch ID opens your apps.").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack(spacing: 8) {
                Image(systemName: gate.touchIDAvailable ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(gate.touchIDAvailable ? Color.green : Color.orange)
                Text(gate.touchIDAvailable ? "Touch ID is ready" : "Touch ID is unavailable").font(.callout)
                Spacer()
                Button("Check again") { gate.refreshTouchID() }.buttonStyle(.link)
            }
            if !gate.windowControlAvailable {
                HStack {
                    Text("Apps such as ChatGPT may need Accessibility access to hide their windows.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Allow window control…", action: gate.requestWindowControl)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Protected apps").font(.headline)
                    Spacer()
                    Button("Add apps…", action: gate.addApps)
                        .disabled(gate.authenticating)
                }
                if gate.apps.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "lock.open").font(.system(size: 28)).foregroundStyle(.secondary)
                        Text("Choose the apps you want to keep private.").font(.callout)
                        Text("They will ask for Touch ID when you open them.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, minHeight: 165)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(gate.apps) { app in
                                HStack(spacing: 12) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                                        .resizable().frame(width: 32, height: 32)
                                    Text(app.name).font(.body)
                                    Spacer()
                                    Image(systemName: "lock.fill").foregroundStyle(.secondary)
                                    Button("Remove") { gate.remove(app) }
                                        .buttonStyle(.borderless).disabled(gate.authenticating)
                                }.padding(12)
                                if app.id != gate.apps.last?.id { Divider().padding(.leading, 56) }
                            }
                        }
                    }.frame(height: 165)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Picker("Ask for Touch ID", selection: Binding(get: { gate.lockMode }, set: gate.setLockMode)) {
                    Text("Every app switch").tag(LockMode.everyActivation)
                    Text("Once per launch").tag(LockMode.oncePerLaunch)
                }.pickerStyle(.segmented).disabled(gate.authenticating)
                Text(gate.lockMode == .everyActivation
                     ? "Ask again when you return after switching to another app."
                     : "Stay unlocked until the app quits, the Mac locks or sleeps, or you choose Lock now.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 10) {
                Label("Lock now, sleep, and screen locking relock all apps", systemImage: "lock.fill")
                Label("Background messages and tasks keep running", systemImage: "arrow.triangle.2.circlepath")
                Label("Local automation also needs Touch ID to open a protected app", systemImage: "cursorarrow")
            }.font(.caption).foregroundStyle(.secondary)
            Divider()
            HStack {
                Toggle("Start at login", isOn: Binding(get: { gate.loginEnabled }, set: gate.setLaunchAtLogin))
                    .toggleStyle(.checkbox).disabled(gate.authenticating)
                Spacer()
                Button("Lock now", action: gate.lockAll)
            }
            if let notice = gate.notice {
                Text(notice).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Text("For casual privacy on an unlocked Mac. Notification previews and app data aren't protected.")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(26).frame(width: 520).tint(.orange)
    }
}

struct UnlockView: View {
    @ObservedObject var gate: GateController

    var body: some View {
        VStack(spacing: 16) {
            if let app = gate.gateApp {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().frame(width: 64, height: 64)
                Text(gate.windowsHidden ? "\(app.name) is locked" : "\(app.name) needs window control").font(.title3.weight(.semibold))
            } else {
                Image(systemName: "lock.fill").font(.largeTitle)
                Text("App locked").font(.title3.weight(.semibold))
            }
            Text("Authenticate to bring its windows back.").font(.callout).foregroundStyle(.secondary)
            if let notice = gate.gateNotice {
                Text(notice).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if !gate.windowControlAvailable {
                    Button("Allow window control…", action: gate.requestWindowControl)
                }
            }
            if gate.authenticating {
                if let view = gate.authenticationView {
                    EmbeddedTouchID(view: view).id(ObjectIdentifier(view)).frame(width: 64, height: 64)
                }
                Text("Use Touch ID to unlock this app.").font(.callout)
            } else {
                Button(action: gate.unlockApp) {
                    Label("Retry Touch ID", systemImage: "touchid")
                }.buttonStyle(.borderedProminent).controlSize(.large)
            }
            Button("Keep locked", action: gate.keepLocked).buttonStyle(.link)
        }.padding(28).frame(width: 380).fixedSize(horizontal: false, vertical: true).tint(.orange)
    }
}

struct EmbeddedTouchID: NSViewRepresentable {
    let view: LAAuthenticationView

    func makeNSView(context: Context) -> LAAuthenticationView { view }
    func updateNSView(_ nsView: LAAuthenticationView, context: Context) {}
}
