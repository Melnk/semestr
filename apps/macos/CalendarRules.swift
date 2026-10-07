import Foundation

enum CalendarRules {
    static let utc = TimeZone(secondsFromGMT:0)!
    static func calendar(_ zone:String = "UTC") -> Calendar { var c = Calendar(identifier:.gregorian); c.timeZone = TimeZone(identifier:zone) ?? utc; return c }
    static func formatter(_ zone:String = "UTC") -> DateFormatter { let f=DateFormatter();f.locale=Locale(identifier:"en_US_POSIX");f.calendar=calendar(zone);f.timeZone=f.calendar.timeZone;f.dateFormat="yyyy-MM-dd";f.isLenient=false;return f }
    static func dateString(_ date:Date,_ zone:String="UTC") -> String {formatter(zone).string(from:date)}
    static func date(_ value:String) -> Date? {guard value.count == 10, let d=formatter().date(from:value),dateString(d)==value else{return nil};return d}
    static func validDate(_ value:String) -> Bool {date(value) != nil}
    static func shift(_ value:String,_ days:Int) -> String {guard let d=date(value) else{return ""};return dateString(d.addingTimeInterval(Double(days)*86400))}
    static func dayDistance(_ from:String,_ until:String) -> Int {guard let f=date(from),let u=date(until) else{return Int.max};return Int(round(u.timeIntervalSince(f)/86400))}
    static func monday(_ value:String) -> String {guard let d=date(value)else{return ""};let day=calendar().component(.weekday,from:d);return shift(value,-((day+5)%7))}
    static func instant(_ value:String) -> Date? {
        let f=ISO8601DateFormatter();f.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
        if let d=f.date(from:value){return d};f.formatOptions=[.withInternetDateTime];return f.date(from:value)
    }
    static func iso(_ date:Date) -> String {ISO8601DateFormatter().string(from:date)}
    static func clock(_ value:String) -> (Int,Int,Int)? {
        guard value.range(of:"^([01][0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9](\\.[0-9]{1,9})?)?$",options:.regularExpression) != nil else{return nil}
        let p=value.split(separator:":");return(Int(p[0])!,Int(p[1])!,p.count>2 ? Int(Double(p[2])!) : 0)
    }
    static func clockSeconds(_ value:String) -> Int? {guard let(h,m,s)=clock(value)else{return nil};return h*3600+m*60+s}
    static func matches(_ lesson:Object,_ value:String) -> Bool {
        guard let d=date(value),validDate(text(lesson,"weekOne")),value >= text(lesson,"validFrom"),value <= text(lesson,"validUntil") else{return false}
        let weekday=(calendar().component(.weekday,from:d)+5)%7+1
        if weekday != number(lesson,"weekday"){return false}
        let week=Int(floor(Double(dayDistance(text(lesson,"weekOne"),value))/7))+1
        let parity=(week%2+2)%2
        return text(lesson,"parity")=="all" || text(lesson,"parity")=="even" && parity==0 || text(lesson,"parity")=="odd" && parity==1
    }
    static func localTime(_ day:String,_ clock:String,_ zone:String) throws -> Date {
        let c=calendar(zone)
        guard let midnight=formatter(zone).date(from:day),let (h,m,s)=self.clock(clock),let value=c.nextDate(after:midnight.addingTimeInterval(-1),matching:DateComponents(hour:h,minute:m,second:s),matchingPolicy:.nextTimePreservingSmallerComponents,repeatedTimePolicy:.first,direction:.forward) else{try fail("Не удалось рассчитать время занятия")}
        return value
    }
    static func times(_ lesson:Object,_ day:String) throws -> (Date,Date) {
        let start=try localTime(day,text(lesson,"startTime"),text(lesson,"timezone"))
        let endDay=(clockSeconds(text(lesson,"endTime")) ?? 0)<=(clockSeconds(text(lesson,"startTime")) ?? 0) ? shift(day,1):day
        let end=try localTime(endDay,text(lesson,"endTime"),text(lesson,"timezone"))
        try check(end>start,"После перевода часов занятие заканчивается раньше начала. Уточните его время.")
        return(start,end)
    }
    static func occurrences(_ records:[Object],_ exceptions:[Object],_ from:Date,_ until:Date,checkConflicts:Bool=true) throws -> [Object] {
        let subjects=Dictionary(uniqueKeysWithValues:records.filter{text(object($0,"data"),"kind")=="subject"}.map{(text($0,"id"),object($0,"data"))})
        var result=[Object]()
        for record in records where text(object(record,"data"),"kind")=="lesson" {
            let l=object(record,"data");let id=text(record,"id")
            guard let subject=subjects[text(l,"subjectId")] else{continue}
            let changes=exceptions.filter{text($0,"lessonId")==id}
            let overridden=Set(changes.map{text($0,"originalDate")})
            func add(_ day:String,_ start:Date,_ end:Date,_ changed:Bool){
                if start>=until || end<=from{return}
                let link=text(l,"onlineUrl").isEmpty ? text(subject,"onlineUrl"):text(l,"onlineUrl")
                result.append(["lessonId":id,"subjectId":text(l,"subjectId"),"title":text(subject,"title"),"startsAt":iso(start),"endsAt":iso(end),"onlineUrl":link,"room":text(l,"room"),"type":text(l,"type"),"originalDate":day,"changed":changed,"conflict":false])
            }
            var day=shift(dateString(from,text(l,"timezone")),-1)
            let last=dateString(until,text(l,"timezone"))
            while day<=last {
                if !overridden.contains(day) && matches(l,day) {let(s,e)=try times(l,day);add(day,s,e,false)}
                day=shift(day,1)
            }
            for e in changes {if let s=instant(text(e,"startsAt")),let end=instant(text(e,"endsAt")){add(text(e,"originalDate"),s,end,true)}}
        }
        let snapshot=result
        for i in result.indices where checkConflicts {
            result[i]["conflict"]=snapshot.indices.contains{j in i != j && text(snapshot[i],"startsAt") < text(snapshot[j],"endsAt") && text(snapshot[i],"endsAt") > text(snapshot[j],"startsAt")}
        }
        return result.sorted{text($0,"startsAt")<text($1,"startsAt")}
    }
}
