import SwiftUI
import AppKit
import Security

struct Appliance: Identifiable, Codable {
    var id: String; var name: String; var room: String; var kind: String
    var brand: String = ""; var entity: String = ""; var on = false; var temperature = 23.0
    var icon: String { kind == "climate" ? "air.conditioner.horizontal" : kind == "media_player" ? "hifispeaker.fill" : "square.dashed" }
}
enum CredentialStore {
    static let service = "br.local.CasaMenu.homeassistant"
    static func read() -> String {
        let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:service, kSecAttrAccount as String:"token", kSecReturnData as String:true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return "" }
        return String(data:data, encoding:.utf8) ?? ""
    }
    static func save(_ value: String) throws {
        let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:service, kSecAttrAccount as String:"token"]
        guard !value.isEmpty else { SecItemDelete(query as CFDictionary); return }
        let update = SecItemUpdate(query as CFDictionary,[kSecValueData as String:Data(value.utf8)] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw AppError.message("Não foi possível atualizar o token no Chaves.") }
        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        guard SecItemAdd(item as CFDictionary,nil) == errSecSuccess else { throw AppError.message("Não foi possível salvar o token no Chaves.") }
    }
}
enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
}
struct HAState: Decodable {
    var entity_id: String; var state: String; var attributes: Attributes
    struct Attributes: Decodable {
        var friendly_name: String?; var temperature: Double?; var current_temperature: Double?
        var min_temp: Double?; var max_temp: Double?; var target_temp_step: Double?
        var hvac_modes: [String]?; var fan_modes: [String]?; var fan_mode: String?
        var swing_modes: [String]?; var swing_mode: String?; var supported_features: Int?
    }
}
@MainActor final class HomeStore: ObservableObject {
    @Published var devices: [Appliance] = []
    @Published var selected = "Visão geral"
    @Published var officeModel = UserDefaults.standard.string(forKey:"officeModel") ?? ""
    @Published var irTested = UserDefaults.standard.bool(forKey:"irTested")
    @Published var bridgeStatus = "Pareamento Apple Casa ainda não verificado"
    @Published var homekitCode = ""
    @Published var tuyaReady = false
    @Published var tuyaCodes: [String] = []
    @Published var tuyaEstimated = true
    @Published var greeConnectionError = ""
    @Published var greeExtras: [String:[String:Int]] = [:]
    @Published var quickID = ""
    @Published var quickMenu = ""
    @Published var demo = true
    @Published var server = UserDefaults.standard.string(forKey:"server") ?? "http://homeassistant.local:8123"
    @Published var token = ""
    @Published var states: [HAState] = []
    @Published var status = "Demonstração • nenhum aparelho conectado"
    @Published var busy = false
    @Published var error = ""
    @Published var lastSync: Date?
    @Published var greePeers: [GreePeer] = []
    @Published var greeTarget = ""
    @Published var greeRoom = "Quarto"
    @Published var greeStatus = "Conecte o Mac ao mesmo Wi-Fi do ar já cadastrado no Gree+."
    var greeSessions: [String:GreeSession] = [:]
    @Published var search = ""
    @Published var activity: [String] = []
    @Published var drafts: [String:Double] = [:]
    @Published var demoModes: [String:String] = [:]
    let credentialProvider: () -> String
    let session: URLSession
    var refreshTask: Task<Void,Never>?
    var connectedServer: String?
    var services: Set<String> = []
    init(session: URLSession = .shared, credentialProvider: @escaping () -> String = CredentialStore.read) {
        self.session = session
        self.credentialProvider = credentialProvider
        if let data = UserDefaults.standard.data(forKey:"inventory"), let saved = try? JSONDecoder().decode([Appliance].self,from:data) { devices = saved }
        else {
            devices = [Appliance(id:"1",name:"Ar do escritório",room:"Escritório",kind:"climate"), Appliance(id:"2",name:"Ar do quarto",room:"Quarto",kind:"climate",brand:"Gree — confirmar"),Appliance(id:"3",name:"Echo / Echo Dot",room:"A confirmar",kind:"media_player",brand:"Amazon")]
            devices += (4...8).map { Appliance(id:String($0),name:"Dispositivo \($0)",room:"A cadastrar",kind:"unknown") }
        }
    }
    func checkBridge() async {
        do {
            var request = URLRequest(url:URL(string:"http://127.0.0.1:8581")!); request.timeoutInterval = 3
            let (_,response) = try await URLSession.shared.data(for:request)
            bridgeStatus = (response as? HTTPURLResponse)?.statusCode == 200 ? "Painel Homebridge em execução · pareamento no Casa pendente de verificação" : "Painel respondeu · confira a configuração"
        } catch { bridgeStatus = "Painel Homebridge não respondeu. Inicie HomeKit/start.command na pasta do projeto." }
        let candidates = AppPaths.storageFolders.map { $0.appendingPathComponent("config.json") }
        homekitCode = ""
        for url in candidates {
            if let data = try? Data(contentsOf:url), let config = try? JSONSerialization.jsonObject(with:data) as? [String:Any], let bridge = config["bridge"] as? [String:Any], let pin = bridge["pin"] as? String { homekitCode = pin; break }
        }
    }
    func persist() { if let data = try? JSONEncoder().encode(devices) { UserDefaults.standard.set(data,forKey:"inventory") } }
    func request(_ path: String, body: [String:Any]? = nil) async throws -> Data {
        guard let base = URL(string:server.trimmingCharacters(in:.whitespacesAndNewlines)), ["http","https"].contains(base.scheme ?? ""), base.host != nil, base.user == nil, base.password == nil, base.query == nil, base.fragment == nil else { throw AppError.message("Informe uma URL http:// ou https:// válida do Home Assistant.") }
        var req = URLRequest(url:base.appendingPathComponent("api/" + path)); req.timeoutInterval = 12
        if token.isEmpty, let stored = UserDefaults.standard.string(forKey:"server"), stored != server, connectedServer != server { throw AppError.message("Para trocar de central, informe o token correspondente.") }
        let secret = token.isEmpty ? credentialProvider() : token
        guard !secret.isEmpty else { throw AppError.message("Informe o token de acesso do Home Assistant.") }
        req.setValue("Bearer " + secret,forHTTPHeaderField:"Authorization")
        if let body { req.httpMethod = "POST"; req.setValue("application/json",forHTTPHeaderField:"Content-Type"); req.httpBody = try JSONSerialization.data(withJSONObject:body) }
        let (data,response) = try await session.data(for:req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw AppError.message("Home Assistant recusou a solicitação. Confira endereço, token e permissões.") }
        return data
    }
    func connect() async {
        busy = true; error = ""; defer { busy = false }
        do {
            let data = try await request("states")
            let result = try JSONDecoder().decode([HAState].self,from:data)
            let serviceData = try await request("services")
            let catalog = try JSONSerialization.jsonObject(with:serviceData) as? [[String:Any]] ?? []
            services = Set(catalog.flatMap { item -> [String] in
                let domain = item["domain"] as? String ?? ""
                return (item["services"] as? [String:Any] ?? [:]).keys.map { domain + "." + $0 }
            })
            if !token.isEmpty { try CredentialStore.save(token); token = "" }
            UserDefaults.standard.set(server,forKey:"server")
            connectedServer = server; states = result; demo = false; lastSync = Date(); status = "Home Assistant conectado"; sync(); selected = "Dispositivos"
            refreshTask?.cancel()
            refreshTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds:8_000_000_000)
                    guard !Task.isCancelled, let self else { return }
                    await self.refresh()
                }
            }
        } catch { self.error = error.localizedDescription; states = []; status = "Falha na conexão" }
    }
    func sync() {
        for i in devices.indices {
            if let state = states.first(where: { $0.entity_id == devices[i].entity }) {
                devices[i].on = !["off","unavailable","unknown"].contains(state.state)
                if let temp = state.attributes.temperature { devices[i].temperature = temp }
            }
        }
    }
    func available(_ device: Appliance) -> Bool {
        if demo { return true }
        if device.entity == "climate.tuya_office" { return tuyaReady }
        let pathReady = device.entity.hasPrefix("climate.gree_lan_") ? greeSessions[device.entity] != nil : server == connectedServer && token.isEmpty
        return pathReady && states.contains { $0.entity_id == device.entity && !["unavailable","unknown"].contains($0.state) }
    }
    func state(_ d: Appliance) -> HAState? { states.first { $0.entity_id == d.entity } }
    func bounds(_ d: Appliance) -> ClosedRange<Double> {
        let lo = state(d)?.attributes.min_temp ?? 16; let hi = state(d)?.attributes.max_temp ?? 30
        return min(lo,hi)...max(max(lo,hi),min(lo,hi)+1)
    }
    func step(_ d: Appliance) -> Double { max(0.1,state(d)?.attributes.target_temp_step ?? 1) }
    func modes(_ d: Appliance) -> [String] { demo ? ["off","cool","heat","dry","fan_only","auto"] : state(d)?.attributes.hvac_modes ?? [] }
    func supports(_ d: Appliance,_ service: String) -> Bool {
        if demo { return true }
        if d.entity == "climate.tuya_office" {
            let code = ["turn_on":"PowerOn","turn_off":"PowerOff","set_temperature":"T","set_hvac_mode":"M","set_fan_mode":"F"][service]
            return tuyaReady && code.map{tuyaCodes.contains($0)} == true
        }
        guard available(d), services.contains(d.kind + "." + service) else { return false }
        let flags = state(d)?.attributes.supported_features ?? 0
        switch service {
        case "set_temperature": return flags & 1 != 0 && state(d)?.attributes.temperature != nil
        case "set_fan_mode": return !(state(d)?.attributes.fan_modes ?? []).isEmpty
        case "set_swing_mode": return !(state(d)?.attributes.swing_modes ?? []).isEmpty
        case "set_hvac_mode": return !modes(d).isEmpty
        case "turn_on": return d.kind != "climate" || flags & 128 != 0
        case "turn_off": return d.kind != "climate" || flags & 256 != 0
        default: return true
        }
    }
    func refresh() async {
        guard !demo, !busy else { return }
        busy = true; defer { busy = false }
        if tuyaReady { do { applyTuya(try await TuyaBridge.run()) } catch { self.error = error.localizedDescription } }
        for (entity,session) in greeSessions {
            do { let (renewed,values) = try await GreeLAN.recoveringExchange(session); greeSessions[entity] = renewed; applyGree(entity,values:values); greeConnectionError = "" }
            catch { if let i = states.firstIndex(where:{$0.entity_id == entity}) { states[i].state = "unavailable" }; greeConnectionError = "Ar do quarto sem conexão. Tentando reconectar automaticamente." }
        }
        if server == connectedServer, token.isEmpty {
            do { let data = try await request("states"); let incoming = try JSONDecoder().decode([HAState].self,from:data); states = states.filter { greeSessions[$0.entity_id] != nil || $0.entity_id == "climate.tuya_office" } + incoming; sync(); lastSync = Date() }
            catch { self.error = "Não foi possível atualizar a central."; states = states.filter { greeSessions[$0.entity_id] != nil || $0.entity_id == "climate.tuya_office" } }
        }
    }
    func scanGree() async {
        guard !busy else { return }; busy = true; error = ""; greeStatus = "Buscando Gree na rede local…"; defer { busy = false }
        do { greePeers = try await GreeLAN.discover(target:greeTarget.trimmingCharacters(in:.whitespacesAndNewlines)); greeStatus = greePeers.isEmpty ? "Nenhum Gree respondeu. Confira a mesma rede Wi-Fi, a permissão Rede Local e tente pelo IP do aparelho." : "Encontrados \(greePeers.count) aparelhos. Escolha o cômodo e clique Conectar." }
        catch { self.error = error.localizedDescription; greeStatus = "Busca não concluída" }
    }
    func bindGree(_ peer:GreePeer) async {
        guard !busy else { return }
        let entity = "climate.gree_lan_" + peer.mac.lowercased().filter { $0.isLetter || $0.isNumber }
        guard let slot = devices.firstIndex(where:{$0.entity == entity}) ?? devices.firstIndex(where:{$0.entity.isEmpty && $0.room == greeRoom && $0.kind == "climate"}) ?? devices.firstIndex(where:{$0.entity.isEmpty && $0.kind == "unknown"}) else { error = "Os oito espaços estão ocupados. Libere um vínculo para conectar."; return }
        busy = true; error = ""; defer { busy = false }
        do {
            let session = try await GreeLAN.bind(peer)
            let values = try await GreeLAN.exchange(session)
            greeSessions[entity] = session
            devices[slot].entity = entity; devices[slot].kind = "climate"; devices[slot].room = greeRoom; devices[slot].brand = "Gree+ · Wi-Fi local"; devices[slot].name = "Ar do " + greeRoom.lowercased()
            demo = false; applyGree(entity,values:values); persist()
            services.formUnion(["climate.set_temperature","climate.set_hvac_mode","climate.set_fan_mode","climate.set_swing_mode","climate.turn_on","climate.turn_off"])
            status = "Gree conectado pelo Wi-Fi local"; greeStatus = "Conectado · " + peer.name; selected = "Visão geral"
            refreshTask?.cancel(); refreshTask = Task { [weak self] in while !Task.isCancelled { try? await Task.sleep(nanoseconds:8_000_000_000); guard !Task.isCancelled, let self else { return }; await self.refresh() } }
        } catch { self.error = error.localizedDescription }
    }
    func applyGree(_ entity:String,values:[String:Int]) {
        greeConnectionError = ""
        greeExtras[entity] = values
        let previous = states.first{$0.entity_id == entity}
        let mode = [0:"auto",1:"cool",2:"dry",3:"fan_only",4:"heat"][values["Mod"] ?? 0] ?? "auto"
        let attrs = HAState.Attributes(friendly_name:devices.first{$0.entity == entity}?.name,temperature:values["SetTem"].map(Double.init) ?? previous?.attributes.temperature,min_temp:16,max_temp:30,target_temp_step:1,hvac_modes:["off","cool","heat","dry","fan_only","auto"],fan_modes:["auto","low","medium_low","medium","medium_high","high"],fan_mode:[0:"auto",1:"low",2:"medium_low",3:"medium",4:"medium_high",5:"high"][values["WdSpd"] ?? 0],swing_modes:["off","on"],swing_mode:values["SwUpDn"] == 1 ? "on" : "off",supported_features:425)
        let state = HAState(entity_id:entity,state:values["Pow"] == 0 ? "off" : mode,attributes:attrs)
        states.removeAll{$0.entity_id == entity}; states.append(state); sync(); lastSync = Date()
    }
    func importEntity(_ state:HAState) {
        guard !devices.contains(where:{$0.entity == state.entity_id}) else { return }
        guard let i = devices.firstIndex(where:{$0.entity.isEmpty && $0.kind == "unknown"}) ?? devices.firstIndex(where:{$0.entity.isEmpty && $0.kind == state.entity_id.components(separatedBy:".")[0]}) else { error = "Os oito espaços estão ocupados. Altere um vínculo abaixo."; return }
        devices[i].name = state.attributes.friendly_name ?? state.entity_id
        devices[i].kind = state.entity_id.components(separatedBy:".")[0]; devices[i].entity = state.entity_id
        devices[i].room = "Escolha o cômodo"; sync(); persist()
    }
    func command(_ id:String,service:String,value: String? = nil,number:Double? = nil) async {
        guard !busy, let i = devices.firstIndex(where:{$0.id == id}) else { return }
        let device = devices[i]
        if demo {
            if let number { devices[i].temperature = number; drafts[id] = nil }
            else if service == "set_hvac_mode" { demoModes[id] = value; devices[i].on = value != "off" }
            else if service == "turn_on" || service == "turn_off" { devices[i].on = service == "turn_on" }
            activity.insert("Simulação · \(device.name) · \(service) \(value ?? number.map(String.init(describing:)) ?? "")",at:0)
            return
        }
        guard supports(device,service) else { error = "Este aparelho não anuncia suporte a esse controle."; return }
        if service == "set_hvac_mode", !modes(device).contains(value ?? "") { return }
        var body: [String:Any] = ["entity_id":device.entity]
        if let number {
            let range = bounds(device); let tick = step(device)
            body["temperature"] = min(range.upperBound,max(range.lowerBound,(number/tick).rounded()*tick))
        }
        if let value {
            if service == "set_fan_mode", !(state(device)?.attributes.fan_modes ?? []).contains(value) { return }
            if service == "set_swing_mode", !(state(device)?.attributes.swing_modes ?? []).contains(value) { return }
            body[service.replacingOccurrences(of:"set_",with:"")] = value
        }
        busy = true; error = ""; defer { busy = false; drafts[id] = nil }
        if device.entity == "climate.tuya_office" {
            do {
                let action = service == "set_hvac_mode" && value == "off" ? "off" : service == "turn_on" ? "on" : service == "turn_off" ? "off" : service == "set_hvac_mode" ? "mode" : service == "set_fan_mode" ? "fan" : "temperature"
                let result = try await TuyaBridge.run(action,temperature:number,value:value)
                applyTuya(result); activity.insert("Aceito pela Tuya · " + device.name,at:0)
            } catch { self.error = error.localizedDescription }
            return
        }
        if let session = greeSessions[device.entity] {
            do {
                let values = try Self.greeCommand(service:service,value:value,number:number,on:device.on)
                let (renewed,_) = try await GreeLAN.recoveringExchange(session,values:values)
                greeSessions[device.entity] = renewed; greeConnectionError = ""
                activity.insert("Confirmado pelo Gree · \(device.name) · \(service)",at:0)
                do { let (updated,state) = try await GreeLAN.recoveringExchange(renewed); greeSessions[device.entity] = updated; applyGree(device.entity,values:state) }
                catch { greeConnectionError = "Comando enviado ao quarto; aguardando atualização do estado." }
            } catch { greeConnectionError = "Não foi possível confirmar o comando do quarto. A reconexão é automática." }
            return
        }
        do {
            _ = try await request("services/\(device.kind)/\(service)",body:body)
            activity.insert("Enviado · \(device.name) · \(service)",at:0); activity = Array(activity.prefix(20))
            status = "Comando aceito pela central; aguardando estado"
            do { let data = try await request("states"); states = try JSONDecoder().decode([HAState].self,from:data); sync(); lastSync = Date() }
            catch { self.error = "Comando aceito, mas a consulta do estado falhou. Confira o aparelho antes de repetir." }
        } catch { self.error = error.localizedDescription; activity.insert("Falha · \(device.name) · \(service)",at:0) }
    }
    static func greeCommand(service:String,value:String?,number:Double?,on:Bool) throws -> [String:Int] {
        switch service {
        case "set_temperature": guard let number, number.isFinite else { throw AppError.message("Temperatura inválida.") }; return ["SetTem":Int(min(30,max(16,number)).rounded()),"TemUn":0,"TemRec":0]
        case "set_hvac_mode": if value == "off" { return ["Pow":0] }; guard let value, let mode = ["auto":0,"cool":1,"dry":2,"fan_only":3,"heat":4][value] else { throw AppError.message("Modo Gree inválido.") }; return ["Pow":1,"Mod":mode]
        case "set_fan_mode": guard let value, let fan = ["auto":0,"low":1,"medium_low":2,"medium":3,"medium_high":4,"high":5][value] else { throw AppError.message("Ventilação inválida.") }; return ["WdSpd":fan]
        case "set_swing_mode": guard ["on","off"].contains(value ?? "") else { throw AppError.message("Oscilação inválida.") }; return ["SwUpDn":value == "on" ? 1 : 0]
        case "turn_on": return ["Pow":1]
        case "turn_off": return ["Pow":0]
        default: throw AppError.message("Comando não implementado para Gree local.")
        }
    }
    func change(_ id:String,temperature:Double? = nil) async {
        guard let device = devices.first(where:{$0.id == id}) else { return }
        if let temperature { await command(id,service:"set_temperature",number:temperature) }
        else if device.entity == "climate.tuya_office" { await command(id,service:device.on ? "turn_off" : "turn_on") }
        else if device.kind == "climate", supports(device,"set_hvac_mode") {
            let mode = device.on ? "off" : (modes(device).contains("cool") ? "cool" : modes(device).first(where:{$0 != "off"}) ?? "off")
            await command(id,service:"set_hvac_mode",value:mode)
        } else { await command(id,service:device.on ? "turn_off" : "turn_on") }
    }

}

#if !ENGINE_TEST
final class CasaAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let url = Bundle.main.url(forResource: "CasaMenu", withExtension: "icns"), let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
    }
}
@main struct CasaMenuApp: App {
    @NSApplicationDelegateAdaptor(CasaAppDelegate.self) var appDelegate
    @StateObject var store = HomeStore()
    var body: some Scene {
        WindowGroup("Casa", id:"main") { Dashboard().environmentObject(store).task { await store.restoreConnections() }.frame(minWidth:1000,minHeight:720).preferredColorScheme(.dark).tint(CasaStyle.accent) }.defaultSize(width:1160,height:800)
        Window("Controle rápido",id:"quick") { QuickPanel().environmentObject(store) }.windowResizability(.contentSize)
        MenuBarExtra { QuickPanel().environmentObject(store) } label: { Image(nsImage:CasaBrand.menuIcon).accessibilityLabel("CasaMenu") }.menuBarExtraStyle(.window)
    }
}
#endif
struct Dashboard: View {
    @EnvironmentObject var store: HomeStore
    @Environment(\.openWindow) var openWindow
    let pages = [("Visão geral","square.grid.2x2"),("Dispositivos","air.conditioner.horizontal"),("Infravermelho","dot.radiowaves.left.and.right"),("Apple Casa","house.fill"),("Ecossistema","point.3.connected.trianglepath.dotted"),("Conexão","network"),("Primeiros passos","checklist")]
    var body: some View {
        NavigationSplitView {
            VStack(alignment:.leading,spacing:24) {
                HStack(spacing:12) { Image(systemName:"house.fill").font(.title2).foregroundStyle(CasaStyle.accent).frame(width:46,height:46).background(CasaStyle.accent.opacity(0.10),in:RoundedRectangle(cornerRadius:15)); VStack(alignment:.leading,spacing:3) { Text("Casa").font(.system(size:26,weight:.semibold,design:.rounded)); Text("CONTROL CENTER").font(.system(size:8,weight:.medium)).tracking(2).foregroundStyle(.secondary) } }.padding(.top,15)
                Text("SEU ECOSSISTEMA").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(pages,id:\.0) { page in Button { store.selected = page.0 } label: { Label(page.0,systemImage:page.1).frame(maxWidth:.infinity,alignment:.leading).padding(12).background(store.selected == page.0 ? CasaStyle.accent.opacity(0.10) : Color.clear,in:RoundedRectangle(cornerRadius:10)) }.buttonStyle(.plain) }
                Spacer()
                Label(store.demo ? "Modo demonstração" : "Dispositivos conectados",systemImage:store.demo ? "sparkles" : "network").font(.caption)
                Text("8 espaços · configuração local").font(.caption).foregroundStyle(.secondary)
            }.padding(20).background(CasaStyle.background).navigationSplitViewColumnWidth(245)
        } detail: {
            ScrollView {
                VStack(alignment:.leading,spacing:24) {
                    HStack { VStack(alignment:.leading,spacing:6) { Text(store.selected).font(.system(size:32,weight:.semibold,design:.rounded)); Text(subtitle).foregroundStyle(.secondary) }; Spacer(); Text(store.selected == "Apple Casa" ? "PONTE HOMEKIT" : store.selected == "Infravermelho" ? (store.tuyaReady ? "TUYA CONECTADA" : "CONECTAR TUYA") : store.selected == "Visão geral" ? (store.demo ? "DEMONSTRAÇÃO" : "CONEXÃO REAL") : "CONFIGURAÇÃO").font(.caption.bold()).padding(9).background(.orange.opacity(0.12),in:Capsule()) }
                    if !store.greeConnectionError.isEmpty { Label(store.greeConnectionError,systemImage:"wifi.exclamationmark").foregroundStyle(.orange) }
                    if !store.error.isEmpty { Label(store.error,systemImage:"exclamationmark.triangle").foregroundStyle(.red).textSelection(.enabled) }
                    switch store.selected {
                    case "Infravermelho": InfraredSetupView()
                    case "Apple Casa": AppleHomeSetupView()
                    case "Dispositivos": inventory
                    case "Ecossistema": ecosystem
                    case "Conexão": connection
                    case "Primeiros passos": steps
                    default: overview
                    }
                }.padding(32)
            }.background(CasaStyle.background)
        }.onChange(of:store.devices) { store.persist() }
        .toolbar { ToolbarItem { Button { openWindow(id:"quick") } label:{ Label("Controle rápido",systemImage:"rectangle.topthird.inset.filled") } } }
    }
    var subtitle:String { switch store.selected { case "Infravermelho": return "Do pareamento no Smart Life à integração do escritório."; case "Apple Casa": return "Seus aparelhos no iPhone, no Casa e na Siri."; case "Dispositivos": return "Cadastre os aparelhos e vincule as entidades da central."; case "Ecossistema":return "Cada camada tem uma responsabilidade."; case "Conexão":return "Uma conexão com a central. Seus dispositivos em um só lugar."; case "Primeiros passos":return "Do primeiro ar-condicionado aos oito dispositivos."; default:return "Conforto e controle, direto do seu Mac." } }
    var overview:some View {
        VStack(alignment:.leading,spacing:24) {
            HStack(spacing:16) { metric("8", "Espaços de dispositivos", "square.grid.2x2"); metric("\(store.devices.filter{ !$0.entity.isEmpty }.count)","Entidades vinculadas","link"); metric(store.demo ? "Demo" : String(store.devices.filter{store.available($0)}.count),store.demo ? "Modo de controle" : "Aparelhos disponíveis","network") }
            HStack { Text("Seus ambientes").font(.title2.bold()); Spacer(); Button("Gerenciar dispositivos") { store.selected = "Dispositivos" } }
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:16) {
                ForEach(store.devices.filter { $0.kind != "unknown" }) { device in
                    VStack(alignment:.leading,spacing:18) {
                        HStack { Image(systemName:device.icon).font(.title2).foregroundStyle(CasaStyle.accent); Spacer(); Text(device.room).font(.caption).foregroundStyle(.secondary) }
                        Text(device.name).font(.system(size:18,weight:.semibold))
                        if device.kind == "climate" { AirConditionerArt(temperature:device.temperature,flowing:device.on && store.available(device)).frame(height:125) }
                        HStack { Text(device.kind == "climate" ? "\(Int(device.temperature))°" : "Echo").font(.system(size:38,weight:.light,design:.rounded)); Spacer(); Button { Task { await store.change(device.id) } } label: { Image(systemName:"power").padding(10) }.disabled(store.busy || !store.available(device)) }
                        if device.kind == "climate" { ClimateControls(device:device) }
                        Text(store.demo ? "Simulação · \(device.on ? "ligado" : "desligado")" : device.entity.isEmpty ? "Aguardando vínculo" : (store.states.first{$0.entity_id == device.entity}?.state ?? "Sem estado")).font(.caption).foregroundStyle(.secondary)
                    }.padding(24).background(LinearGradient(colors:[CasaStyle.accent.opacity(0.065),CasaStyle.surface],startPoint:.topLeading,endPoint:.bottomTrailing),in:RoundedRectangle(cornerRadius:26)).overlay(RoundedRectangle(cornerRadius:26).stroke(.white.opacity(0.16)))
                }
            }
            if !store.activity.isEmpty {
                VStack(alignment:.leading,spacing:8) { Text("Atividade recente").font(.headline); ForEach(Array(store.activity.prefix(5).enumerated()),id:\.offset) { _, line in Text(line).font(.caption).foregroundStyle(.secondary) } }.frame(maxWidth:.infinity,alignment:.leading)
            }
            Button("Adicionar ou vincular aparelho") { store.selected = "Dispositivos" }.buttonStyle(.borderedProminent)
            HStack(spacing:16) {
                Button { store.selected = "Infravermelho" } label: { info("Escritório · infravermelho", "LQ‑Y06 · Smart Life/Tuya. Configure e valide os comandos.", "dot.radiowaves.left.and.right") }.buttonStyle(.plain)
                Button { store.selected = "Apple Casa" } label: { info("iPhone e Siri", "Pareie a ponte HomeKit para controlar pelo Casa.", "house.fill") }.buttonStyle(.plain)
            }
        }
    }
    func metric(_ value:String,_ label:String,_ icon:String) -> some View { VStack(alignment:.leading,spacing:12) { Image(systemName:icon).foregroundStyle(CasaStyle.accent); Text(value).font(.title.bold()); Text(label).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth:.infinity,alignment:.leading).padding(18).background(CasaStyle.surface,in:RoundedRectangle(cornerRadius:22)).overlay(RoundedRectangle(cornerRadius:22).stroke(.white.opacity(0.05))) }
    func info(_ title:String,_ text:String,_ icon:String) -> some View { HStack(alignment:.top,spacing:16) { Image(systemName:icon).font(.title2).foregroundStyle(CasaStyle.accent); VStack(alignment:.leading,spacing:8) { Text(title).font(.headline); Text(text).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true) } }.frame(maxWidth:.infinity,alignment:.leading).padding(20).background(CasaStyle.surface,in:RoundedRectangle(cornerRadius:22)).overlay(RoundedRectangle(cornerRadius:22).stroke(.white.opacity(0.05))) }
    var inventory:some View {
        VStack(spacing:16) {
            if store.demo {
                info("Escolha a conexão do aparelho", "Gree+ usa busca direta no Wi-Fi. O LQ‑Y06 do escritório começa no Smart Life. Para outras marcas, configure a central compatível.", "network")
                Button("Configurar conexão") { store.selected = "Conexão" }.buttonStyle(.borderedProminent)
            } else {
                VStack(alignment:.leading,spacing:12) {
                    HStack { Text("Encontrados na sua central").font(.title2.bold()); Spacer(); Button("Buscar novamente") { Task { await store.refresh() } }.disabled(store.busy) }
                    TextField("Buscar por nome ou identificador",text:$store.search).textFieldStyle(.roundedBorder)
                    ForEach(store.states.filter { ["climate","media_player","switch","light"].contains($0.entity_id.components(separatedBy:".")[0]) && (store.search.isEmpty || ($0.attributes.friendly_name ?? "").localizedCaseInsensitiveContains(store.search) || $0.entity_id.localizedCaseInsensitiveContains(store.search)) },id:\.entity_id) { state in
                        HStack { VStack(alignment:.leading) { Text(state.attributes.friendly_name ?? state.entity_id); Text(state.entity_id).font(.caption).foregroundStyle(.secondary) }; Spacer(); Button(store.devices.contains{$0.entity == state.entity_id} ? "Adicionado" : "Adicionar") { store.importEntity(state) }.disabled(store.devices.contains{$0.entity == state.entity_id}) }
                    }
                    if store.states.isEmpty { Text("Nenhuma entidade disponível. Verifique a conexão e as integrações na central.").foregroundStyle(.secondary) }
                }.padding(20).background(CasaStyle.surface,in:RoundedRectangle(cornerRadius:22)).overlay(RoundedRectangle(cornerRadius:22).stroke(.white.opacity(0.05)))
            }
            ForEach($store.devices) { $device in
                VStack(alignment:.leading,spacing:12) {
                    HStack { Image(systemName:device.icon).foregroundStyle(CasaStyle.accent); Text("Dispositivo \(device.id)").font(.headline); Spacer(); Text(device.entity.isEmpty ? "A configurar" : "Vínculo salvo").font(.caption).foregroundStyle(.secondary) }
                    HStack { TextField("Nome",text:$device.name); Picker("Cômodo",selection:$device.room) { ForEach(Array(Set([device.room,"Escritório","Quarto","Sala","Cozinha","Varanda","A confirmar"])).sorted(),id:\.self) { Text($0).tag($0) } } }
                    HStack { TextField("Marca e modelo",text:$device.brand); Picker("Tipo",selection:$device.kind) { Text("A definir").tag("unknown"); Text("Ar-condicionado").tag("climate"); Text("Echo / mídia").tag("media_player"); Text("Interruptor / tomada").tag("switch"); Text("Luz").tag("light") }.frame(width:250) }
                    Picker("Entidade Home Assistant",selection:$device.entity) {
                        Text("Sem vínculo").tag("")
                        if !device.entity.isEmpty && !store.states.contains(where:{$0.entity_id == device.entity}) { Text(device.entity + " · não encontrada").tag(device.entity) }
                        ForEach(store.states.filter{$0.entity_id.hasPrefix(device.kind + ".")},id:\.entity_id) { state in Text(state.attributes.friendly_name ?? state.entity_id).tag(state.entity_id) }
                    }
                }.textFieldStyle(.roundedBorder).padding(18).background(CasaStyle.surface,in:RoundedRectangle(cornerRadius:22)).overlay(RoundedRectangle(cornerRadius:22).stroke(.white.opacity(0.05)))
            }
        }
    }
    var ecosystem:some View {
        VStack(spacing:16) {
            info("01 · Interface no Mac", "Este app mostra ambientes, dispositivos e controles. O menu perto da bateria permite acesso rápido. Demonstração e operação real ficam identificadas.","macbook")
            info("02 · Regras e capacidades", "Cada dispositivo tem identidade, cômodo, tipo e entidade. Comandos dependem das capacidades expostas pela integração. Estado recebido e comando enviado são coisas diferentes.","slider.horizontal.3")
            info("03 · Home Assistant", "Central que integra marcas e recebe os comandos do app pela API. Os estados são consultados a cada oito segundos e após comandos. Precisa permanecer ligado e acessível.","network")
            info("04 · Controladores e aparelhos", "Wi-Fi, infravermelho e outros protocolos são tratados pelas integrações da central. Um emissor IR precisa alcançar o aparelho; comandos IR não garantem confirmação do estado físico.","dot.radiowaves.left.and.right")
            info("05 · Apple Casa e Siri", "O HomeKit Bridge do Home Assistant publica entidades compatíveis no Apple Casa. O pareamento acontece pelo Casa, com o código da ponte. Este app não faz o pareamento e não transforma o Echo em HomePod.","house.fill")
            info("06 · Echo / Echo Dot", "Há dois fluxos: Alexa controlar os aparelhos da casa; e o Home Assistant controlar funções do Echo pela integração Alexa Devices. A disponibilidade depende do modelo, conta e entidades expostas pela Amazon.","hifispeaker.fill")
            Link("Documentação: Apple Casa / HomeKit Bridge",destination:URL(string:"https://www.home-assistant.io/integrations/homekit/")!)
            Link("Documentação: Alexa Devices",destination:URL(string:"https://www.home-assistant.io/integrations/alexa_devices/")!)
        }
    }
    var connection:some View {
        VStack(alignment:.leading,spacing:20) {
            VStack(alignment:.leading,spacing:16) {
                Label("Gree+ · conexão direta",systemImage:"wifi").font(.title2.bold())
                Text("Para o ar do quarto, comece aqui. Não precisa de Home Assistant nem da senha do Gree+. O aparelho precisa estar cadastrado no Gree+ e na mesma rede do Mac.").foregroundStyle(.secondary)
                HStack { TextField("IP do aparelho (opcional)",text:$store.greeTarget).textFieldStyle(.roundedBorder); Button(store.busy ? "Aguarde…" : "Buscar Gree no Wi-Fi") { Task { await store.scanGree() } }.buttonStyle(.borderedProminent).disabled(store.busy) }
                Text(store.greeStatus).font(.caption).foregroundStyle(.secondary)
                Picker("Cômodo",selection:$store.greeRoom) { Text("Quarto").tag("Quarto"); Text("Escritório").tag("Escritório"); Text("Sala").tag("Sala") }.frame(maxWidth:300)
                ForEach(store.greePeers) { peer in HStack { VStack(alignment:.leading) { Text(peer.name).font(.headline); Text(peer.host + " · Gree LAN V" + String(peer.version)).font(.caption).foregroundStyle(.secondary) }; Spacer(); Button("Conectar") { Task { await store.bindGree(peer) } }.disabled(store.busy) } }
                Text("O app reconecta automaticamente os aparelhos já cadastrados e tenta recuperar falhas temporárias. Apple Casa tem seu próprio pareamento.").font(.caption).foregroundStyle(.secondary)
            }.padding(24).background(.blue.opacity(0.08),in:RoundedRectangle(cornerRadius:22))
            Divider()
            info("Você usa o Casa da Apple?", "Casa e Home Assistant são aplicativos diferentes. Ter o Casa instalado não significa ter uma central Home Assistant. Primeiro identificamos o aplicativo do seu infravermelho; depois conectamos pela integração compatível. Nenhum token é necessário enquanto essa central não existir.", "house.fill")
            Link("Como instalar Home Assistant no Mac",destination:URL(string:"https://www.home-assistant.io/installation/macos/")!)
            Text("No Mac, o Home Assistant OS funciona em uma máquina virtual. A orientação oficial pede ao menos 2 GB de memória, 2 processadores virtuais e rede em modo bridge. A instalação é uma etapa separada e o Mac precisa permanecer acordado para servir de central.").font(.callout).foregroundStyle(.secondary)
            info("Já instalou a central? Conecte aqui", "Use o endereço da central na sua rede e um token de acesso de longa duração. O token é salvo no Chaves do macOS após uma conexão válida. Não cole senhas da Apple ou Amazon aqui.","lock.shield")
            TextField("http://homeassistant.local:8123",text:$store.server).textFieldStyle(.roundedBorder)
            SecureField("Token de acesso • deixe vazio para usar o salvo",text:$store.token).textFieldStyle(.roundedBorder)
            HStack { Button(store.busy ? "Conectando…" : "Conectar e buscar entidades") { Task { await store.connect() } }.buttonStyle(.borderedProminent).disabled(store.busy); Button("Usar demonstração") { store.refreshTask?.cancel(); store.greeSessions = [:]; store.demo = true; store.states = []; store.status = "Demonstração • nenhum aparelho conectado"; store.error = "" }.disabled(store.busy) }
            Text(store.status).font(.callout).foregroundStyle(.secondary)
            if let date = store.lastSync { Text("Última consulta: \(date.formatted(date:.omitted,time:.standard))").font(.caption).foregroundStyle(.secondary) }
            HStack { Link("Abrir Home Assistant",destination:URL(string:store.server) ?? URL(string:"http://homeassistant.local:8123")!); Link("Criar token no perfil",destination:(URL(string:store.server) ?? URL(string:"http://homeassistant.local:8123")!).appendingPathComponent("profile/security")) }
            Text("Não tem Home Assistant? Precisamos instalar a central e integrar seu infravermelho antes de buscar os aparelhos. A lista é importada da central, não diretamente da Alexa.").foregroundStyle(.secondary)
            Text("Depois de conectar, abra Dispositivos e escolha a entidade correspondente a cada aparelho. A conexão é direta com o endereço informado; nenhum serviço intermediário é usado pelo app.").foregroundStyle(.secondary)
        }
    }
    var steps:some View {
        VStack(spacing:16) {
            info("1. Identificar", "Anote marca e modelo do infravermelho, nome do aplicativo atual, modelos dos dois aparelhos de ar e geração do Echo. Cadastre os outros cinco dispositivos.","1.circle")
            info("2. Preparar a central", "Escolha um equipamento para o Home Assistant ficar ligado. Configure a integração compatível com seu controlador. Valide ligar, desligar e temperatura de um único ar.","2.circle")
            info("3. Conectar o Mac", "Na tela Conexão, informe URL e token. Vincule as entidades em Dispositivos. Teste um comando e confira o resultado no aparelho físico.","3.circle")
            info("4. Ativar Apple Casa", "Configure HomeKit Bridge na central, selecione as entidades compatíveis e faça o pareamento no Casa. Teste um comando pela Siri.","4.circle")
            info("5. Integrar o Echo e expandir", "Configure Alexa Devices no Home Assistant para funções do Echo. O caminho inverso — comandos de voz Alexa para a casa — exige sua própria configuração. Repita a validação para os oito aparelhos.","5.circle")
        }
    }
}
extension Appliance: Equatable {}

struct ClimateControls: View {
    @EnvironmentObject var store: HomeStore
    let device: Appliance
    var compact = false
    var temperature: Double { store.drafts[device.id] ?? device.temperature }
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack { Text("Temperatura desejada").font(.caption).foregroundStyle(.secondary); Spacer(); Text(temperature.formatted(.number.precision(.fractionLength(0...1))) + "°").font(.title3.bold()).monospacedDigit() }
            Slider(value:Binding(get:{ min(store.bounds(device).upperBound,max(store.bounds(device).lowerBound,temperature)) },set:{ store.drafts[device.id] = $0 }),in:store.bounds(device),step:store.step(device),onEditingChanged:{ editing in if !editing { let value = temperature; Task { await store.change(device.id,temperature:value) } } }).tint(.cyan).disabled(store.busy || !store.supports(device,"set_temperature"))
            HStack { Text("\(Int(store.bounds(device).lowerBound))°"); Spacer(); Text("Arraste para ajustar"); Spacer(); Text("\(Int(store.bounds(device).upperBound))°") }.font(.caption2).foregroundStyle(.secondary)
            if let current = store.state(device)?.attributes.current_temperature { Text("Ambiente agora · " + current.formatted() + "°").font(.caption).foregroundStyle(.secondary) }
            if !compact {
                ExtraClimateControls(device:device)
                if store.supports(device,"set_hvac_mode") {
                    Picker("Modo",selection:Binding(get:{ store.demo ? store.demoModes[device.id] ?? (device.on ? "cool" : "off") : store.state(device)?.state ?? "off" },set:{ mode in Task { await store.command(device.id,service:"set_hvac_mode",value:mode) } })) {
                        ForEach(store.modes(device),id:\.self) { Text(modeLabel($0)).tag($0) }
                    }.disabled(store.busy)
                }
                let fans = store.demo ? ["auto","low","medium","high"] : store.state(device)?.attributes.fan_modes ?? []
                if !fans.isEmpty {
                    Menu { ForEach(fans,id:\.self) { mode in Button(mode) { Task { await store.command(device.id,service:"set_fan_mode",value:mode) } } } } label: { Label("Ventilação · " + (store.state(device)?.attributes.fan_mode ?? "Selecionar"),systemImage:"fan") }.disabled(store.busy || !store.supports(device,"set_fan_mode"))
                }
                let swings = store.demo ? ["off","on"] : store.state(device)?.attributes.swing_modes ?? []
                if !swings.isEmpty {
                    Menu { ForEach(swings,id:\.self) { mode in Button(mode) { Task { await store.command(device.id,service:"set_swing_mode",value:mode) } } } } label: { Label("Oscilação · " + (store.state(device)?.attributes.swing_mode ?? "Selecionar"),systemImage:"wind") }.disabled(store.busy || !store.supports(device,"set_swing_mode"))
                }
            }
        }
    }
    func modeLabel(_ mode:String) -> String { ["off":"Desligado","cool":"Resfriar","heat":"Aquecer","dry":"Desumidificar","fan_only":"Ventilar","auto":"Automático","heat_cool":"Aquecer / resfriar"][mode] ?? mode }
}
