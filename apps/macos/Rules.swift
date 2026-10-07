import Foundation
import CoreFoundation

enum Rules {
    static func appearance(_ p:Object) throws {
        try check(Set(p.keys) == ["theme"],"Проверьте настройки оформления")
        try choice(p,"theme",["light","dark"])
    }
    static func settingsBundle(_ p:Object) throws {
        try check(text(p,"format") == "semestr-settings","Это не файл настроек Семестра. Выберите файл, сохранённый в разделе «Перенос настроек».")
        guard let version=p["formatVersion"] as? NSNumber,CFGetTypeID(version) != CFBooleanGetTypeID(),version.doubleValue == 1 else { try fail("Версия файла настроек не поддерживается") }
        let required:Set<String>=["format","formatVersion","profile","appearance"]
        try check(Set(p.keys)==required || Set(p.keys)==required.union(["notifications"]),"В файле настроек есть неизвестные или пропущенные поля")
        try check(try encoded(p).count <= 64_000,"Файл настроек должен быть меньше 64 КБ")
        try profile(object(p,"profile"))
        try appearance(object(p,"appearance"))
        if p["notifications"] != nil {try ReminderPreferences.validate(object(p,"notifications"))}
    }
    static func profile(_ p: Object) throws {
        let keys: Set<String> = ["name","university","direction","group","timezone","semester","weekOne","onboarded"]
        try check(Set(p.keys) == keys,"Проверьте поля профиля")
        for key in ["name","university","direction","group","semester"] { try string(p,key,300) }
        try zone(text(p,"timezone"))
        try check(CalendarRules.validDate(text(p,"weekOne")) && CalendarRules.monday(text(p,"weekOne")) == text(p,"weekOne"),"Первая учебная неделя начинается в понедельник")
        try check(p["onboarded"] is Bool,"Некорректный профиль")
    }
    static func zone(_ value: String) throws {
        try check(value == "UTC" || TimeZone.knownTimeZoneIdentifiers.contains(value),"Укажите часовой пояс: например, Asia/Yekaterinburg")
    }
    static func string(_ p: Object, _ key: String, _ max: Int = 20000, required: Bool = false) throws {
        guard let value = p[key] as? String else { try fail("Поле \(key) должно быть текстом") }
        try check(value.count <= max && (!required || !value.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty),"Проверьте поле \(key) (максимум \(max) символов)")
    }
    static func url(_ value: String) throws {
        if value.isEmpty { return }
        let u = URLComponents(string:value)
        try check(value.count <= 4096 && ["https","http"].contains(u?.scheme ?? "") && !(u?.host ?? "").isEmpty && u?.user == nil && u?.password == nil,"Ссылка должна начинаться с https:// или http:// и не содержать пароль")
    }
    static func links(_ value: Any?) throws {
        guard let links = value as? [Object] else { try fail("Неверный список ссылок") }
        try check(links.count <= 30,"Не более 30 ссылок на запись")
        for l in links { try check(Set(l.keys) == ["title","url"],"Неверные поля ссылки"); try string(l,"title",300,required:true); try string(l,"url",4096,required:true); try url(text(l,"url")) }
    }
    static func choice(_ p: Object,_ key: String,_ values: [String]) throws { try check(values.contains(text(p,key)),"Неизвестное значение \(key)") }
    static func optionalDate(_ p:Object,_ key:String,instant:Bool=false) throws {
        if p[key] is NSNull { return }
        let value = text(p,key)
        try check(instant ? CalendarRules.instant(value) != nil : CalendarRules.validDate(value),"Проверьте дату \(key)")
    }
    static func normalize(_ input: Object) throws -> Object {
        let defaults: Object
        switch text(input,"kind") {
        case "subject": defaults = ["kind":"subject","title":"","semester":"","description":"","teacher":"","contact":"","assessment":"unknown","requirements":"","admission":"","onlineUrl":"","links":[Object](),"status":"studying"]
        case "task": defaults = ["kind":"task","subjectId":"","title":"","description":"","deadline":null,"status":"todo","debtId":null,"lessonId":null,"links":[Object](),"resultUrl":"","notes":""]
        case "debt": defaults = ["kind":"debt","subjectId":"","reason":"difference","deadline":null,"requirements":"","nextStep":"","teacher":"","status":"clarify","closedAt":null,"confirmation":"","notes":""]
        case "lesson": defaults = ["kind":"lesson","subjectId":"","weekday":0,"startTime":"","endTime":"","type":"practice","validFrom":"","validUntil":"","timezone":"","parity":"all","weekOne":"","onlineUrl":"","room":""]
        case "note": defaults = ["kind":"note","subjectId":"","text":""]
        default: try fail("Неизвестный тип записи")
        }
        try check(Set(input.keys).isSubset(of:Set(defaults.keys)),"В записи есть неизвестные поля")
        let p = defaults.merging(input,uniquingKeysWith: {_,new in new})
        if text(p,"kind") != "subject" { try check(UUID(uuidString:text(p,"subjectId")) != nil,"Выберите предмет") }
        switch text(p,"kind") {
        case "subject":
            try string(p,"title",300,required:true); try string(p,"semester",100); try string(p,"teacher",300); try string(p,"contact",500)
            for k in ["description","requirements","admission"] { try string(p,k) }
            try choice(p,"assessment",["unknown","exam","credit","graded_credit"]); try choice(p,"status",["studying","ready","closed"])
            try string(p,"onlineUrl",4096); try url(text(p,"onlineUrl")); try links(p["links"])
        case "task":
            try string(p,"title",300,required:true); try string(p,"description"); try string(p,"notes"); try optionalDate(p,"deadline",instant:true)
            try choice(p,"status",["todo","in_progress","submitted","accepted","revision"])
            for k in ["debtId","lessonId"] { try check(p[k] is NSNull || UUID(uuidString:text(p,k)) != nil,"Проверьте связанную запись") }
            try links(p["links"]); try string(p,"resultUrl",4096); try url(text(p,"resultUrl"))
        case "debt":
            for k in ["requirements","notes","confirmation"] { try string(p,k) }
            try string(p,"nextStep",1000); try string(p,"teacher",300)
            try choice(p,"reason",["difference","overdue","retake"]); try choice(p,"status",["clarify","working","review","ready","closed"])
            try optionalDate(p,"deadline"); try optionalDate(p,"closedAt")
            if text(p,"status") == "closed" { try check(!(p["closedAt"] is NSNull) && !text(p,"confirmation").trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,"Для закрытия укажите дату и подтверждение результата") }
            else { try check(p["closedAt"] is NSNull,"У незакрытого долга не должно быть даты закрытия") }
        case "lesson":
            try check((1...7).contains(number(p,"weekday")),"Выберите день недели")
            try check(CalendarRules.clock(text(p,"startTime")) != nil && CalendarRules.clock(text(p,"endTime")) != nil && CalendarRules.clockSeconds(text(p,"startTime")) != CalendarRules.clockSeconds(text(p,"endTime")),"Проверьте время занятия")
            try check(CalendarRules.validDate(text(p,"validFrom")) && CalendarRules.validDate(text(p,"validUntil")) && text(p,"validUntil") >= text(p,"validFrom") && CalendarRules.dayDistance(text(p,"validFrom"),text(p,"validUntil")) <= 731,"Период расписания — не более двух лет")
            try zone(text(p,"timezone")); try check(CalendarRules.validDate(text(p,"weekOne")) && CalendarRules.monday(text(p,"weekOne")) == text(p,"weekOne"),"Неделя № 1 начинается в понедельник")
            try choice(p,"parity",["all","even","odd"]); try choice(p,"type",["lecture","practice","lab"])
            try string(p,"room",300); try string(p,"onlineUrl",4096); try url(text(p,"onlineUrl"))
        default: try string(p,"text",20000,required:true)
        }
        return p
    }
    static func relations(_ p:Object,_ records:[Object]) throws {
        if text(p,"kind") == "subject" { return }
        let subject = records.first {text($0,"id") == text(p,"subjectId")}
        try check(subject != nil && text(object(subject!,"data"),"kind") == "subject","Связанный предмет не найден")
        if text(p,"kind") == "task" {
            for (key,kind) in [("debtId","debt"),("lessonId","lesson")] {
                if p[key] is NSNull { continue }
                guard let linked = records.first(where:{text($0,"id") == text(p,key)}) else { try fail("Связанная запись не найдена") }
                let data = object(linked,"data")
                try check(text(data,"kind") == kind && text(data,"subjectId") == text(p,"subjectId"),"Связанные записи должны принадлежать одному предмету")
            }
        }
    }
    static func exception(_ p:Object,_ lesson:Object) throws {
        try check(CalendarRules.validDate(text(p,"originalDate")) && CalendarRules.matches(lesson,text(p,"originalDate")),"В этот день занятия в серии нет")
        let s = p["startsAt"] as? String; let e = p["endsAt"] as? String
        if s == nil && e == nil { try check((p["startsAt"] == nil || p["startsAt"] is NSNull) && (p["endsAt"] == nil || p["endsAt"] is NSNull),"Проверьте время переноса"); return }
        guard let start = CalendarRules.instant(s ?? ""), let end = CalendarRules.instant(e ?? "") else { try fail("Проверьте время переноса") }
        try check(end > start && end.timeIntervalSince(start) <= 86400,"Пара должна закончиться после начала, не позднее чем через сутки")
    }
    struct Imported { let profile:Object; let records:[Object]; let exceptions:[Object]; let preview:Object }
    static func bundle(_ p:Object) throws -> Imported {
        try check(number(p,"formatVersion") == 1,"Версия файла не поддерживается")
        try check(Set(p.keys) == ["formatVersion","profile","records","exceptions"],"Неверная структура файла")
        let profile = object(p,"profile"); try self.profile(profile)
        guard let rawRecords = p["records"] as? [Object], let exceptions = p["exceptions"] as? [Object] else { try fail("Проверьте список записей") }
        try check(rawRecords.count <= 10000 && exceptions.count <= 10000,"Не более 10 000 записей и исключений за импорт")
        var seen = Set<String>(); var records = [Object]()
        for r in rawRecords {
            let id = text(r,"id"); try check(UUID(uuidString:id) != nil && seen.insert(id).inserted,"В файле повторяется или неверен идентификатор")
            records.append(["id":id,"version":0,"data":try normalize(object(r,"data"))])
        }
        for r in records { try relations(object(r,"data"),records) }
        var exceptionKeys = Set<String>()
        for e in exceptions {
            guard let lesson = records.first(where:{text($0,"id") == text(e,"lessonId")}), text(object(lesson,"data"),"kind") == "lesson" else { try fail("Исключение связано с отсутствующим занятием") }
            try check(exceptionKeys.insert(text(e,"lessonId")+text(e,"originalDate")).inserted,"Повторяющееся исключение")
            try exception(e,object(lesson,"data"))
        }
        var preview: Object = ["exceptions":exceptions.count]
        for (kind,name) in [("subject","subjects"),("task","tasks"),("debt","debts"),("lesson","lessons"),("note","notes")] { preview[name] = records.filter{text(object($0,"data"),"kind") == kind}.count }
        return Imported(profile:profile,records:records,exceptions:exceptions,preview:preview)
    }
}
