import Foundation

enum PageImportError: LocalizedError {
    case invalidURL
    case notFound
    case loginRequired
    case badStatus(Int)
    case notHTML
    case tooLarge
    case unreadable
    case nothingFound

    var errorDescription: String? {
        switch self {
        case .invalidURL: "That doesn't look like a web link. Check it starts with http:// or https://."
        case .notFound: "That page wasn't found. Check the link."
        case .loginRequired: "That page needs a login or blocks automated reading. Paste the text instead."
        case .badStatus(let code): "The site couldn't be read (HTTP \(code)). Try again, or paste the text instead."
        case .notHTML: "That link isn't a web page Ambit can read."
        case .tooLarge: "That page is too large to read."
        case .unreadable: "Ambit couldn't read that page's text."
        case .nothingFound: "Ambit couldn't find an itinerary on that page. It may need a login or load its content with JavaScript. Paste the text instead."
        }
    }
}

enum ItineraryPageImporter {
    private static let maxBytes = 2_000_000
    private static let maxTextChars = 60_000

    /// Fetches a page and turns it into a draft: structured data when the page has it,
    /// otherwise its readable text through the same extractor used for pasted text.
    static func load(_ urlString: String) async throws -> ItineraryDraft {
        let url = try validatedURL(urlString)
        let html = try await fetch(url)

        if var draft = structuredDraft(fromHTML: html), draft.stopCount > 0 {
            draft.sourceHost = url.host()
            return draft
        }

        let text = readableText(fromHTML: html)
        // A real itinerary page has substantial text; the model will invent stops from a stub.
        guard text.count >= 600 else { throw PageImportError.nothingFound }

        var draft = await ItineraryExtractor.extract(from: text)
        guard draft.stopCount >= 2 else { throw PageImportError.nothingFound }
        draft.sourceHost = url.host()
        return draft
    }

    static func validatedURL(_ string: String) throws -> URL {
        var trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.contains("://") { trimmed = "https://" + trimmed }
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, host.contains(".") else { throw PageImportError.invalidURL }
        components.scheme = "https"
        guard let url = components.url else { throw PageImportError.invalidURL }
        return url
    }

    // MARK: Fetching

    private static func fetch(_ url: URL) async throws -> String {
        // Ephemeral session: no cookies or stored credentials are sent with the request.
        let session = URLSession(configuration: .ephemeral)
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw PageImportError.unreadable }
        switch http.statusCode {
        case 200..<300: break
        case 404, 410: throw PageImportError.notFound
        case 401, 403, 429: throw PageImportError.loginRequired
        default: throw PageImportError.badStatus(http.statusCode)
        }
        let type = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        guard type.isEmpty || type.contains("html") || type.contains("xml") else { throw PageImportError.notHTML }

        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > maxBytes { throw PageImportError.tooLarge }
        }

        let encoding = http.textEncodingName
            .map { CFStringConvertEncodingToNSStringEncoding(CFStringConvertIANACharSetNameToEncoding($0 as CFString)) }
            .map { String.Encoding(rawValue: $0) }
        guard let html = String(data: data, encoding: encoding ?? .utf8)
                ?? String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else { throw PageImportError.unreadable }
        return html
    }

    // MARK: Structured data (schema.org JSON-LD)

    static func structuredDraft(fromHTML html: String) -> ItineraryDraft? {
        let blocks = matches(in: html, pattern: #"<script[^>]*type=["']application/ld\+json["'][^>]*>(.*?)</script>"#)
        for block in blocks {
            guard let data = block.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            for trip in tripNodes(in: json) {
                if let draft = draft(fromTrip: trip), draft.stopCount > 0 { return draft }
            }
        }
        return nil
    }

    private static func tripNodes(in node: Any) -> [[String: Any]] {
        if let array = node as? [Any] { return array.flatMap(tripNodes) }
        guard let dict = node as? [String: Any] else { return [] }
        var result: [[String: Any]] = []
        if types(of: dict).contains(where: { $0.hasSuffix("Trip") }) { result.append(dict) }
        for key in ["@graph", "mainEntity", "about"] {
            if let child = dict[key] { result += tripNodes(in: child) }
        }
        return result
    }

    private static func types(of dict: [String: Any]) -> [String] {
        if let single = dict["@type"] as? String { return [single] }
        return (dict["@type"] as? [String]) ?? []
    }

    private static func draft(fromTrip trip: [String: Any]) -> ItineraryDraft? {
        var draft = ItineraryDraft()
        draft.name = (trip["name"] as? String)?.trimmed ?? ""
        draft.destination = placeName(trip["destination"] ?? trip["location"] ?? trip["areaServed"]) ?? ""

        let elements = listElements(trip["itinerary"])
        // Elements that carry their own list are days; otherwise they're all stops of one day.
        let nested = elements.filter { !listElements($0["itinerary"] ?? $0["itemListElement"]).isEmpty }
        if !nested.isEmpty {
            draft.days = nested.enumerated().map { index, day in
                let stops = listElements(day["itinerary"] ?? day["itemListElement"]).compactMap(stop(from:))
                return DraftDay(title: (day["name"] as? String)?.trimmed ?? "Day \(index + 1)", stops: stops)
            }
        } else {
            draft.days = [DraftDay(title: "Day 1", stops: elements.compactMap(stop(from:)))]
        }
        return draft
    }

    private static func listElements(_ node: Any?) -> [[String: Any]] {
        guard let node else { return [] }
        if let array = node as? [Any] {
            return array.compactMap { ($0 as? [String: Any]) }
        }
        if let dict = node as? [String: Any] {
            if let list = dict["itemListElement"] { return listElements(list) }
            return [dict]
        }
        return []
    }

    private static func stop(from element: [String: Any]) -> DraftStop? {
        let item = (element["item"] as? [String: Any]) ?? element
        guard let name = (item["name"] as? String ?? element["name"] as? String)?.trimmed, !name.isEmpty else { return nil }
        var stop = DraftStop(name: name)
        let foodTypes: Set<String> = ["Restaurant", "CafeOrCoffeeShop", "BarOrPub", "Bakery", "FoodEstablishment", "FastFoodRestaurant", "IceCreamShop"]
        stop.category = types(of: item).contains(where: foodTypes.contains) ? .food : ItineraryTextParser.guessCategory(name)
        stop.notes = ((item["description"] as? String) ?? "").trimmed.prefix(160).description
        if let geo = item["geo"] as? [String: Any],
           let lat = number(geo["latitude"]), let lon = number(geo["longitude"]) {
            stop.latitude = lat
            stop.longitude = lon
            stop.locateState = .found
        }
        return stop
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? Double) ?? (value as? String).flatMap(Double.init)
    }

    private static func placeName(_ value: Any?) -> String? {
        if let string = value as? String { return string.trimmed }
        if let dict = value as? [String: Any] { return (dict["name"] as? String)?.trimmed }
        if let array = value as? [Any] { return array.compactMap(placeName).first }
        return nil
    }

    // MARK: Readable text

    static func readableText(fromHTML html: String) -> String {
        var page = html
        page = replace(page, pattern: #"<!--.*?-->"#, with: "")
        for tag in ["script", "style", "noscript", "svg", "nav", "footer", "aside", "form", "iframe", "template"] {
            page = replace(page, pattern: "<\(tag)\\b[^>]*>.*?</\(tag)>", with: "")
        }

        let title = matches(in: page, pattern: #"<title[^>]*>(.*?)</title>"#).first.map(decode)?.trimmed ?? ""

        // Prefer the article body when the page has one; the rest is mostly chrome.
        for tag in ["article", "main"] {
            if let body = matches(in: page, pattern: "<\(tag)\\b[^>]*>(.*)</\(tag)>").first,
               stripTags(body).count > 400 {
                page = body
                break
            }
        }

        page = replace(page, pattern: #"<h[1-6]\b[^>]*>"#, with: "\n\n")
        page = replace(page, pattern: #"</h[1-6]>"#, with: "\n")
        page = replace(page, pattern: #"<li\b[^>]*>"#, with: "\n- ")
        page = replace(page, pattern: #"<br\s*/?>|</p>|</div>|</tr>|</section>"#, with: "\n")

        var lines = decode(stripTags(page))
            .split(whereSeparator: \.isNewline)
            .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .filter { !$0.isEmpty }
        if !title.isEmpty { lines.insert(title, at: 0) }
        return String(lines.joined(separator: "\n").prefix(maxTextChars))
    }

    private static func stripTags(_ html: String) -> String {
        replace(html, pattern: #"<[^>]+>"#, with: "")
    }

    private static func decode(_ text: String) -> String {
        var result = text
        let named = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&apos;": "'",
                     "&#39;": "'", "&ndash;": "–", "&mdash;": "—", "&rsquo;": "'", "&lsquo;": "'",
                     "&ldquo;": "\"", "&rdquo;": "\"", "&hellip;": "…"]
        for (entity, value) in named { result = result.replacingOccurrences(of: entity, with: value) }
        guard let numeric = try? NSRegularExpression(pattern: #"&#(x?[0-9a-fA-F]+);"#) else { return result }
        let ns = result as NSString
        var output = ""
        var last = 0
        for match in numeric.matches(in: result, range: NSRange(location: 0, length: ns.length)) {
            output += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            let code = ns.substring(with: match.range(at: 1))
            let scalar = code.hasPrefix("x") || code.hasPrefix("X")
                ? UInt32(code.dropFirst(), radix: 16)
                : UInt32(code)
            output += scalar.flatMap(Unicode.Scalar.init).map(String.init) ?? ns.substring(with: match.range)
            last = match.range.location + match.range.length
        }
        return output + ns.substring(from: last)
    }

    // MARK: Regex helpers (NSRegularExpression is far faster than Regex on large pages)

    private static func replace(_ text: String, pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive])
        else { return text }
        return regex.stringByReplacingMatches(
            in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: template
        )
    }

    private static func matches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive])
        else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap {
            $0.numberOfRanges > 1 ? ns.substring(with: $0.range(at: 1)) : nil
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
