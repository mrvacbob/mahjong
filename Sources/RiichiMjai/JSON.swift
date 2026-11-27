// A small JSON reader and writer, without Foundation (design §2).
//
// The reader scans one object and records where each top-level value is; values
// are parsed only when asked for, and anything not asked for (Mortal's `meta`, with
// nested objects and arrays of floats) is skipped over without being built.

public struct JSONError: Error, Sendable, CustomStringConvertible {
    public let message: String
    public let offset: Int
    public var description: String { "\(message) at byte \(offset)" }
}

/// A parsed JSON value. Numbers keep their text (floats are never needed as numbers).
public enum JSONValue: Hashable, Sendable {
    case null
    case bool(Bool)
    case number(String)
    case string(String)
    case array([JSONValue])
    case object(JSONObject)

    public var int: Int? { if case .number(let n) = self { Int(n) } else { nil } }
    public var string: String? { if case .string(let s) = self { s } else { nil } }
    public var bool: Bool? { if case .bool(let b) = self { b } else { nil } }
    public var array: [JSONValue]? { if case .array(let a) = self { a } else { nil } }
    public var object: JSONObject? { if case .object(let o) = self { o } else { nil } }
}

/// One JSON object: its keys in order, and each value's bytes, parsed on demand.
public struct JSONObject: Hashable, Sendable {
    let bytes: [UInt8]
    public let keys: [String]
    let ranges: [Range<Int>]

    /// Parses `text`, which must be one object (surrounding whitespace allowed).
    public init(parsing text: String) throws(JSONError) {
        var s = Scanner(bytes: Array(text.utf8))
        s.whitespace()
        self = try s.object()
        s.whitespace()
        guard s.i == s.bytes.count else { throw JSONError(message: "trailing characters", offset: s.i) }
    }

    init(bytes: [UInt8], keys: [String], ranges: [Range<Int>]) {
        self.bytes = bytes
        self.keys = keys
        self.ranges = ranges
    }

    /// The value of `key` (the last, if repeated, as other JSON readers do), parsed
    /// now. Parsing cannot fail: `init(parsing:)` has validated every value.
    public subscript(key: String) -> JSONValue? {
        guard let i = keys.lastIndex(of: key) else { return nil }
        var s = Scanner(bytes: bytes, i: ranges[i].lowerBound)
        return try? s.value()
    }

    public func has(_ key: String) -> Bool { keys.contains(key) }

    public static func == (a: JSONObject, b: JSONObject) -> Bool {
        a.keys == b.keys && zip(a.ranges, b.ranges).allSatisfy { a.bytes[$0.0] == b.bytes[$0.1] }
    }
    public func hash(into h: inout Hasher) { h.combine(keys) }
}

struct Scanner {
    let bytes: [UInt8]
    var i = 0
    /// Arrays and objects open around the current position.
    var depth = 0
    /// Deeper nesting is refused (mjai needs three levels; the limit keeps hostile
    /// input from exhausting the stack).
    static let maxDepth = 64

    mutating func enter() throws(JSONError) {
        depth += 1
        if depth > Scanner.maxDepth { throw fail("nesting too deep") }
    }

    func fail(_ m: String) -> JSONError { JSONError(message: m, offset: i) }

    mutating func whitespace() {
        while i < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[i]) { i += 1 }
    }

    mutating func expect(_ c: UInt8) throws(JSONError) {
        whitespace()
        guard i < bytes.count, bytes[i] == c else { throw fail("expected '\(Character(Unicode.Scalar(c)))'") }
        i += 1
    }

    mutating func peek() -> UInt8? {
        whitespace()
        return i < bytes.count ? bytes[i] : nil
    }

    mutating func object() throws(JSONError) -> JSONObject {
        try expect(UInt8(ascii: "{"))
        try enter()
        defer { depth -= 1 }
        var keys: [String] = [], ranges: [Range<Int>] = []
        if peek() == UInt8(ascii: "}") { i += 1; return JSONObject(bytes: bytes, keys: [], ranges: []) }
        while true {
            whitespace()
            keys.append(try string())
            try expect(UInt8(ascii: ":"))
            whitespace()
            let start = i
            try skip()
            ranges.append(start..<i)
            switch peek() {
            case UInt8(ascii: ","): i += 1
            case UInt8(ascii: "}"): i += 1; return JSONObject(bytes: bytes, keys: keys, ranges: ranges)
            default: throw fail("expected ',' or '}'")
            }
        }
    }

    mutating func string() throws(JSONError) -> String {
        guard i < bytes.count, bytes[i] == UInt8(ascii: "\"") else { throw fail("expected a string") }
        i += 1
        var out: [UInt8] = []
        while i < bytes.count {
            let c = bytes[i]
            i += 1
            switch c {
            case UInt8(ascii: "\""):
                return String(decoding: out, as: UTF8.self)
            case UInt8(ascii: "\\"):
                guard i < bytes.count else { throw fail("unterminated escape") }
                let e = bytes[i]
                i += 1
                switch e {
                case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"): out.append(e)
                case UInt8(ascii: "b"): out.append(0x08)
                case UInt8(ascii: "f"): out.append(0x0C)
                case UInt8(ascii: "n"): out.append(0x0A)
                case UInt8(ascii: "r"): out.append(0x0D)
                case UInt8(ascii: "t"): out.append(0x09)
                case UInt8(ascii: "u"):
                    var code = try hex4()
                    if (0xD800..<0xDC00).contains(code), i + 1 < bytes.count,
                       bytes[i] == UInt8(ascii: "\\"), bytes[i + 1] == UInt8(ascii: "u") {
                        // A low surrogate completes the pair; anything else is left
                        // to be read on its own, and the lone high surrogate is U+FFFD.
                        let save = i
                        i += 2
                        let low = try hex4()
                        if (0xDC00...0xDFFF).contains(low) {
                            code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                        } else {
                            i = save
                        }
                    }
                    let scalar = Unicode.Scalar(code) ?? "\u{FFFD}"
                    out += Array(String(Character(scalar)).utf8)
                default: throw fail("bad escape")
                }
            default:
                guard c >= 0x20 else { i -= 1; throw fail("control character in a string") }
                out.append(c)
            }
        }
        throw fail("unterminated string")
    }

    mutating func hex4() throws(JSONError) -> UInt32 {
        guard i + 4 <= bytes.count else { throw fail("short \\u escape") }
        var v: UInt32 = 0
        for _ in 0..<4 {
            let c = bytes[i]
            i += 1
            let d: UInt32
            switch c {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): d = UInt32(c - UInt8(ascii: "0"))
            case UInt8(ascii: "a")...UInt8(ascii: "f"): d = UInt32(c - UInt8(ascii: "a") + 10)
            case UInt8(ascii: "A")...UInt8(ascii: "F"): d = UInt32(c - UInt8(ascii: "A") + 10)
            default: throw fail("bad hex digit")
            }
            v = v * 16 + d
        }
        return v
    }

    mutating func literal(_ word: String) throws(JSONError) {
        for c in word.utf8 {
            guard i < bytes.count, bytes[i] == c else { throw fail("expected \(word)") }
            i += 1
        }
    }

    /// RFC 8259: `-? (0 | [1-9][0-9]*) (. [0-9]+)? ([eE] [+-]? [0-9]+)?`.
    mutating func number() throws(JSONError) -> String {
        let start = i
        func digit() -> Bool { i < bytes.count && (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[i]) }
        func digits() throws(JSONError) {
            guard digit() else { throw fail("bad number") }
            while digit() { i += 1 }
        }
        if i < bytes.count, bytes[i] == UInt8(ascii: "-") { i += 1 }
        if i < bytes.count, bytes[i] == UInt8(ascii: "0") { i += 1 } else { try digits() }
        if i < bytes.count, bytes[i] == UInt8(ascii: ".") { i += 1; try digits() }
        if i < bytes.count, bytes[i] == UInt8(ascii: "e") || bytes[i] == UInt8(ascii: "E") {
            i += 1
            if i < bytes.count, bytes[i] == UInt8(ascii: "+") || bytes[i] == UInt8(ascii: "-") { i += 1 }
            try digits()
        }
        return String(decoding: bytes[start..<i], as: UTF8.self)
    }

    /// Steps over one value without building it.
    mutating func skip() throws(JSONError) {
        whitespace()
        guard i < bytes.count else { throw fail("expected a value") }
        switch bytes[i] {
        case UInt8(ascii: "\""):
            // Validated as `string()` would read it (escapes, control characters).
            _ = try string()
        case UInt8(ascii: "{"), UInt8(ascii: "["):
            let close = bytes[i] == UInt8(ascii: "{") ? UInt8(ascii: "}") : UInt8(ascii: "]")
            let isObject = close == UInt8(ascii: "}")
            i += 1
            try enter()
            defer { depth -= 1 }
            if peek() == close { i += 1; return }
            while true {
                if isObject {
                    whitespace()
                    _ = try string()
                    try expect(UInt8(ascii: ":"))
                }
                try skip()
                switch peek() {
                case UInt8(ascii: ","): i += 1
                case close: i += 1; return
                default: throw fail("expected ',' or a closing bracket")
                }
            }
        case UInt8(ascii: "t"): try literal("true")
        case UInt8(ascii: "f"): try literal("false")
        case UInt8(ascii: "n"): try literal("null")
        default: _ = try number()
        }
    }

    mutating func value() throws(JSONError) -> JSONValue {
        whitespace()
        guard i < bytes.count else { throw fail("expected a value") }
        switch bytes[i] {
        case UInt8(ascii: "\""): return .string(try string())
        case UInt8(ascii: "{"): return .object(try object())
        case UInt8(ascii: "["):
            i += 1
            try enter()
            defer { depth -= 1 }
            var out: [JSONValue] = []
            if peek() == UInt8(ascii: "]") { i += 1; return .array([]) }
            while true {
                out.append(try value())
                switch peek() {
                case UInt8(ascii: ","): i += 1
                case UInt8(ascii: "]"): i += 1; return .array(out)
                default: throw fail("expected ',' or ']'")
                }
            }
        case UInt8(ascii: "t"): try literal("true"); return .bool(true)
        case UInt8(ascii: "f"): try literal("false"); return .bool(false)
        case UInt8(ascii: "n"): try literal("null"); return .null
        default: return .number(try number())
        }
    }
}

// MARK: writing

/// A value to write. Objects keep their keys in the order given.
public indirect enum JSONOut: Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case string(String)
    case array([JSONOut])
    case object([(String, JSONOut)])

    /// Compact JSON text (no spaces).
    public var text: String {
        var out = ""
        write(to: &out)
        return out
    }

    func write(to out: inout String) {
        switch self {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .int(let n): out += String(n)
        case .string(let s): JSONOut.quote(s, into: &out)
        case .array(let a):
            out += "["
            for (n, v) in a.enumerated() {
                if n > 0 { out += "," }
                v.write(to: &out)
            }
            out += "]"
        case .object(let fields):
            out += "{"
            for (n, (k, v)) in fields.enumerated() {
                if n > 0 { out += "," }
                JSONOut.quote(k, into: &out)
                out += ":"
                v.write(to: &out)
            }
            out += "}"
        }
    }

    static func quote(_ s: String, into out: inout String) {
        out += "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if u.value < 0x20 {
                    let h = String(u.value, radix: 16)
                    out += "\\u" + String(repeating: "0", count: 4 - h.count) + h
                } else {
                    out.unicodeScalars.append(u)
                }
            }
        }
        out += "\""
    }
}
