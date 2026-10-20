import UIKit

final class Speller {
    private let checker = UITextChecker()
    private let lang = "en_US"
    private var learned = Set(UserDefaults.standard.stringArray(forKey: "learned") ?? [])

    private static let fixes = [
        "i": "I", "im": "I'm", "ive": "I've", "dont": "don't", "cant": "can't", "wont": "won't",
        "didnt": "didn't", "doesnt": "doesn't", "isnt": "isn't", "wasnt": "wasn't", "werent": "weren't",
        "arent": "aren't", "couldnt": "couldn't", "shouldnt": "shouldn't", "wouldnt": "wouldn't",
        "havent": "haven't", "hasnt": "hasn't", "youre": "you're", "theyre": "they're", "thats": "that's",
        "whats": "what's", "theres": "there's", "youve": "you've", "theyve": "they've",
    ]

    private static let slang: Set<String> = [
        "lol", "lmao", "lmfao", "bruh", "gng", "fr", "ngl", "tbh", "idk", "imo", "imho", "rn", "smh", "ong",
        "pls", "plz", "ty", "tysm", "np", "dm", "dms", "gg", "ggs", "wtf", "omg", "btw", "nvm", "irl", "afk",
        "brb", "ok", "okay", "yo", "sus", "mid", "lowkey", "highkey", "yall", "ya", "yea", "nah", "gonna",
        "wanna", "gotta", "kinda", "lemme", "dunno", "tho", "thx", "kk", "xd", "hbu", "wyd", "wym", "icl",
        "istg", "fyi", "asap", "ig", "bc", "cuz", "ppl", "nsfw", "sfw", "mod", "mods", "vc", "gc", "pfp",
        "ign", "pvp", "ur", "u", "bro", "sis", "fam", "vibe", "vibes", "goat", "cap", "w", "l", "dw", "hmu",
    ]

    func learn(_ word: String) {
        let w = word.lowercased()
        guard !learned.contains(w) else { return }
        learned.insert(w)
        UserDefaults.standard.set(Array(learned), forKey: "learned")
        UITextChecker.learnWord(w)
    }

    func correction(for word: String, sentenceStart: Bool) -> String? {
        let lower = word.lowercased()
        if learned.contains(lower) || Self.slang.contains(lower) { return nil }
        if word.first?.isUppercase == true && !sentenceStart && lower != "i" { return nil }
        if word.dropFirst().contains(where: \.isUppercase) { return nil }
        if let f = Self.fixes[lower] {
            let r = matchCase(f, like: word)
            return r == word ? nil : r
        }
        guard word.count >= 3, misspelled(word), let g = guesses(word).first,
              distance(lower, g.lowercased()) <= (word.count >= 7 ? 2 : 1) else { return nil }
        let r = matchCase(g, like: word)
        return r == word ? nil : r
    }

    func suggestions(for word: String, correction: String?) -> [String] {
        var out = correction.map { [$0] } ?? []
        for w in (misspelled(word) ? guesses(word) : []) + completions(word) {
            let m = matchCase(w, like: word)
            if m.lowercased() != word.lowercased(), !out.contains(m) { out.append(m) }
            if out.count == 2 { break }
        }
        return out
    }

    private func range(_ w: String) -> NSRange { NSRange(location: 0, length: (w as NSString).length) }

    private func misspelled(_ w: String) -> Bool {
        checker.rangeOfMisspelledWord(in: w, range: range(w), startingAt: 0, wrap: false, language: lang).location != NSNotFound
    }

    private func guesses(_ w: String) -> [String] {
        checker.guesses(forWordRange: range(w), in: w, language: lang) ?? []
    }

    private func completions(_ w: String) -> [String] {
        checker.completions(forPartialWordRange: range(w), in: w, language: lang) ?? []
    }

    private func matchCase(_ w: String, like word: String) -> String {
        word.first?.isUppercase == true ? w.prefix(1).uppercased() + w.dropFirst() : w
    }

    private func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty || b.isEmpty { return max(a.count, b.count) }
        var d = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { d[i][0] = i }
        for j in 0...b.count { d[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
                }
            }
        }
        return d[a.count][b.count]
    }
}
