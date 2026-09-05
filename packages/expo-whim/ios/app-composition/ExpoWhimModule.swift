import ExpoModulesCore
import WhimCore

public final class ExpoWhimModule: Module {
    public static let schemaVersion = WhimCoreVersion.schema

    public func definition() -> ModuleDefinition {
        Name("ExpoWhim")

        Function("schemaVersion") { () -> Int in
            Self.schemaVersion
        }
    }
}
