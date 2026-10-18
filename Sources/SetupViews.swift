import SwiftUI
import AppKit

enum CasaStyle {
    static let background = Color(red:0.055,green:0.063,blue:0.08)
    static let surface = Color(red:0.095,green:0.105,blue:0.125)
    static let accent = Color(red:0.40,green:0.82,blue:1)
}
struct SetupCard<Content:View>:View {
    let number:String; let title:String; let subtitle:String
    @ViewBuilder var content:()->Content
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            HStack(alignment:.top,spacing:14) {
                Text(number).font(.system(size:12,weight:.bold,design:.rounded)).foregroundStyle(CasaStyle.accent).frame(width:34,height:34).background(CasaStyle.accent.opacity(0.1),in:RoundedRectangle(cornerRadius:11))
                VStack(alignment:.leading,spacing:5) { Text(title).font(.system(size:18,weight:.semibold)); Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true) }
            }
            content()
        }.padding(24).frame(maxWidth:.infinity,alignment:.leading).background(CasaStyle.surface,in:RoundedRectangle(cornerRadius:23)).overlay(RoundedRectangle(cornerRadius:23).stroke(.white.opacity(0.06)))
    }
}
struct InfraredSetupView:View {
    @EnvironmentObject var store:HomeStore
    private var accountLinked: Bool { accountAuthorizationExists() }
    var body:some View {
        VStack(spacing:18) {
            SetupCard(number:"1",title:"Sua conta Tuya",subtitle:accountLinked ? "Autorização encontrada neste Mac" : "Conecte a conta que você já usa no celular") {
                Label(accountLinked ? "Conta autorizada" : "Aguardando conexão",systemImage:accountLinked ? "checkmark.circle.fill" : "qrcode").foregroundStyle(accountLinked ? .green : CasaStyle.accent)
                Text(accountLinked ? "Você já autorizou o acesso pelo celular. Não precisa repetir o QR." : "Use o mesmo aplicativo que já controla seus aparelhos. A conexão é feita por QR Code.").foregroundStyle(.secondary)
                if !accountLinked { Button("Conectar Tuya") { NSWorkspace.shared.open(URL(string:"http://127.0.0.1:8581/plugins")!) } }
            }
            SetupCard(number:"2",title:"Ar do escritório",subtitle:"Smart IR · controle pelo Tuya funcionando") {
                Label(store.tuyaReady ? "Pronto para controlar" : "Conexão necessária",systemImage:store.tuyaReady ? "checkmark.circle.fill" : "clock").foregroundStyle(store.tuyaReady ? .green : .orange)
                Text("Ligar, desligar, temperatura, modo e ventilação estão integrados. Turbo e oscilação não foram anunciados pela Tuya para este controle.").foregroundStyle(.secondary)
                Button(store.busy ? "Conectando…" : "Conectar escritório") { Task { await store.connectTuya() } }.disabled(store.busy)
                if let device = store.devices.first(where:{$0.entity == "climate.tuya_office"}), store.tuyaReady { ClimateControls(device:device) }
            }
            SetupCard(number:"3",title:"Como saber se funciona",subtitle:"Conta conectada e aparelho controlável são estados diferentes") {
                Text("O controle só será liberado quando o aplicativo tiver comandos disponíveis. Um aparelho encontrado não será apresentado como pronto para uso.").foregroundStyle(.secondary)
            }
        }
    }
    private func accountAuthorizationExists() -> Bool {
        let folders = AppPaths.storageFolders
        return folders.contains { folder in
            ((try? FileManager.default.contentsOfDirectory(atPath:folder.path)) ?? []).contains { $0.hasPrefix("tuya-ha-qr-auth.") && $0.hasSuffix(".json") }
        }
    }
}
struct AppleHomeSetupView:View {
    @EnvironmentObject var store:HomeStore
    var body:some View {
        VStack(spacing:18) {
            SetupCard(number:"⌂",title:"Sua casa também no iPhone",subtitle:"O Casa controla acessórios HomeKit/Matter. A ponte no Mac conecta os controles compatíveis ao Casa.") {
                HStack(spacing:10) { flow("Ar Gree","air.conditioner.horizontal"); Image(systemName:"arrow.left.arrow.right").foregroundStyle(.secondary); flow("Homebridge","network"); Image(systemName:"arrow.left.arrow.right").foregroundStyle(.secondary); flow("Casa + Siri","house.fill") }.frame(maxWidth:.infinity)
                Text("O CasaMenu mantém o controle direto pelo Wi-Fi. O Homebridge publica o mesmo ar para o ecossistema Apple. Não é necessário informar sua senha da Apple ao nosso aplicativo.").font(.callout).foregroundStyle(.secondary)
            }
            SetupCard(number:"01",title:"Ponte HomeKit",subtitle:store.bridgeStatus) {
                HStack { Button("Iniciar ponte local") { let script = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("HomeKit/start.command"); if FileManager.default.fileExists(atPath:script.path) { NSWorkspace.shared.open(script) } else { store.bridgeStatus = "Mantenha a pasta HomeKit junto do aplicativo para iniciar a ponte." } }; Button("Verificar ponte") { Task { await store.checkBridge() } }; Button("Abrir painel Homebridge") { NSWorkspace.shared.open(URL(string:"http://127.0.0.1:8581")!) }.buttonStyle(.borderedProminent).tint(CasaStyle.accent) }
                Text("O painel local gerencia a ponte. Instalação e execução não comprovam que o acessório já foi pareado no Casa.").font(.caption).foregroundStyle(.secondary)
            }
            SetupCard(number:"02",title:"Adicionar no Casa do iPhone",subtitle:"Mantenha o iPhone e o Mac na mesma rede durante o pareamento.") {
                Text("Abra Casa → + → Adicionar acessório. Escaneie o QR da ponte no painel Homebridge. Como alternativa, toque em Mais opções, escolha CasaMenu e informe o código abaixo.").font(.callout).lineSpacing(5)
                if !store.homekitCode.isEmpty {
                    Text(store.homekitCode).font(.system(size:30,weight:.medium,design:.monospaced)).tracking(4).padding(18).frame(maxWidth:.infinity).background(.black.opacity(0.2),in:RoundedRectangle(cornerRadius:15)).textSelection(.enabled)
                    Text("Código privado desta ponte. Use somente no Casa para o pareamento.").font(.caption).foregroundStyle(.secondary)
                } else { Text("O código aparecerá quando a configuração local da ponte estiver disponível.").font(.caption).foregroundStyle(.secondary) }
                Text("Se o Casa avisar que o acessório não é certificado, ele se refere à ponte de terceiros. O pareamento e a escolha dos cômodos são concluídos por você no iPhone.").font(.caption).foregroundStyle(.secondary)
            }
            SetupCard(number:"03",title:"Controle local, Siri e acesso remoto",subtitle:"Compatibilidade depende do aparelho e das funções publicadas.") {
                Text("Depois do pareamento, o quarto aparece com os controles Gree e o escritório com ligar/desligar. Temperatura, modo e ventilação do escritório continuam no CasaMenu. Para controle fora de casa, compartilhamento e automações, configure HomePod ou Apple TV como central da casa.").font(.callout).lineSpacing(5)
                Text("O Mac que executa Homebridge precisa permanecer ligado, acordado e na rede. Um Echo não substitui a central Apple e não se transforma em HomePod.").font(.caption).foregroundStyle(.secondary)
                Link("Centrais da casa · documentação Apple",destination:URL(string:"https://support.apple.com/pt-br/102557")!)
            }
        }.task { await store.checkBridge() }
    }
    func flow(_ title:String,_ icon:String)->some View { VStack(spacing:10) { Image(systemName:icon).font(.title2).foregroundStyle(CasaStyle.accent); Text(title).font(.caption) }.frame(maxWidth:.infinity).padding(.vertical,17).background(.white.opacity(0.03),in:RoundedRectangle(cornerRadius:15)) }
}
