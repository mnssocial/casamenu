import SwiftUI
import AppKit

struct QuickPanel: View {
    @EnvironmentObject var store: HomeStore
    @Environment(\.openWindow) var openWindow
    private let cyan = Color(red:0.40,green:0.82,blue:1)
    var appliances: [Appliance] { store.devices.filter { $0.kind != "unknown" } }
    var active: Appliance? {
        appliances.first { $0.id == store.quickID }
        ?? appliances.first { !store.demo && store.available($0) && $0.kind == "climate" }
        ?? appliances.first { $0.room == "Quarto" }
        ?? appliances.first
    }
    var body: some View {
        VStack(spacing:0) {
            HStack(spacing:10) {
                Image(systemName:"house.fill").foregroundStyle(cyan)
                Text("Casa").font(.system(size:15,weight:.semibold))
                Spacer()
                Text(store.demo ? "DEMONSTRAÇÃO" : "CONECTADO").font(.system(size:9,weight:.bold,design:.rounded)).tracking(1.2).foregroundStyle(store.demo ? Color.orange : cyan)
                Button { openWindow(id:"main"); store.selected = "Conexão"; NSApp.activate(ignoringOtherApps:true) } label:{ Image(systemName:"slider.horizontal.3").frame(width:26,height:26) }.buttonStyle(.plain).help("Conectar e configurar aparelhos")
            }.padding(.horizontal,22).padding(.top,20).padding(.bottom,18)
            ScrollView(.horizontal,showsIndicators:false) {
                HStack(spacing:8) {
                    ForEach(appliances) { device in
                        Button { withAnimation(.easeInOut(duration:0.2)) { store.quickID = device.id } } label: {
                            HStack(spacing:6) { Image(systemName:device.icon).font(.caption); Text(device.room == "A confirmar" ? "Echo" : device.room).font(.system(size:12,weight:.medium)) }
                                .padding(.horizontal,13).padding(.vertical,9)
                                .background(active?.id == device.id ? cyan.opacity(0.17) : .white.opacity(0.04),in:Capsule())
                                .overlay(Capsule().stroke(active?.id == device.id ? cyan.opacity(0.35) : .white.opacity(0.05)))
                                .foregroundStyle(active?.id == device.id ? cyan : .white.opacity(0.55))
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal,22)
            }.padding(.bottom,18)
            if let device = active {
                if device.kind == "climate" { climate(device) }
                else {
                    VStack(spacing:18) { Image(systemName:device.icon).font(.system(size:64)).foregroundStyle(cyan); Text(device.name).font(.title2.bold()); Text(store.available(device) && !store.demo ? "Vinculado à central" : "Conecte este aparelho para habilitar os controles.").font(.callout).foregroundStyle(.secondary); Button("Configurar aparelho") { store.selected = "Dispositivos"; openWindow(id:"main") }.buttonStyle(.bordered) }.frame(height:360).frame(maxWidth:.infinity)
                }
            }
            if !store.greeConnectionError.isEmpty { Text(store.greeConnectionError).font(.caption).foregroundStyle(.orange).padding(.horizontal,22).padding(.bottom,12) }
            if !store.error.isEmpty { Text(store.error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal:false,vertical:true).padding(.horizontal,22).padding(.bottom,12) }
            Divider().overlay(.white.opacity(0.05))
            HStack(spacing:7) {
                Circle().fill(store.demo ? Color.orange : active.map { store.available($0) } == true ? Color.green : Color.gray).frame(width:5,height:5)
                Text(store.demo ? "Simulação · nenhum comando físico" : active.map { store.available($0) } == true ? "Conectado ao aparelho" : "Aguardando conexão").font(.system(size:10)).foregroundStyle(.white.opacity(0.45))
                Spacer()
                Button { Task { await store.refresh() } } label:{ Image(systemName:"arrow.clockwise").font(.system(size:11)) }.buttonStyle(.plain).disabled(store.busy || store.demo).help("Atualizar estado")
                Button { openWindow(id:"main"); NSApp.activate(ignoringOtherApps:true) } label:{ Image(systemName:"arrow.up.right.square").font(.system(size:11)) }.buttonStyle(.plain).help("Abrir central")
            }.padding(.horizontal,22).padding(.vertical,15)
        }
        .frame(width:390)
        .background {
            ZStack(alignment:.topTrailing) {
                Color(red:0.065,green:0.073,blue:0.09)
                Circle().fill(cyan.opacity(0.11)).frame(width:250,height:250).blur(radius:75).offset(x:110,y:50)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius:24))
        .overlay(RoundedRectangle(cornerRadius:24).stroke(.white.opacity(0.10)))
        .preferredColorScheme(.dark)
    }
    @ViewBuilder func climate(_ d:Appliance) -> some View {
        let value = store.drafts[d.id] ?? d.temperature
        let ready = store.available(d)
        VStack(alignment:.leading,spacing:0) {
            HStack(alignment:.top) {
                VStack(alignment:.leading,spacing:5) {
                    Text(d.name).font(.system(size:16,weight:.semibold))
                    Text(store.demo ? "Prévia dos controles" : d.brand.isEmpty ? "Ar-condicionado" : d.brand).font(.system(size:11)).foregroundStyle(.white.opacity(0.4))
                }
                Spacer()
                Button { Task { await store.change(d.id) } } label:{
                    Image(systemName:"power").font(.system(size:17,weight:.medium)).foregroundStyle(d.on && ready ? Color.black : Color.white.opacity(0.5)).frame(width:38,height:38)
                        .background(d.on && ready ? cyan : Color.white.opacity(0.08),in:Circle())
                        .shadow(color:d.on && ready ? cyan.opacity(0.35) : .clear,radius:12)
                }.buttonStyle(.plain).disabled(store.busy || !ready).help(d.on ? "Desligar ar" : "Ligar ar")
            }
            AirConditionerArt(temperature:value,flowing:d.on && ready).frame(height:154).padding(.top,7)
            HStack(alignment:.firstTextBaseline,spacing:3) {
                Text(value.formatted(.number.precision(.fractionLength(0...1)))).font(.system(size:64,weight:.light,design:.rounded)).contentTransition(.numericText()).monospacedDigit()
                Text("°C").font(.system(size:20,weight:.light)).foregroundStyle(.white.opacity(0.55))
                Spacer()
                VStack(alignment:.trailing,spacing:5) { Text("TEMPERATURA").font(.system(size:8,weight:.semibold)).tracking(1.5); Text("desejada").font(.system(size:11)) }.foregroundStyle(.white.opacity(0.3))
            }.padding(.bottom,13)
            HStack(spacing:10) {
                nudge(d,value:value,delta:-store.step(d),symbol:"minus")
                TemperatureTrack(value:Binding(get:{ store.drafts[d.id] ?? d.temperature },set:{ store.drafts[d.id] = $0 }),range:store.bounds(d),step:store.step(d)) { target in Task { await store.change(d.id,temperature:target) } }.frame(height:34).disabled(store.busy || !store.supports(d,"set_temperature"))
                nudge(d,value:value,delta:store.step(d),symbol:"plus")
            }
            HStack { Text(store.bounds(d).lowerBound.formatted() + "°"); Spacer(); Text("Arraste para ajustar"); Spacer(); Text(store.bounds(d).upperBound.formatted() + "°") }.font(.system(size:9)).foregroundStyle(.white.opacity(0.3)).padding(.horizontal,43).padding(.top,7).padding(.bottom,23)
            HStack(spacing:9) {
                PanelChoiceTile(id:d.id + ".mode",title:"Modo",value:modeName(store.demo ? store.demoModes[d.id] ?? (d.on ? "cool" : "off") : store.state(d)?.state ?? "off"),icon:"snowflake",choices:store.modes(d),label:modeName) { mode in Task { await store.command(d.id,service:"set_hvac_mode",value:mode) } }.disabled(store.busy || !store.supports(d,"set_hvac_mode"))
                let fans = store.demo ? ["auto","low","medium","high"] : store.state(d)?.attributes.fan_modes ?? []
                PanelChoiceTile(id:d.id + ".fan",title:"Ventilação",value:fanName(store.state(d)?.attributes.fan_mode ?? "auto"),icon:"fan",choices:fans,label:fanName) { fan in Task { await store.command(d.id,service:"set_fan_mode",value:fan) } }.disabled(store.busy || !store.supports(d,"set_fan_mode"))
                let swings = store.demo ? ["off","on"] : store.state(d)?.attributes.swing_modes ?? []
                PanelChoiceTile(id:d.id + ".swing",title:"Oscilação",value:swingName(store.state(d)?.attributes.swing_mode ?? "off"),icon:"wind",choices:swings,label:swingName) { swing in Task { await store.command(d.id,service:"set_swing_mode",value:swing) } }.disabled(store.busy || !store.supports(d,"set_swing_mode"))
            }.padding(.bottom,22)
            ExtraClimateControls(device:d)
            if !ready { Button("Conectar este aparelho") { store.selected = "Conexão"; openWindow(id:"main"); NSApp.activate(ignoringOtherApps:true) }.buttonStyle(.borderedProminent).tint(cyan).frame(maxWidth:.infinity).padding(.bottom,18) }
        }.padding(.horizontal,22)
    }
    func nudge(_ d:Appliance,value:Double,delta:Double,symbol:String) -> some View {
        Button { Task { await store.change(d.id,temperature:min(store.bounds(d).upperBound,max(store.bounds(d).lowerBound,value+delta))) } } label:{ Image(systemName:symbol).font(.system(size:12,weight:.medium)).frame(width:30,height:30).background(.white.opacity(0.07),in:Circle()) }.buttonStyle(.plain).disabled(store.busy || !store.supports(d,"set_temperature"))
    }
    func modeName(_ mode:String) -> String { ["off":"Desligado","cool":"Resfriar","heat":"Aquecer","dry":"Secar","fan_only":"Ventilar","auto":"Auto","heat_cool":"Auto quente/frio"][mode] ?? mode }
    func fanName(_ fan:String) -> String { ["auto":"Auto","low":"Baixa","medium_low":"Média baixa","medium":"Média","medium_high":"Média alta","high":"Alta"][fan] ?? fan }
    func swingName(_ swing:String) -> String { ["on":"Ligada","off":"Desligada"][swing] ?? swing }
}

struct TemperatureTrack: View {
    @Binding var value:Double
    let range:ClosedRange<Double>
    let step:Double
    var commit:(Double)->Void
    var fraction: Double { min(1,max(0,(value-range.lowerBound)/(range.upperBound-range.lowerBound))) }
    func target(_ x:Double,_ width:Double) -> Double { min(range.upperBound,max(range.lowerBound,((range.lowerBound+min(1,max(0,x/max(1,width)))*(range.upperBound-range.lowerBound))/step).rounded()*step)) }
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment:.leading) {
                Capsule().fill(.white.opacity(0.08))
                Capsule().fill(LinearGradient(colors:[.indigo,Color(red:0.39,green:0.82,blue:1)],startPoint:.leading,endPoint:.trailing)).frame(width:max(34,proxy.size.width*fraction))
                Capsule().fill(.white.opacity(0.75)).frame(width:3,height:13).offset(x:max(16,min(proxy.size.width-18,proxy.size.width*fraction-17)))
            }.contentShape(Capsule())
                .gesture(DragGesture(minimumDistance:0).onChanged { event in value = target(event.location.x,proxy.size.width) }.onEnded { event in let result = target(event.location.x,proxy.size.width); value = result; commit(result) })
        }
        .accessibilityElement().accessibilityLabel("Temperatura desejada").accessibilityValue(value.formatted() + " graus")
        .accessibilityAdjustableAction { direction in
            let result = min(range.upperBound,max(range.lowerBound,value + (direction == .increment ? step : -step))); value = result; commit(result)
        }
    }
}

struct AirConditionerArt: View {
    let temperature:Double
    let flowing:Bool
    var body: some View {
        VStack(spacing:0) {
            ZStack(alignment:.bottom) {
                RoundedRectangle(cornerRadius:16).fill(LinearGradient(colors:[.white,Color(white:0.77)],startPoint:.top,endPoint:.bottom)).frame(width:256,height:77).shadow(color:.black.opacity(0.5),radius:15,y:12)
                VStack {
                    HStack { Text("C A S A").font(.system(size:6,weight:.medium)).foregroundStyle(.gray.opacity(0.4)); Spacer(); Text(temperature.formatted(.number.precision(.fractionLength(0...1)))).font(.system(size:12,weight:.light,design:.monospaced)).foregroundStyle(flowing ? Color.cyan.opacity(0.6) : .gray.opacity(0.25)) }.padding(.horizontal,23).padding(.top,19)
                    Spacer()
                    Capsule().fill(Color(white:0.1)).frame(height:9).padding(.horizontal,14).padding(.bottom,7)
                }.frame(width:256,height:77)
                RoundedRectangle(cornerRadius:2).fill(Color(white:0.66)).frame(width:221,height:3).offset(y:2)
            }
            TimelineView(.animation(minimumInterval:0.05,paused:!flowing)) { context in
                Canvas { graphics,size in
                    guard flowing else { return }
                    let intensity = min(1,max(0,(30-temperature)/14))
                    let duration = 2.1 - intensity * 1.1
                    let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy:duration)/duration
                    for line in 0..<11 {
                        var path = Path()
                        let start = size.width/2 + CGFloat(line-5)*14
                        path.move(to:CGPoint(x:start,y:3))
                        path.addQuadCurve(to:CGPoint(x:start+CGFloat(line-5)*5,y:32+intensity*23),control:CGPoint(x:start+CGFloat(line-5)*2,y:20))
                        var layer = graphics
                        layer.opacity = (0.09 + intensity*0.17) * (0.7 + 0.3*sin(phase * .pi*2 + Double(line)*0.4))
                        layer.stroke(path,with:.linearGradient(Gradient(colors:[.cyan,.clear]),startPoint:CGPoint(x:0,y:0),endPoint:CGPoint(x:0,y:55)),style:StrokeStyle(lineWidth:0.9+intensity*0.9,dash:[8,8],dashPhase:-phase*32))
                    }
                }
            }.frame(height:58)
        }.frame(maxWidth:.infinity)
        .accessibilityLabel(flowing ? "Ilustração de ar-condicionado ligado" : "Ilustração de ar-condicionado desligado")
    }
}

struct PanelChoiceTile:View {
    @EnvironmentObject var store:HomeStore
    let id:String; let title:String; let value:String; let icon:String; let choices:[String]
    var label:(String)->String
    var action:(String)->Void
    var body:some View {
        Button { store.quickMenu = id } label: {
            VStack(alignment:.leading,spacing:5) {
                Image(systemName:icon).font(.system(size:16)).foregroundStyle(Color.cyan.opacity(0.8)).padding(.bottom,3)
                Text(title).font(.system(size:9)).foregroundStyle(.white.opacity(0.4))
                Text(value).font(.system(size:11,weight:.semibold)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
            }.frame(maxWidth:.infinity,alignment:.leading).padding(12)
                .background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:15))
                .overlay(RoundedRectangle(cornerRadius:15).stroke(.white.opacity(0.07)))
        }.buttonStyle(.plain)
            .popover(isPresented:Binding(get:{store.quickMenu == id},set:{ if !$0 { store.quickMenu = "" } })) {
                VStack(alignment:.leading,spacing:4) {
                    Text(title).font(.caption.bold()).foregroundStyle(.secondary).padding(8)
                    ForEach(choices,id:\.self) { item in Button { store.quickMenu = ""; action(item) } label: {
                        HStack { Text(label(item)); Spacer(); if label(item) == value { Image(systemName:"checkmark").foregroundStyle(.cyan) } }.padding(9).contentShape(Rectangle())
                    }.buttonStyle(.plain) }
                }.padding(8).frame(width:190).preferredColorScheme(.dark)
            }
    }
}
