import Foundation

enum Failure: Error, CustomStringConvertible {
    case invalid(String)
    var description: String { switch self { case .invalid(let message): return message } }
}
func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw Failure.invalid(message) }
}
func numeric(_ value: String) throws -> Double {
    guard let parsed = Double(value), parsed.isFinite else { throw Failure.invalid("Finite number required") }
    return parsed
}
func input(_ columns: Int) throws -> [[String]] {
    var rows: [[String]] = []
    while let line = readLine() {
        try require(rows.count < 100000, "Input capacity exceeded")
        let fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        try require(fields.count == columns && fields.allSatisfy { !$0.isEmpty }, "Invalid CSV row")
        rows.append(fields)
    }
    try require(!rows.isEmpty, "Missing input")
    return rows
}
func output<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(value)
    guard let text = String(data: data, encoding: .utf8) else { throw Failure.invalid("Encoding failed") }
    print(text)
}

struct Check { let id: String; let dependencies: [String]; let status: String; let measured: Double; let lower: Double; let upper: Double; let ageHours: Double }
struct Acceptance: Codable { let id: String; let accepted: Bool; let reasons: [String] }
func evaluate(_ checks: [Check]) throws -> [Acceptance] {
    try require(checks.count <= 512, "At most 512 commissioning checks supported")
    var catalog: [String: Check] = [:]
    for c in checks {
        try require(catalog[c.id] == nil && c.lower <= c.upper && c.ageHours >= 0 && ["PASS", "FAIL", "PENDING"].contains(c.status), "Invalid check")
        try require(Set(c.dependencies).count == c.dependencies.count, "Duplicate dependency")
        catalog[c.id] = c
    }
    var visiting = Set<String>(), completed: [String: Acceptance] = [:]
    func visit(_ id: String) throws -> Acceptance {
        if let existing = completed[id] { return existing }
        guard let c = catalog[id] else { throw Failure.invalid("Unknown dependency: " + id) }
        try require(!visiting.contains(id), "Dependency cycle")
        visiting.insert(id)
        var reasons: [String] = []
        for dependency in c.dependencies {
            let result = try visit(dependency)
            if !result.accepted { reasons.append("BLOCKED:" + dependency) }
        }
        if c.status != "PASS" { reasons.append(c.status) }
        if c.measured < c.lower || c.measured > c.upper { reasons.append("OUT_OF_RANGE") }
        if c.ageHours > 24 { reasons.append("STALE_EVIDENCE") }
        visiting.remove(id)
        let result = Acceptance(id: id, accepted: reasons.isEmpty, reasons: reasons)
        completed[id] = result
        return result
    }
    return try checks.map { try visit($0.id) }
}
func test() throws {
    let a = Check(id: "A", dependencies: [], status: "PASS", measured: 5, lower: 0, upper: 10, ageHours: 1)
    let b = Check(id: "B", dependencies: ["A"], status: "PASS", measured: 20, lower: 0, upper: 10, ageHours: 1)
    let c = Check(id: "C", dependencies: ["B"], status: "PASS", measured: 5, lower: 0, upper: 10, ageHours: 1)
    let r = try evaluate([a, b, c]); try require(r[0].accepted && !r[1].accepted && r[2].reasons.contains("BLOCKED:B"), "Acceptance propagation mismatch")
    var rejected = false
    do { _ = try evaluate([Check(id: "A", dependencies: ["A"], status: "PASS", measured: 0, lower: 0, upper: 1, ageHours: 0)]) } catch { rejected = true }
    try require(rejected, "Cycle accepted")
}
func run() throws {
    let checks = try input(7).map { row in Check(id: row[0], dependencies: row[1] == "-" ? [] : row[1].split(separator: "|").map(String.init), status: row[2], measured: try numeric(row[3]), lower: try numeric(row[4]), upper: try numeric(row[5]), ageHours: try numeric(row[6])) }
    for result in try evaluate(checks) { try output(result) }
}

do {
    if Array(CommandLine.arguments.dropFirst()) == ["--self-test"] { try test(); print("Tests passed") }
    else { try run() }
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(2)
}
