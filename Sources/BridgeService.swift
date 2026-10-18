import Foundation
import SwiftUI
import WebKit

/// Owns only the child started by this app. Existing bridges are reused, never stopped.
@MainActor final class BridgeService: ObservableObject {
    static let shared = BridgeService()
    @Published var status = "Verificando a conexão…"
    @Published var busy = false
    @Published var ready = false
    @Published var showPanel = false
    @Published var panelPath = "/"
    @Published var automatic = UserDefaults.standard.bool(forKey: "bridgeAutomatic") {
        didSet { UserDefaults.standard.set(automatic, forKey: "bridgeAutomatic") }
    }
    private var child: Process?
    private var log: FileHandle?
    private var restoring = false

    func check() async -> Bool {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:8581/api/status")!)
        request.timeoutInterval = 2
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            ready = (response as? HTTPURLResponse).map { (200...499).contains($0.statusCode) } ?? false
        } catch { ready = false }
        status = ready ? "Ponte disponível neste Mac" : "Ponte desligada"
        return ready
    }
    func restore() async {
        guard !restoring else { return }; restoring = true
        if automatic { await start() } else { _ = await check() }
    }
    func openPanel(_ path: String = "/") async {
        await start()
        if ready { panelPath = path; showPanel = true }
    }
    func start() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        if await check() { return }
        // A managed installation may still be starting. Do not create a second bridge.
        let service = Process()
        service.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        service.arguments = ["print", "gui/\(getuid())/br.local.CasaMenu.bridge"]
        service.standardOutput = FileHandle.nullDevice; service.standardError = FileHandle.nullDevice
        try? service.run(); service.waitUntilExit()
        if service.terminationStatus == 0 {
            status = "A ponte do macOS está iniciando. Aguarde e tente novamente."
            return
        }
        guard child?.isRunning != true else { status = "A ponte ainda está iniciando."; return }
        guard let node = AppPaths.node, let setup = AppPaths.bridgeFile("setup.mjs"),
              let entry = AppPaths.bridgeFile("node_modules/homebridge-config-ui-x/dist/bin/hb-service.js") else {
            status = "Componentes incompletos. Instale o pacote completo do CasaMenu."; return
        }
        do {
            let storage = AppPaths.support.appendingPathComponent("homebridge-data")
            try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            status = "Preparando sua ponte…"
            try await Task.detached {
                let process = Process()
                process.executableURL = node; process.arguments = [setup.path, storage.path]
                process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
                try process.run(); process.waitUntilExit()
                guard process.terminationStatus == 0 else { throw AppError.message("Não foi possível preparar os dados da ponte.") }
            }.value
            let logs = AppPaths.support.appendingPathComponent("Logs")
            try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let logURL = logs.appendingPathComponent("bridge.log")
            if !FileManager.default.fileExists(atPath: logURL.path) { FileManager.default.createFile(atPath: logURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) }
            log = try FileHandle(forWritingTo: logURL); try log?.seekToEnd()
            let process = Process(); process.executableURL = node
            process.arguments = [entry.path, "run", "-U", storage.path, "-P", setup.deletingLastPathComponent().appendingPathComponent("node_modules").path, "--strict-plugin-resolution"]
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = node.deletingLastPathComponent().path + ":/usr/bin:/bin:/usr/sbin:/sbin"
            process.environment = env
            process.standardOutput = log; process.standardError = log
            process.terminationHandler = { [weak self] _ in Task { @MainActor in
                self?.ready = false; self?.status = "Ponte encerrada. Use Preparar conexão para iniciar novamente."
                try? self?.log?.close(); self?.log = nil
            } }
            child = process; try process.run()
            for _ in 0..<20 {
                if await check() { automatic = true; return }
                guard process.isRunning else { break }
                status = "Iniciando a ponte…"
                try await Task.sleep(nanoseconds: 500_000_000)
            }
            status = "A ponte não respondeu. Consulte o diagnóstico e tente novamente."
        } catch { status = error.localizedDescription }
    }
    func stopOwnedProcess() { if child?.isRunning == true { child?.terminate() } }
}

struct BridgePanel: View {
    @ObservedObject var bridge = BridgeService.shared
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Conectar sua casa").font(.headline)
                    Text("Configuração local · Tuya e pareamento com Casa/Siri").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Concluir") { dismiss() }
            }.padding(18)
            Divider()
            BridgeWebView(path: bridge.panelPath)
        }.frame(width: 960, height: 690)
    }
}
struct BridgeWebView: NSViewRepresentable {
    let path: String
    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.load(URLRequest(url: URL(string: "http://127.0.0.1:8581" + path)!))
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
struct BridgeSetupControls: View {
    @ObservedObject var bridge = BridgeService.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(bridge.status, systemImage: bridge.ready ? "checkmark.circle.fill" : "network").foregroundStyle(bridge.ready ? .green : .secondary)
            HStack {
                Button(bridge.busy ? "Preparando…" : "Preparar conexão") { Task { await bridge.start() } }.disabled(bridge.busy)
                Button("Configurar e mostrar QR") { Task { await bridge.openPanel() } }.disabled(bridge.busy)
                Button("Diagnóstico") { NSWorkspace.shared.open(AppPaths.support.appendingPathComponent("Logs")) }
            }
            Toggle("Iniciar a ponte ao abrir o CasaMenu", isOn: $bridge.automatic)
            Text("O aplicativo inclui os componentes necessários. Na primeira vez, crie seu acesso local e autorize a conta pelo celular. O Mac precisa permanecer ligado para responder ao Casa/Siri.").font(.caption).foregroundStyle(.secondary)
        }.sheet(isPresented: $bridge.showPanel) { BridgePanel() }.task { _ = await bridge.check() }
    }
}
