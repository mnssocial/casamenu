import Foundation
import SwiftUI
struct TuyaSnapshot: Decodable, Sendable {
    var name: String?
    var on: Bool?
    var temperature: Double?
    var codes: [String]?
    var mode: String?
    var fan: String?
    var estimated: Bool?
    var error: String?
}
enum TuyaBridge {
    static func run(_ action:String = "status", temperature:Double? = nil, value:String? = nil) async throws -> TuyaSnapshot {
        return try await Task.detached {
            let folders = AppPaths.storageFolders
            guard let storage = folders.first(where:{ folder in ((try? FileManager.default.contentsOfDirectory(atPath:folder.path)) ?? []).contains(where:{$0.hasPrefix("tuya-ha-qr-auth.")}) }) else { throw AppError.message("Conecte sua conta Tuya para continuar.") }
            guard let node = AppPaths.node, let helper = AppPaths.bridgeFile("casamenu-tuya.cjs") else { throw AppError.message("O componente Tuya não está instalado. Reinstale o CasaMenu com seus componentes integrados.") }
            let process = Process(), output = Pipe()
            process.executableURL = node
            process.arguments = [helper.path,storage.path,action] + (temperature.map{[String(Int($0.rounded()))]} ?? value.map{[$0]} ?? [])
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard let result = try? JSONDecoder().decode(TuyaSnapshot.self,from:data) else { throw AppError.message("Não foi possível consultar a Tuya. Tente novamente.") }
            if let error = result.error { throw AppError.message(error) }
            return result
        }.value
    }
}
extension HomeStore {
    func connectTuya() async {
        guard !busy else { return }; busy = true; defer {busy = false}
        do {
            let result = try await TuyaBridge.run()
            guard let index = devices.firstIndex(where:{$0.entity == "climate.tuya_office"}) ?? devices.firstIndex(where:{$0.room == "Escritório" && $0.kind == "climate"}) else { return }
            devices[index].entity = "climate.tuya_office"; devices[index].brand = "Tuya · infravermelho"
            demo = false; tuyaReady = true; applyTuya(result); persist(); error = ""
            status = "Escritório conectado à Tuya"
        } catch { self.error = error.localizedDescription }
    }
    func applyTuya(_ result:TuyaSnapshot) {
        tuyaCodes = result.codes ?? []; tuyaEstimated = result.estimated ?? true
        let attrs = HAState.Attributes(temperature:result.temperature,min_temp:16,max_temp:30,target_temp_step:1,hvac_modes:["off","cool","heat","auto","fan_only","dry"],fan_modes:["auto","low","medium","high"],fan_mode:result.fan,supported_features:393)
        states.removeAll{$0.entity_id == "climate.tuya_office"}
        states.append(HAState(entity_id:"climate.tuya_office",state:result.on == true ? (result.mode ?? "cool") : "off",attributes:attrs)); sync(); lastSync = Date()
    }
}

extension HomeStore {
    func toggleGreeFeature(_ device:Appliance, key:String) async {
        guard !busy, let session = greeSessions[device.entity], let current = greeExtras[device.entity]?[key], current >= 0 else { return }
        busy = true; defer {busy = false}; error = ""
        let next = current == 0 ? (key == "Quiet" ? 2 : 1) : 0
        var values = [key:next]
        if key == "SwhSlp" { values["SlpMod"] = next }
        if key == "Tur", next == 1 { values["Quiet"] = 0 }
        if key == "Quiet", next != 0 { values["Tur"] = 0 }
        do {
            let (renewed,_) = try await GreeLAN.recoveringExchange(session,values:values)
            greeSessions[device.entity] = renewed
            let (updated,state) = try await GreeLAN.recoveringExchange(renewed)
            greeSessions[device.entity] = updated; applyGree(device.entity,values:state)
        } catch { greeConnectionError = "Não foi possível confirmar o recurso do quarto. A reconexão é automática." }
    }
}
struct ExtraClimateControls: View {
    @EnvironmentObject var store:HomeStore
    let device:Appliance
    private let options = [("Tur","Turbo","bolt.fill"),("Quiet","Silencioso","speaker.slash.fill"),("SwhSlp","Dormir","moon.fill"),("Lig","Luz do painel","lightbulb.fill"),("Blo","Secagem interna","wind"),("Health","Purificação","leaf.fill"),("SvSt","Economia","leaf"),("SwingLfRig","Oscilação lateral","arrow.left.and.right")]
    var body:some View {
        if device.entity == "climate.tuya_office" {
            Text("Turbo e oscilação não foram disponibilizados pela Tuya para este controle. Estado indicado pela nuvem ou pelo último comando enviado.").font(.caption).foregroundStyle(.secondary).padding(.bottom,12)
        } else if store.greeSessions[device.entity] != nil {
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:8) {
                ForEach(options,id:\.0) { option in
                    if let value = store.greeExtras[device.entity]?[option.0], value >= 0 {
                        Button { Task { await store.toggleGreeFeature(device,key:option.0) } } label: {
                            HStack { Image(systemName:option.2); Text(option.1).font(.caption); Spacer(); Circle().fill(value == 0 ? Color.gray : CasaStyle.accent).frame(width:6,height:6) }.padding(11).background(value == 0 ? Color.white.opacity(0.04) : CasaStyle.accent.opacity(0.12),in:RoundedRectangle(cornerRadius:12))
                        }.buttonStyle(.plain).disabled(store.busy)
                    }
                }
            }.padding(.bottom,12)
        }
    }
}

extension HomeStore {
    func restoreConnections() async {
        guard !busy else { return }
        if !tuyaReady { await connectTuya() }
        let known = devices.filter{$0.entity.hasPrefix("climate.gree_lan_")}
        if !known.isEmpty && greeSessions.isEmpty {
            await scanGree()
            for peer in greePeers {
                let entity = "climate.gree_lan_" + peer.mac.lowercased().filter{$0.isLetter || $0.isNumber}
                if let saved = known.first(where:{$0.entity == entity}) { greeRoom = saved.room; await bindGree(peer) }
            }
        }
    }
}
