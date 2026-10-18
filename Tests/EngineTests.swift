import Foundation

final class MockProtocol: URLProtocol {
    static var received: [URLRequest] = []
    static var reject = false
    static let fixture = """
    [{"entity_id":"climate.office","state":"cool","attributes":{"friendly_name":"Ar escritório","temperature":23,"current_temperature":27,"min_temp":18,"max_temp":28,"target_temp_step":0.5,"supported_features":393,"hvac_modes":["off","cool"],"fan_modes":["auto","low"],"fan_mode":"auto","swing_modes":["off","on"]}}]
    """
    override class func canInit(with request:URLRequest) -> Bool { true }
    override class func canonicalRequest(for request:URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.received.append(request)
        let code = Self.reject ? 401 : 200
        let text = request.httpMethod == "POST" ? "[]" : Self.fixture
        client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:code,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:Data(text.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@main struct EngineTests {
    @MainActor static func main() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockProtocol.self]
        let store = HomeStore(session:URLSession(configuration:config),credentialProvider:{ "test-token" })
        store.demo = false; store.connectedServer = store.server
        store.states = try JSONDecoder().decode([HAState].self,from:Data(MockProtocol.fixture.utf8))
        store.devices = [Appliance(id:"test",name:"Office",room:"Escritório",kind:"climate",entity:"climate.office")]
        store.services = ["climate.set_temperature","climate.set_hvac_mode","climate.set_fan_mode","climate.set_swing_mode"]
        store.sync()
        precondition(store.devices[0].on && store.devices[0].temperature == 23)
        precondition(store.bounds(store.devices[0]) == 18...28)
        await store.change("test",temperature:50)
        let post = MockProtocol.received.first{$0.httpMethod == "POST"}!
        precondition(post.url!.path == "/api/services/climate/set_temperature")
        precondition(post.value(forHTTPHeaderField:"Authorization") == "Bearer test-token")
        var bodyData = post.httpBody
        if bodyData == nil, let stream = post.httpBodyStream {
            stream.open(); var data = Data(); var bytes = [UInt8](repeating:0,count:4096)
            while stream.hasBytesAvailable { let count = stream.read(&bytes,maxLength:bytes.count); if count <= 0 { break }; data.append(contentsOf:bytes.prefix(count)) }; stream.close(); bodyData = data
        }
        let body = try JSONSerialization.jsonObject(with:bodyData!) as! [String:Any]
        precondition(body["temperature"] as? Double == 28)
        precondition(body["entity_id"] as? String == "climate.office")
        let count = MockProtocol.received.count
        await store.command("test",service:"set_hvac_mode",value:"heat")
        precondition(MockProtocol.received.count == count)
        await store.command("test",service:"set_fan_mode",value:"invalid")
        precondition(MockProtocol.received.count == count)
        await store.command("test",service:"set_fan_mode",value:"low")
        precondition(MockProtocol.received.contains{$0.url!.path == "/api/services/climate/set_fan_mode"})
        MockProtocol.reject = true
        await store.change("test",temperature:22)
        precondition(!store.error.isEmpty && !store.busy)
        MockProtocol.reject = false
        await store.refresh()
        precondition(store.lastSync != nil)
        store.states[0].state = "unavailable"
        precondition(!store.available(store.devices[0]))
        let packet:[String:Any] = ["mac":"abc","t":"status"]
        let encrypted = try GreeWire.encode(packet,key:GreeWire.key(1),version:1)
        precondition(encrypted["pack"] as? String == "FZpALaUofWbTdBcYLKhuzO6qR3yFSMuoUolyXaSW9ew=")
        for version in [1,2] {
            let encrypted = try GreeWire.encode(packet,key:GreeWire.key(version),version:version)
            let decrypted = try GreeWire.decode(encrypted,key:GreeWire.key(version),version:version)
            precondition(decrypted["mac"] as? String == "abc")
        }
        var tampered = try GreeWire.encode(packet,key:GreeWire.key(2),version:2)
        tampered["tag"] = Data(repeating:0,count:16).base64EncodedString()
        do { _ = try GreeWire.decode(tampered,key:GreeWire.key(2),version:2); preconditionFailure("Invalid GCM tag accepted") } catch {}
        let greeTemp = try HomeStore.greeCommand(service:"set_temperature",value:nil,number:99,on:true)
        precondition(greeTemp["SetTem"] == 30 && greeTemp["TemUn"] == 0)
        let greeCool = try HomeStore.greeCommand(service:"set_hvac_mode",value:"cool",number:nil,on:false)
        precondition(greeCool["Pow"] == 1 && greeCool["Mod"] == 1)
        let greeOff = try HomeStore.greeCommand(service:"turn_off",value:nil,number:nil,on:true)
        precondition(greeOff == ["Pow":0])
        print("PASS: Gree ECB known-answer vector, V1/V2 encoding, GCM authentication, temperature clamping, mode and power command mapping")
        print("PASS: state decoding, physical limits, auth, endpoint/body, unsupported modes, ventilation, HTTP failure, refresh, unavailable-device guard")
    }
}
