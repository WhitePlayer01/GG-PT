import Foundation

/* 测试与截图共用内存偏好，不读写用户配置。 */
final class OrganizationTestDefaults: UserDefaults {
    var values: [String: Any] = [:]
    override func object(forKey key: String) -> Any? { values[key] }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
    override func data(forKey key: String) -> Data? { values[key] as? Data }
    override func string(forKey key: String) -> String? { values[key] as? String }
    override func dictionary(forKey key: String) -> [String: Any]? { values[key] as? [String: Any] }
    override func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
    override func double(forKey key: String) -> Double { values[key] as? Double ?? 0 }
    override func integer(forKey key: String) -> Int { values[key] as? Int ?? 0 }
}
