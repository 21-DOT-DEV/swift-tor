import Testing
import libtor
@testable import Tor

/// Tor Tests
/// Note: tor_main_configuration_new() crashes in Swift Testing due to
/// unknown interaction between the test harness and Tor's C code.
/// The API works correctly when called from regular Swift code.
@Suite("Tor Tests", .serialized)
struct TorTests {
    
    @Test("TorController can be instantiated")
    func torControllerInstantiation() {
        let controller = TorController()
        _ = controller
    }
    
    @Test("tor_api_get_provider_version returns version string")
    func testProviderVersion() {
        let version = tor_api_get_provider_version()
        #expect(version != nil)
        
        if let version = version {
            let str = String(cString: version)
            print("Tor provider version: \(str)")
            #expect(str.contains("tor"))
        }
    }
    
    @Test("tor_main_configuration_new creates configuration")
    func testConfigurationNew() {
        let config = tor_main_configuration_new()
        #expect(config != nil)
        
        if let config = config {
            print("Configuration created successfully")
            tor_main_configuration_free(config)
            print("Configuration freed successfully")
        }
    }
}
