import Foundation
import CryptoKit
import CommonCrypto
import Darwin

// Native implementation of the Gree LAN wire format; reference: cmroche/greeclimate.
struct GreePeer: Identifiable, Equatable {
    var id: String { mac }
    let mac: String
    let name: String
    let host: String
    let port: UInt16
    let version: Int
}
struct GreeSession {
    let peer: GreePeer
    let key: String
    let version: Int
}
enum GreeWire {
    static func key(_ version:Int) -> String { version == 1 ? "a3K8Bx%2r8Y7#xDh" : "{yxAHAY_Lm6pbC/<" }
    static let nonce = Data([0x54,0x40,0x78,0x44,0x49,0x67,0x5a,0x51,0x6c,0x5e,0x63,0x13])
    static func ecb(_ data:Data,key:String,decrypt:Bool) throws -> Data {
        let secret = Data(key.utf8)
        guard secret.count == 16 else { throw AppError.message("Chave Gree inválida.") }
        var output = Data(count:data.count+16); var written = 0
        let capacity = output.count
        let result = output.withUnsafeMutableBytes { out in data.withUnsafeBytes { input in secret.withUnsafeBytes { secret in
            CCCrypt(CCOperation(decrypt ? kCCDecrypt : kCCEncrypt),CCAlgorithm(kCCAlgorithmAES),CCOptions(kCCOptionECBMode | kCCOptionPKCS7Padding),secret.baseAddress,16,nil,input.baseAddress,data.count,out.baseAddress,capacity,&written)
        } } }
        guard result == kCCSuccess else { throw AppError.message("Resposta Gree não pôde ser decodificada.") }
        return output.prefix(written)
    }
    static func encode(_ object:[String:Any],key:String,version:Int) throws -> [String:Any] {
        let data = try JSONSerialization.data(withJSONObject:object,options:.sortedKeys)
        if version == 1 { return ["pack":try ecb(data,key:key,decrypt:false).base64EncodedString()] }
        let sealed = try AES.GCM.seal(data,using:SymmetricKey(data:Data(key.utf8)),nonce:AES.GCM.Nonce(data:nonce),authenticating:Data("qualcomm-test".utf8))
        return ["pack":sealed.ciphertext.base64EncodedString(),"tag":sealed.tag.base64EncodedString()]
    }
    static func decode(_ envelope:[String:Any],key:String,version:Int) throws -> [String:Any] {
        guard let pack = envelope["pack"] as? String, let data = Data(base64Encoded:pack) else { throw AppError.message("Pacote Gree inválido.") }
        let plain:Data
        if version == 1 { plain = try ecb(data,key:key,decrypt:true) }
        else {
            guard let rawTag = envelope["tag"] as? String, let tag = Data(base64Encoded:rawTag) else { throw AppError.message("Resposta Gree V2 sem autenticação; este firmware ainda não é compatível.") }
            let box = try AES.GCM.SealedBox(nonce:AES.GCM.Nonce(data:nonce),ciphertext:data,tag:tag)
            plain = try AES.GCM.open(box,using:SymmetricKey(data:Data(key.utf8)),authenticating:Data("qualcomm-test".utf8))
        }
        guard let object = try JSONSerialization.jsonObject(with:plain) as? [String:Any] else { throw AppError.message("Dados Gree inválidos.") }
        return object
    }
    static func envelope(_ content:[String:Any],mac:String,key:String,version:Int,bind:Bool = false) throws -> [String:Any] {
        var result: [String:Any] = ["cid":"app","uid":0,"i":bind ? 1 : 0,"t":"pack","tcid":mac]
        for (name,value) in try encode(content,key:key,version:version) { result[name] = value }
        return result
    }
}
final class GreeSocket {
    let fd:Int32
    init() throws {
        fd = socket(AF_INET,SOCK_DGRAM,IPPROTO_UDP)
        guard fd >= 0 else { throw AppError.message("Não foi possível acessar a rede local.") }
        var yes:Int32 = 1; setsockopt(fd,SOL_SOCKET,SO_BROADCAST,&yes,socklen_t(MemoryLayout.size(ofValue:yes)))
        var timeout = timeval(tv_sec:0,tv_usec:250_000)
        setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,socklen_t(MemoryLayout.size(ofValue:timeout)))
    }
    deinit { close(fd) }
    func send(_ object:[String:Any],host:String,port:UInt16 = 7000) throws {
        var address = sockaddr_in(); address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); address.sin_family = sa_family_t(AF_INET); address.sin_port = port.bigEndian
        guard inet_pton(AF_INET,host,&address.sin_addr) == 1 else { throw AppError.message("Informe o IP IPv4 do ar-condicionado.") }
        let bytes = try JSONSerialization.data(withJSONObject:object)
        let sent = bytes.withUnsafeBytes { data in withUnsafePointer(to:&address) { pointer in pointer.withMemoryRebound(to:sockaddr.self,capacity:1) { sendto(fd,data.baseAddress,bytes.count,0,$0,socklen_t(MemoryLayout<sockaddr_in>.size)) } } }
        guard sent == bytes.count else { throw AppError.message("Não foi possível enviar ao Gree \(host):\(port). Rede: \(String(cString:strerror(errno))). Confira a permissão de Rede Local e a conexão Wi-Fi.") }
    }
    func receive() -> ([String:Any],String,UInt16)? {
        var buffer = [UInt8](repeating:0,count:8192); var source = sockaddr_in(); var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let count = withUnsafeMutablePointer(to:&source) { ptr in ptr.withMemoryRebound(to:sockaddr.self,capacity:1) { recvfrom(fd,&buffer,buffer.count,0,$0,&length) } }
        guard count > 0, let json = try? JSONSerialization.jsonObject(with:Data(buffer.prefix(count))) as? [String:Any] else { return nil }
        var address = source.sin_addr; var text = [CChar](repeating:0,count:Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET,&address,&text,socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
        return (json,String(cString:text),UInt16(bigEndian:source.sin_port))
    }
    static func broadcasts() -> [String] {
        var head:UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return ["255.255.255.255"] }
        defer { freeifaddrs(head) }
        var current = head; var result:Set<String> = ["255.255.255.255"]
        while let entry = current {
            defer { current = entry.pointee.ifa_next }
            let value = entry.pointee
            guard value.ifa_flags & UInt32(IFF_UP) != 0, value.ifa_flags & UInt32(IFF_BROADCAST) != 0, let addr = value.ifa_addr, let mask = value.ifa_netmask, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let ip = UnsafeRawPointer(addr).assumingMemoryBound(to:sockaddr_in.self).pointee.sin_addr.s_addr
            let netmask = UnsafeRawPointer(mask).assumingMemoryBound(to:sockaddr_in.self).pointee.sin_addr.s_addr
            var broadcast = in_addr(s_addr:ip | ~netmask); var text = [CChar](repeating:0,count:Int(INET_ADDRSTRLEN))
            if inet_ntop(AF_INET,&broadcast,&text,socklen_t(INET_ADDRSTRLEN)) != nil { result.insert(String(cString:text)) }
        }
        return Array(result)
    }
}
enum GreeLAN {
    // Writes are absolute assignments, so retrying the same command is idempotent.
    static func recoveringExchange(_ session:GreeSession, values:[String:Int]? = nil) async throws -> (GreeSession,[String:Int]) {
        do { return (session,try await exchange(session,values:values)) }
        catch {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds:350_000_000)
            do { return (session,try await exchange(session,values:values)) }
            catch {
                let peers = try await discover()
                guard let peer = peers.first(where:{$0.mac.caseInsensitiveCompare(session.peer.mac) == .orderedSame}) else {
                    throw AppError.message("O ar do quarto está temporariamente sem conexão. Vou tentar reconectar automaticamente.")
                }
                let renewed = try await bind(peer)
                return (renewed,try await exchange(renewed,values:values))
            }
        }
    }

    static func discover(target:String = "") async throws -> [GreePeer] {
        try await Task.detached {
            let socket = try GreeSocket()
            var sent = false
            for address in target.isEmpty ? GreeSocket.broadcasts() : [target] { if (try? socket.send(["t":"scan"],host:address)) != nil { sent = true } }
            guard sent else { throw AppError.message("A busca na rede foi bloqueada. Verifique a permissão de Rede Local.") }
            let deadline = Date().addingTimeInterval(4); var found:[String:GreePeer] = [:]
            while Date() < deadline {
                guard let (outer,host,port) = socket.receive() else { continue }
                for version in [1,2] {
                    guard let inner = try? GreeWire.decode(outer,key:GreeWire.key(version),version:version), let mac = (inner["mac"] ?? inner["cid"]) as? String, !mac.isEmpty else { continue }
                    found[mac] = GreePeer(mac:mac,name:inner["name"] as? String ?? "Ar Gree",host:host,port:port,version:version); break
                }
            }
            return found.values.sorted{$0.name < $1.name}
        }.value
    }
    static func bind(_ peer:GreePeer) async throws -> GreeSession {
        try await Task.detached {
            let socket = try GreeSocket()
            for version in [peer.version,peer.version == 1 ? 2 : 1] {
                try socket.send(["t":"scan"],host:peer.host,port:peer.port)
                _ = socket.receive()
                let content:[String:Any] = ["t":"bind","mac":peer.mac,"uid":0]
                try socket.send(GreeWire.envelope(content,mac:peer.mac,key:GreeWire.key(version),version:version,bind:true),host:peer.host,port:peer.port)
                let deadline = Date().addingTimeInterval(3)
                while Date() < deadline {
                    guard let (outer,host,_) = socket.receive(), host == peer.host, let inner = try? GreeWire.decode(outer,key:GreeWire.key(version),version:version), inner["t"] as? String == "bindok", let key = inner["key"] as? String, key.utf8.count == 16 else { continue }
                    return GreeSession(peer:peer,key:key,version:version)
                }
            }
            throw AppError.message("O Gree não autorizou a conexão local. Confira o Wi-Fi e tente buscar novamente. Este firmware pode não ser compatível.")
        }.value
    }
    static func exchange(_ session:GreeSession,values:[String:Int]? = nil) async throws -> [String:Int] {
        try await Task.detached {
            let socket = try GreeSocket(); let peer = session.peer
            let columns = ["Pow","Mod","SetTem","TemUn","WdSpd","SwUpDn","SwingLfRig","Tur","Quiet","Lig","Blo","SwhSlp","SlpMod","Health","SvSt"]
            var content:[String:Any] = ["t":values == nil ? "status" : "cmd","mac":peer.mac]
            if let values { let keys = values.keys.sorted(); content["opt"] = keys; content["p"] = keys.map{values[$0]!} }
            else { content["cols"] = columns }
            try socket.send(GreeWire.envelope(content,mac:peer.mac,key:session.key,version:session.version),host:peer.host,port:peer.port)
            let deadline = Date().addingTimeInterval(4)
            while Date() < deadline {
                guard let (outer,host,_) = socket.receive(), host == peer.host, let inner = try? GreeWire.decode(outer,key:session.key,version:session.version) else { continue }
                let expected = values == nil ? "dat" : "res"
                guard (inner["t"] as? String)?.lowercased() == expected else { continue }
                let keys = (inner[values == nil ? "cols" : "opt"] as? [String]) ?? []
                let data = (inner[values == nil ? "dat" : "val"] as? [Int]) ?? (inner["p"] as? [Int]) ?? []
                guard !keys.isEmpty, keys.count == data.count else { continue }
                return Dictionary(uniqueKeysWithValues:zip(keys,data))
            }
            throw AppError.message(values == nil ? "O Gree não respondeu à consulta de estado." : "Sem confirmação do Gree. Confira o aparelho antes de repetir o comando.")
        }.value
    }
}
