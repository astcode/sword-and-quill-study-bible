// MagQLite Swift Wrapper (iOS 17+ / macOS 14+ / SwiftPM)
// Zero external dependencies — links directly against MagQLite.xcframework (CMagQLite).

import Foundation
import CMagQLite

public struct MagQLiteError: Error, LocalizedError, CustomStringConvertible {
    public let message: String
    public var errorDescription: String? { message }
    public var description: String { message }
    public init(_ message: String) { self.message = message }
}

public struct MagQLiteConfig: Encodable {
    public var durability: String?
    public var pagedStorage: Bool?
    public var bufferPoolPages: Int?
    public var autoCheckpointFrames: Int?
    public var encryptionKey: String?

    enum CodingKeys: String, CodingKey {
        case durability
        case pagedStorage = "paged_storage"
        case bufferPoolPages = "buffer_pool_pages"
        case autoCheckpointFrames = "auto_checkpoint_frames"
        case encryptionKey = "encryption_key"
    }

    public init(
        durability: String? = "normal",
        pagedStorage: Bool? = true,
        bufferPoolPages: Int? = 256,
        autoCheckpointFrames: Int? = 64,
        encryptionKey: String? = nil
    ) {
        self.durability = durability
        self.pagedStorage = pagedStorage
        self.bufferPoolPages = bufferPoolPages
        self.autoCheckpointFrames = autoCheckpointFrames
        self.encryptionKey = encryptionKey
    }
}

/// Strongly-typed SQL bind parameter with lossless Data <-> BLOB support.
public enum MagQLiteParam {
    case null
    case int(Int64)
    case double(Double)
    case string(String)
    case bool(Bool)
    case blob(Data)

    func toJSONValue() -> Any {
        switch self {
        case .null: return NSNull()
        case .int(let v): return v
        case .double(let v): return v
        case .string(let v): return v
        case .bool(let v): return v
        case .blob(let data):
            return ["$blob": Self.hexEncode(data)]
        }
    }

    static func hexEncode(_ data: Data) -> String {
        let hexChars = Array("0123456789abcdef".utf8)
        var out = [UInt8]()
        out.reserveCapacity(data.count * 2)
        for byte in data {
            out.append(hexChars[Int(byte >> 4)])
            out.append(hexChars[Int(byte & 0x0F)])
        }
        return String(decoding: out, as: UTF8.self)
    }

    static func hexDecode(_ str: String) -> Data? {
        let raw = str.hasPrefix("0x") || str.hasPrefix("0X") ? String(str.dropFirst(2)) : str
        guard raw.count % 2 == 0 else { return nil }
        var data = Data(capacity: raw.count / 2)
        var idx = raw.startIndex
        while idx < raw.endIndex {
            let next = raw.index(idx, offsetBy: 2)
            guard let byte = UInt8(raw[idx..<next], radix: 16) else { return nil }
            data.append(byte)
            idx = next
        }
        return data
    }
}

public struct MagQLiteRow {
    public let values: [Any]

    public func int(at index: Int) -> Int64? {
        guard index < values.count else { return nil }
        if let n = values[index] as? Int64 { return n }
        if let n = values[index] as? Int { return Int64(n) }
        if let n = values[index] as? NSNumber { return n.int64Value }
        return nil
    }

    public func double(at index: Int) -> Double? {
        guard index < values.count else { return nil }
        if let n = values[index] as? Double { return n }
        if let n = values[index] as? NSNumber { return n.doubleValue }
        return nil
    }

    public func string(at index: Int) -> String? {
        guard index < values.count else { return nil }
        return values[index] as? String
    }

    public func bool(at index: Int) -> Bool? {
        guard index < values.count else { return nil }
        return values[index] as? Bool
    }

    /// Decodes a BLOB column serialized by MagQLite as `"0x<hex>"` back into raw `Data`.
    public func blob(at index: Int) -> Data? {
        guard index < values.count, let hex = values[index] as? String else { return nil }
        return MagQLiteParam.hexDecode(hex)
    }

    public func isNull(at index: Int) -> Bool {
        guard index < values.count else { return true }
        return values[index] is NSNull
    }
}

public struct MagQLiteResult {
    public let columns: [String]
    public let rows: [MagQLiteRow]
    public let affectedRows: Int
    public let message: String?
}

public final class MagQLite {
    private var handle: OpaquePointer?

    public init(path: String = ":memory:", config: MagQLiteConfig? = nil) throws {
        var cfgString: String? = nil
        if let config = config {
            let data = try JSONEncoder().encode(config)
            cfgString = String(data: data, encoding: .utf8)
        }
        let h: OpaquePointer? = path.withCString { pPtr in
            if let cfg = cfgString {
                return cfg.withCString { cPtr in
                    magqlite_open_with_config(pPtr, cPtr)
                }
            } else {
                return magqlite_open_with_config(pPtr, nil)
            }
        }
        guard let opened = h else {
            throw MagQLiteError("Failed to open MagQLite database at '\(path)'")
        }
        self.handle = opened
    }

    deinit {
        close()
    }

    public func close() {
        if let h = handle {
            magqlite_close(h)
            handle = nil
        }
    }

    public static func compiledModules() -> [String] {
        guard let ptr = magqlite_modules_json() else { return [] }
        defer { magqlite_free_string(ptr) }
        let raw = String(cString: ptr)
        guard let data = raw.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [String] else {
            return []
        }
        return arr
    }

    @discardableResult
    public func query(_ sql: String) throws -> MagQLiteResult {
        guard let h = handle else { throw MagQLiteError("Database is closed") }
        let ptr = sql.withCString { magqlite_exec_json(h, $0) }
        return try takeResult(ptr)
    }

    @discardableResult
    public func queryParams(_ sql: String, params: [MagQLiteParam]) throws -> MagQLiteResult {
        guard let h = handle else { throw MagQLiteError("Database is closed") }
        guard let stmt = sql.withCString({ magqlite_prepare(h, $0) }) else {
            throw MagQLiteError("Failed to prepare SQL: \(sql)")
        }
        defer { magqlite_free_stmt(stmt) }

        let jsonObj = params.map { $0.toJSONValue() }
        let jsonData = try JSONSerialization.data(withJSONObject: jsonObj)
        guard let jsonStr = String(data: jsonData, encoding: .utf8) else {
            throw MagQLiteError("Failed to encode params_json")
        }
        let ptr = jsonStr.withCString { magqlite_exec_params_json(h, stmt, $0) }
        return try takeResult(ptr)
    }

    @discardableResult
    public func queryAsIdentity(_ identity: String?, sql: String) throws -> MagQLiteResult {
        guard let h = handle else { throw MagQLiteError("Database is closed") }
        let idStr = identity ?? ""
        let ptr = idStr.withCString { idPtr in
            sql.withCString { sqlPtr in
                magqlite_exec_as_identity_json(h, idPtr, sqlPtr)
            }
        }
        return try takeResult(ptr)
    }

    @discardableResult
    public func queryAsRole(_ role: String?, sql: String) throws -> MagQLiteResult {
        guard let h = handle else { throw MagQLiteError("Database is closed") }
        let roleStr = role ?? ""
        let ptr = roleStr.withCString { rPtr in
            sql.withCString { sqlPtr in
                magqlite_exec_as_role_json(h, rPtr, sqlPtr)
            }
        }
        return try takeResult(ptr)
    }

    @discardableResult
    public func queryAsContext(identity: String?, role: String?, sql: String) throws -> MagQLiteResult {
        guard let h = handle else { throw MagQLiteError("Database is closed") }
        let idStr = identity ?? ""
        let roleStr = role ?? ""
        let ptr = idStr.withCString { idPtr in
            roleStr.withCString { rPtr in
                sql.withCString { sqlPtr in
                    magqlite_exec_as_context_json(h, idPtr, rPtr, sqlPtr)
                }
            }
        }
        return try takeResult(ptr)
    }

    /// Creates a hot, non-blocking single-file `.mql` backup (even when `paged_storage = true`).
    @discardableResult
    public func backup(to destinationPath: String) throws -> String {
        let escaped = destinationPath.replacingOccurrences(of: "'", with: "''")
        let res = try query("BACKUP TO '\(escaped)';")
        return res.message ?? "Backup complete"
    }

    private func takeResult(_ ptr: UnsafeMutablePointer<CChar>?) throws -> MagQLiteResult {
        guard let ptr = ptr else {
            throw MagQLiteError("Null response from MagQLite FFI")
        }
        defer { magqlite_free_string(ptr) }
        let raw = String(cString: ptr)
        guard let data = raw.data(using: .utf8),
              let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MagQLiteError("Invalid JSON response from MagQLite FFI")
        }
        if let err = dict["error"] as? String {
            throw MagQLiteError(err)
        }
        let cols = dict["columns"] as? [String] ?? []
        let rawRows = dict["rows"] as? [[Any]] ?? []
        let rows = rawRows.map { MagQLiteRow(values: $0) }
        let affected = dict["affected_rows"] as? Int ?? 0
        let msg = dict["message"] as? String
        return MagQLiteResult(columns: cols, rows: rows, affectedRows: affected, message: msg)
    }
}
