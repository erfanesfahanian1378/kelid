/// PLAN.md §6.1.1: tolerant decoding is mandatory for every settings
/// struct. A missing key or an unknown enum value falls back to the
/// default, so an old settings blob keeps working as settings are added in
/// later phases — never a decode failure that could brick a user's saved
/// settings.
extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, default d: @autoclosure () -> T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? d()
    }
}
