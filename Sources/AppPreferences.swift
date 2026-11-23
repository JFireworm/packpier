import Foundation

enum PPText {
    static let languages = [(code:"zh-Hans",name:"简体中文"), (code:"en",name:"English"),
                            (code:"ja",name:"日本語"), (code:"ko",name:"한국어")]
    static let languageKey = "packpier.language"
    static func resolved(_ preference:String, preferred:[String] = Locale.preferredLanguages) -> String {
        let supported = languages.map(\.code)
        if supported.contains(preference) { return preference }
        return Bundle.preferredLocalizations(from:supported,forPreferences:preferred).first ?? "zh-Hans"
    }
    static func get(_ key:String, language:String? = nil) -> String {
        let code = resolved(language ?? UserDefaults.standard.string(forKey:languageKey) ?? "system")
        guard let url = Bundle.main.url(forResource:code,withExtension:"lproj"),
              let bundle = Bundle(url:url) else { return key }
        return bundle.localizedString(forKey:key,value:key,table:nil)
    }
    static func format(_ key:String, _ args:CVarArg...) -> String {
        String(format:get(key),locale:nil,arguments:args)
    }
}

