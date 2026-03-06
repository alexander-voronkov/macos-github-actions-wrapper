import Foundation
import ServiceManagement

final class LaunchAtLoginService {
    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    func isEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }
}
