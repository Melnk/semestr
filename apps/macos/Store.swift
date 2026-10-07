import Foundation
import SQLite3

typealias Object = [String: Any]
let null = NSNull()
struct LocalError: Error { let status: Int; let code: String; let message: String }
func fail(_ message: String, _ status: Int = 422, _ code: String = "validation") throws -> Never { throw LocalError(status: status, code: code, message: message) }
func check(_ condition: Bool, _ message: String) throws { if !condition { try fail(message) } }
func text(_ obj: Object, _ key: String) -> String { obj[key] as? String ?? "" }
func number(_ obj: Object, _ key: String) -> Int { (obj[key] as? NSNumber)?.intValue ?? -1 }
func object(_ obj: Object, _ key: String) -> Object { obj[key] as? Object ?? [:] }
func objects(_ obj: Object, _ key: String) -> [Object] { obj[key] as? [Object] ?? [] }
func newID() -> String { UUID().uuidString.lowercased() }
func encoded(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed]) }

/// A local transactional store. Every request reads a fresh SQLite snapshot;
/// versions protect concurrent windows/processes. No HTTP server or cloud account.
final class LocalStore {
    private var db: OpaquePointer?
    let fileURL: URL
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        fileURL = directory.appendingPathComponent("semestr.sqlite3")
        guard sqlite3_open_v2(fileURL.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else { sqlite3_close(db); db=nil; throw LocalError(status:500,code:"storage",message:"Не удалось открыть локальную базу.") }
        sqlite3_busy_timeout(db, 5000)
        try sql("PRAGMA journal_mode=WAL")
        try sql("PRAGMA synchronous=FULL")
        try sql("CREATE TABLE IF NOT EXISTS workspace (id INTEGER PRIMARY KEY CHECK(id=1), payload TEXT NOT NULL)")
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        try transaction {
            if try loadOptional() == nil {
                let zone = TimeZone.current.identifier
                let today = CalendarRules.dateString(Date(), zone)
                let monday = CalendarRules.monday(today)
                let profile: Object = ["name":"", "university":"", "direction":"", "group":"", "timezone":zone, "semester":"", "weekOne":monday, "onboarded":false]
                let account: Object = ["id":newID(), "email":"", "profile":profile, "version":0, "revision":0]
                try persist(["formatVersion":1, "account":account, "records":[Object](), "exceptions":[Object]()])
            }
        }
    }
    deinit { sqlite3_close(db) }
    private func sql(_ statement: String) throws {
        if sqlite3_exec(db, statement, nil, nil, nil) != SQLITE_OK { try fail("Не удалось записать данные. Закройте другие окна приложения и повторите.", 503, "storage") }
    }
    private func transaction<T>(_ work: () throws -> T) throws -> T {
        try sql("BEGIN IMMEDIATE")
        do { let result = try work(); try sql("COMMIT"); return result }
        catch { try? sql("ROLLBACK"); throw error }
    }
    private func loadOptional() throws -> Object? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT payload FROM workspace WHERE id=1", -1, &stmt, nil) == SQLITE_OK else { try fail("Ошибка чтения базы.",500,"storage") }
        defer { sqlite3_finalize(stmt) }
        let result = sqlite3_step(stmt)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW, let raw = sqlite3_column_text(stmt, 0) else { try fail("Не удалось прочитать данные.",500,"storage") }
        let data = Data(String(cString: raw).utf8)
        guard let state = try JSONSerialization.jsonObject(with:data) as? Object, number(state,"formatVersion") == 1 else { try fail("Формат базы не поддерживается. Существующие данные не изменены.",500,"storage") }
        return state
    }
    private func persist(_ state: Object) throws {
        let json = String(decoding:try encoded(state),as:UTF8.self)
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT INTO workspace(id,payload) VALUES(1,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload", -1, &stmt, nil) == SQLITE_OK else { try fail("Ошибка записи базы.",500,"storage") }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt,1,json,-1,transient)
        guard sqlite3_step(stmt) == SQLITE_DONE else { try fail("Изменения не сохранены. Проверьте свободное место на диске.",503,"storage") }
    }
    func request(path: String, method: String = "GET", body: Object = [:]) throws -> Any {
        try check(path.hasPrefix("/"),"Некорректный запрос")
        try check(try encoded(body).count <= 5_000_000,"Файл слишком большой: максимум 5 МБ")
        let components = URLComponents(string: "semestr://app" + path)!
        let route = components.path
        let query = Dictionary((components.queryItems ?? []).map { ($0.name,$0.value ?? "") }, uniquingKeysWith: { _,new in new })
        return try transaction {
            guard var state = try loadOptional() else { try fail("База не найдена.",500,"storage") }
            var account = object(state,"account")
            var records = objects(state,"records")
            var exceptions = objects(state,"exceptions")
            var dirty = false
            var output: Any = null
            switch (method, route) {
            case ("GET", "/auth/session"):
                return ["account":account,"csrf":"local"]
            case ("GET", "/appearance"):
                return state["appearance"] ?? ["theme":"light"]
            case ("POST", "/appearance/initialize"), ("PUT", "/appearance"):
                try Rules.appearance(body)
                // On the first launch after upgrading, keep the previous WebKit theme.
                if method == "POST", let existing = state["appearance"] { return existing }
                if text(object(state,"appearance"),"theme") == text(body,"theme") { return body }
                state["appearance"] = body; dirty = true; output = body
            case ("GET", "/settings/export"):
                return ["format":"semestr-settings","formatVersion":1,"profile":account["profile"]!,"appearance":state["appearance"] ?? ["theme":"light"]]
            case ("POST", "/settings/preview"):
                try Rules.settingsBundle(body)
                return ["bundle":body,"expectedRevision":number(account,"revision")]
            case ("POST", "/settings/import"):
                try Rules.settingsBundle(object(body,"bundle"))
                guard number(body,"expectedRevision") == number(account,"revision") else { try fail("Настройки или данные изменились после предпросмотра. Загрузите файл ещё раз.",409,"conflict") }
                let imported = object(body,"bundle")
                account["profile"] = imported["profile"]!
                account["version"] = number(account,"version")+1
                state["appearance"] = imported["appearance"]!
                dirty = true
            case ("PUT", "/profile"):
                try version(body, account)
                let profile = object(body,"profile"); try Rules.profile(profile)
                account["profile"] = profile; account["version"] = number(account,"version")+1; dirty = true
                output = account
            case ("GET", "/records"):
                let limit = min(200,max(1,Int(query["limit"] ?? "100") ?? 100))
                let filtered = records.filter { (query["kind"] == nil || text(object($0,"data"),"kind") == query["kind"]) && (query["cursor"] == nil || text($0,"id") > query["cursor"]!) }.sorted { text($0,"id") < text($1,"id") }
                let page = Array(filtered.prefix(limit))
                return ["items":page, "nextCursor":filtered.count > limit ? page.last!["id"]! : null]
            case ("POST", "/records"):
                try check(records.count < 10000,"В локальной базе уже 10 000 записей. Экспортируйте архив перед добавлением.")
                let data = try Rules.normalize(object(body,"data"))
                try Rules.relations(data,records)
                let record: Object = ["id":newID(),"version":0,"data":data]
                records.append(record); dirty = true; output = record
            case ("POST", "/debts/with-subject"):
                try check(records.count <= 9998,"Недостаточно места для нового предмета и долга: максимум 10 000 записей")
                try check(Set(body.keys) == ["subjectTitle","data"],"Проверьте поля нового долга")
                try check(text(object(body,"data"),"kind") == "debt","Здесь можно создать только академический долг")
                let title=text(body,"subjectTitle").trimmingCharacters(in:.whitespacesAndNewlines)
                let subjectData=try Rules.normalize(["kind":"subject","title":title,"teacher":text(object(body,"data"),"teacher")])
                let subject:Object=["id":newID(),"version":0,"data":subjectData]
                var debtInput=object(body,"data");debtInput["subjectId"]=subject["id"]!
                let debtData=try Rules.normalize(debtInput)
                try Rules.relations(debtData,records+[subject])
                let debt:Object=["id":newID(),"version":0,"data":debtData]
                // One SQLite commit: a validation error cannot leave an empty subject behind.
                records.append(contentsOf:[subject,debt]);dirty=true
                output=["subject":subject,"debt":debt]
            case ("GET", "/schedule/exceptions"):
                return exceptions
            case ("GET", "/schedule"):
                guard let from = CalendarRules.instant(query["from"] ?? ""), let until = CalendarRules.instant(query["until"] ?? "") else { try fail("Проверьте диапазон расписания") }
                try check(until > from && until.timeIntervalSince(from) <= 63*86400,"Диапазон расписания — не больше 62 дней")
                return try CalendarRules.occurrences(records,exceptions,from,until)
            case ("GET", "/export"):
                return ["formatVersion":1,"profile":account["profile"]!,"records":records,"exceptions":exceptions]
            case ("POST", "/import/preview"):
                return try Rules.bundle(body).preview
            case ("POST", "/import"):
                guard number(body,"expectedRevision") == number(account,"revision") else { try fail("Данные изменились после предпросмотра. Проверьте файл ещё раз.",409,"conflict") }
                let mode = text(body,"mode")
                try check(["add","replace"].contains(mode),"Выберите способ импорта")
                try check(mode != "replace" || body["confirmed"] as? Bool == true,"Подтвердите замену данных")
                let imported = try Rules.bundle(object(body,"bundle"))
                try check((mode == "replace" ? 0 : records.count) + imported.records.count <= 10000,"После импорта будет больше 10 000 записей")
                if mode == "replace" { records = []; exceptions = []; account["profile"] = imported.profile; account["version"] = number(account,"version")+1 }
                let ids = Dictionary(uniqueKeysWithValues: imported.records.map { (text($0,"id"),newID()) })
                for record in imported.records {
                    var data = object(record,"data")
                    for key in ["subjectId","debtId","lessonId"] { if let old = data[key] as? String { data[key] = ids[old]! } }
                    records.append(["id":ids[text(record,"id")]!,"version":0,"data":data])
                }
                for item in imported.exceptions {
                    var e = item; e["id"] = newID(); e["version"] = 0; e["lessonId"] = ids[text(e,"lessonId")]!
                    exceptions.append(e)
                }
                dirty = true; output = imported.preview
            default:
                if route.hasPrefix("/records/") {
                    let id = String(route.dropFirst("/records/".count))
                    guard let index = records.firstIndex(where: {text($0,"id") == id}) else { try fail("Запись не найдена",404,"not_found") }
                    let old = records[index]
                    if method == "GET" { return old }
                    if method == "PUT" {
                        try version(body, old)
                        let data = try Rules.normalize(object(body,"data")); let oldData = object(old,"data")
                        try check(text(data,"kind") == text(oldData,"kind"),"Нельзя менять тип записи")
                        try check(text(data,"subjectId") == text(oldData,"subjectId"),"Нельзя переместить запись в другой предмет")
                        try Rules.relations(data,records)
                        if text(data,"kind") == "lesson" {
                            for e in exceptions where text(e,"lessonId") == id { try check(CalendarRules.matches(data,text(e,"originalDate")),"Сначала восстановите исключения, не входящие в новое расписание") }
                        }
                        let updated: Object = ["id":id,"version":number(old,"version")+1,"data":data]
                        records[index] = updated; dirty = true; output = updated
                    } else if method == "DELETE" {
                        try version(["version":Int(query["version"] ?? "") ?? -1],old)
                        for other in records {
                            let d = object(other,"data")
                            if ["subjectId","debtId","lessonId"].contains(where:{text(d,$0) == id}) { try fail("Сначала удалите связанные задания, долги, занятия или заметки.",409,"conflict") }
                        }
                        records.remove(at:index); exceptions.removeAll {text($0,"lessonId") == id}; dirty = true
                    } else { try fail("Операция не поддерживается",405,"method") }
                } else if route.hasPrefix("/schedule/exceptions/") && method == "DELETE" {
                    let id = String(route.dropFirst("/schedule/exceptions/".count))
                    guard let index = exceptions.firstIndex(where:{text($0,"id") == id}) else { try fail("Исключение не найдено",404,"not_found") }
                    try version(["version":Int(query["version"] ?? "") ?? -1],exceptions[index]); exceptions.remove(at:index); dirty = true
                } else if route.hasPrefix("/schedule/") && route.hasSuffix("/exception") && method == "PUT" {
                    let id = route.split(separator:"/")[1].description
                    guard let record = records.first(where:{text($0,"id") == id}), text(object(record,"data"),"kind") == "lesson" else { try fail("Занятие не найдено",404,"not_found") }
                    try Rules.exception(body,object(record,"data"))
                    if let index = exceptions.firstIndex(where:{text($0,"lessonId") == id && text($0,"originalDate") == text(body,"originalDate")}) {
                        try version(body,exceptions[index])
                        let e: Object = ["id":exceptions[index]["id"]!,"lessonId":id,"originalDate":body["originalDate"]!,"startsAt":body["startsAt"] ?? null,"endsAt":body["endsAt"] ?? null,"version":number(exceptions[index],"version")+1]
                        exceptions[index] = e; output = e
                    } else {
                        try check(body["version"] == nil || body["version"] is NSNull,"Исключение больше не существует")
                        let e: Object = ["id":newID(),"lessonId":id,"originalDate":body["originalDate"]!,"startsAt":body["startsAt"] ?? null,"endsAt":body["endsAt"] ?? null,"version":0]
                        exceptions.append(e); output = e
                    }
                    dirty = true
                } else { try fail("Эта операция недоступна в локальном приложении",404,"not_found") }
            }
            if dirty {
                account["revision"] = number(account,"revision")+1
                state["account"] = account; state["records"] = records; state["exceptions"] = exceptions
                try persist(state)
                if route == "/profile" { output = account }
                if route == "/settings/import" { output = ["account":account,"appearance":state["appearance"]!] }
            }
            return output
        }
    }
    private func version(_ request: Object, _ old: Object) throws {
        if number(request,"version") != number(old,"version") { try fail("Запись изменилась в другом окне. Черновик сохранён; загрузите актуальную версию.",409,"conflict") }
    }
}
