import Foundation
import CoreFoundation

enum ReminderPreferences {
    static let defaults:Object = ["enabled":false,"lessonsEnabled":true,"lessonTypes":["practice"],"lessonMinutes":5,"deadlinesEnabled":true,"deadlineMinutes":[60,1440],"debtTime":"18:00","sound":true]
    static func validate(_ p:Object) throws {
        try check(Set(p.keys)==Set(defaults.keys),"Проверьте поля настроек уведомлений")
        for key in ["enabled","lessonsEnabled","deadlinesEnabled","sound"] {
            guard let value=p[key] as? NSNumber,CFGetTypeID(value)==CFBooleanGetTypeID() else {try fail("Проверьте переключатель уведомлений")}
        }
        guard let minutes=p["lessonMinutes"] as? NSNumber,CFGetTypeID(minutes) != CFBooleanGetTypeID(),minutes.doubleValue==Double(minutes.intValue),(1...120).contains(minutes.intValue) else {try fail("Напоминание о паре — за 1–120 минут")}
        guard let types=p["lessonTypes"] as? [String],Set(types).isSubset(of:["lecture","practice","lab"]),Set(types).count==types.count else {try fail("Выберите типы занятий")}
        try check(p["lessonsEnabled"] as? Bool != true || !types.isEmpty,"Выберите хотя бы один тип занятия")
        guard let offsets=p["deadlineMinutes"] as? [NSNumber],offsets.allSatisfy({CFGetTypeID($0) != CFBooleanGetTypeID() && $0.doubleValue==Double($0.intValue) && [15,60,180,1440,2880].contains($0.intValue)}),Set(offsets.map(\.intValue)).count==offsets.count else {try fail("Проверьте время напоминаний о дедлайнах")}
        try check(p["deadlinesEnabled"] as? Bool != true || !offsets.isEmpty,"Выберите хотя бы одно напоминание о дедлайне")
        try check(text(p,"debtTime").count==5 && CalendarRules.clock(text(p,"debtTime")) != nil,"Проверьте время срока для долгов")
    }
}

struct Reminder:Equatable {
    let id:String
    let fireAt:Date
    let title:String
    let body:String
    let subjectID:String
    let recordID:String
    let sound:Bool
    var signature:String { [CalendarRules.iso(fireAt),title,body,subjectID,recordID,String(sound)].joined(separator:"\n") }
}

struct ReminderPlan {
    let reminders:[Reminder]
    let coveredUntil:Date
    let truncated:Bool
}

enum ReminderPlanner {
    static let prefix="semestr.reminder."
    static func plan(_ snapshot:Object,now:Date=Date(),limit:Int=60) throws -> ReminderPlan {
        let preferences=object(snapshot,"notifications")
        let horizon=now.addingTimeInterval(30*86400)
        guard preferences["enabled"] as? Bool==true else {return ReminderPlan(reminders:[],coveredUntil:horizon,truncated:false)}
        let records=objects(snapshot,"records")
        let subjects=Dictionary(uniqueKeysWithValues:records.filter{text(object($0,"data"),"kind")=="subject"}.map{(text($0,"id"),object($0,"data"))})
        let zone=text(object(snapshot,"profile"),"timezone")
        let sound=preferences["sound"] as? Bool==true
        var reminders=[Reminder]()
        func add(_ id:String,_ date:Date,_ title:String,_ body:String,_ subjectID:String,_ recordID:String) {
            guard date>now,date<horizon else{return}
            reminders.append(Reminder(id:prefix+id,fireAt:date,title:title,body:body,subjectID:subjectID,recordID:recordID,sound:sound))
        }
        func dateLabel(_ date:Date)->String {
            let f=DateFormatter();f.locale=Locale(identifier:"ru_RU");f.timeZone=TimeZone(identifier:zone);f.dateFormat="d MMM, HH:mm";return f.string(from:date)
        }
        if preferences["lessonsEnabled"] as? Bool==true {
            let types=Set(preferences["lessonTypes"] as? [String] ?? [])
            let lead=number(preferences,"lessonMinutes")
            let active=records.filter { r in
                let d=object(r,"data")
                if text(d,"kind")=="subject" {return text(d,"status") != "closed"}
                return text(d,"kind")=="lesson" && types.contains(text(d,"type"))
            }
            let events=try CalendarRules.occurrences(active,objects(snapshot,"exceptions"),now,horizon.addingTimeInterval(Double(lead)*60),checkConflicts:false)
            for event in events {
                guard let start=CalendarRules.instant(text(event,"startsAt")) else{continue}
                let type=["practice":"Практика","lecture":"Лекция","lab":"Лабораторная"][text(event,"type")] ?? "Занятие"
                let room=text(event,"room")
                let body="\(text(event,"title")) · \(dateLabel(start))"+(room.isEmpty ? "":" · "+room)
                add("lesson.\(text(event,"lessonId")).\(text(event,"originalDate")).\(lead)",start.addingTimeInterval(-Double(lead)*60),"\(type) через \(lead) мин",body,text(event,"subjectId"),text(event,"lessonId"))
            }
        }
        if preferences["deadlinesEnabled"] as? Bool==true {
            let offsets=(preferences["deadlineMinutes"] as? [NSNumber] ?? []).map(\.intValue)
            for record in records {
                let data=object(record,"data"),kind=text(data,"kind"),sid=text(data,"subjectId")
                guard let subject=subjects[sid],text(subject,"status") != "closed" else{continue}
                let deadline:Date?
                let name:String
                if kind=="task",["todo","in_progress","revision"].contains(text(data,"status")) {
                    deadline=CalendarRules.instant(text(data,"deadline"));name=text(data,"title")
                } else if kind=="debt",text(data,"status") != "closed",CalendarRules.validDate(text(data,"deadline")) {
                    deadline=try CalendarRules.localTime(text(data,"deadline"),text(preferences,"debtTime"),zone);name="Академический долг"
                } else {continue}
                guard let date=deadline,date>now else{continue}
                for lead in offsets {
                    let when=[15:"через 15 минут",60:"через час",180:"через 3 часа",1440:"через сутки",2880:"через 2 суток"][lead]!
                    add("\(kind).\(text(record,"id")).\(lead)",date.addingTimeInterval(-Double(lead)*60),"Дедлайн \(when)","\(name) · \(text(subject,"title"))\nСрок: \(dateLabel(date))",sid,text(record,"id"))
                }
            }
        }
        reminders.sort {$0.fireAt==$1.fireAt ? $0.id<$1.id : $0.fireAt<$1.fireAt}
        let selected=Array(reminders.prefix(max(0,limit)))
        let truncated=reminders.count>limit
        return ReminderPlan(reminders:selected,coveredUntil:truncated ? (selected.last?.fireAt ?? now):horizon,truncated:truncated)
    }
}
