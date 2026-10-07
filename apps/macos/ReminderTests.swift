import Foundation

func runReminderTests() throws {
    var assertions=0
    func expect(_ value:Bool,_ name:String) throws{try check(value,"REMINDER TEST: "+name);assertions+=1}
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent("semestr-reminders-"+newID())
    defer{try? FileManager.default.removeItem(at:directory)}
    let store=try LocalStore(directory:directory)
    func call(_ route:String,_ method:String="GET",_ body:Object=[:]) throws -> Object {try store.request(path:route,method:method,body:body) as! Object}
    let defaults=try call("/notifications")
    try expect(defaults["enabled"] as? Bool==false && defaults["lessonTypes"] as? [String]==["practice"] && defaults["deadlineMinutes"] as? [Int]==[60,1440],"opt-in defaults match requested reminders")
    var prefs=defaults;prefs["enabled"]=true
    _=try call("/notifications","PUT",prefs)
    let reopened=try LocalStore(directory:directory)
    try expect(try encoded(reopened.request(path:"/notifications"))==encoded(prefs),"preferences survive reopening")
    let invalids:[Object]=[["enabled":1],["lessonMinutes":true],["lessonMinutes":1.5],["lessonMinutes":0],["lessonMinutes":121],["lessonTypes":["exam"]],["lessonTypes":[String]()],["deadlineMinutes":[60,60]],["deadlineMinutes":[true]],["deadlineMinutes":[60.5]],["deadlineMinutes":[Int]()],["debtTime":"24:00"],["extra":true]]
    for change in invalids {
        do{_=try call("/notifications","PUT",prefs.merging(change,uniquingKeysWith:{_,n in n}));try fail("Invalid preference accepted",500)}
        catch let e as LocalError {try expect(e.status==422,"invalid preferences rejected")}
    }
    try expect(try encoded(call("/notifications"))==encoded(prefs),"invalid updates leave settings unchanged")
    let exported=try call("/settings/export")
    let destination=try LocalStore(directory:directory.appendingPathComponent("recipient"))
    let preview=try destination.request(path:"/settings/preview",method:"POST",body:exported) as! Object
    _=try destination.request(path:"/settings/import",method:"POST",body:preview)
    try expect(try encoded(destination.request(path:"/notifications"))==encoded(prefs),"notification settings transfer between accounts")
    var legacy=exported;legacy.removeValue(forKey:"notifications")
    let legacyPreview=try destination.request(path:"/settings/preview",method:"POST",body:legacy) as! Object
    _=try destination.request(path:"/settings/import",method:"POST",body:legacyPreview)
    try expect(try encoded(destination.request(path:"/notifications"))==encoded(prefs),"old settings files preserve notification preferences")

    let sid=newID(),lid=newID(),lectureID=newID(),taskID=newID(),debtID=newID()
    let subject:Object=["id":sid,"data":["kind":"subject","title":"Математика","status":"studying"]]
    let lesson=try Rules.normalize(["kind":"lesson","subjectId":sid,"weekday":1,"startTime":"12:00","endTime":"13:30","validFrom":"2026-10-05","validUntil":"2026-10-05","timezone":"Asia/Yekaterinburg","parity":"all","weekOne":"2026-10-05"])
    let practice:Object=["id":lid,"data":lesson]
    let lecture:Object=["id":lectureID,"data":lesson.merging(["type":"lecture"],uniquingKeysWith:{_,n in n})]
    let task:Object=["id":taskID,"data":["kind":"task","subjectId":sid,"title":"Проект","status":"todo","deadline":"2026-10-06T12:00:00Z"]]
    let debt:Object=["id":debtID,"data":["kind":"debt","subjectId":sid,"status":"working","deadline":"2026-10-06"]]
    let records=[subject,practice,lecture,task,debt]
    let snapshot:Object=["notifications":prefs,"profile":["timezone":"Asia/Yekaterinburg"],"records":records,"exceptions":[Object]()]
    let now=CalendarRules.instant("2026-10-05T05:00:00Z")!
    func plan(_ changes:Object=[:],at:Date?=nil,limit:Int=60) throws -> ReminderPlan {try ReminderPlanner.plan(snapshot.merging(changes,uniquingKeysWith:{_,n in n}),now:at ?? now,limit:limit)}
    let base=try plan().reminders
    try expect(base.count==5,"practice plus two task and two debt reminders")
    try expect(base.first?.fireAt==CalendarRules.instant("2026-10-05T06:55:00Z") && base.first?.recordID==lid,"practice five minutes before in lesson timezone")
    try expect(base.filter{$0.recordID==lectureID}.isEmpty,"practice-only excludes lectures")
    try expect(base.filter{$0.recordID==taskID}.map(\.fireAt)==[CalendarRules.instant("2026-10-05T12:00:00Z")!,CalendarRules.instant("2026-10-06T11:00:00Z")!],"both deadline offsets scheduled")
    try expect(base.filter{$0.recordID==debtID}.map(\.fireAt)==[CalendarRules.instant("2026-10-05T13:00:00Z")!,CalendarRules.instant("2026-10-06T12:00:00Z")!],"date-only debt uses configured local time")
    let cancel:Object=["lessonId":lid,"originalDate":"2026-10-05","startsAt":null,"endsAt":null]
    try expect(try plan(["exceptions":[cancel]]).reminders.count==4,"cancel removes the original occurrence")
    let moved=cancel.merging(["startsAt":"2026-10-07T08:00:00Z","endsAt":"2026-10-07T09:00:00Z"],uniquingKeysWith:{_,n in n})
    let changed=try plan(["exceptions":[moved]]).reminders.first{$0.recordID==lid}!
    try expect(changed.fireAt==CalendarRules.instant("2026-10-07T07:55:00Z") && changed.id==base.first!.id && changed.signature != base.first!.signature,"moved occurrence replaces same notification identity")
    var off=prefs;off["enabled"]=false
    try expect(try plan(["notifications":off]).reminders.isEmpty,"master switch removes all reminders")
    var noClasses=prefs;noClasses["lessonsEnabled"]=false
    try expect(try plan(["notifications":noClasses]).reminders.count==4,"independent lesson switch")
    var noDeadlines=prefs;noDeadlines["deadlinesEnabled"]=false
    try expect(try plan(["notifications":noDeadlines]).reminders.count==1,"independent deadline switch")
    let closedSubject:Object=["id":sid,"data":["kind":"subject","title":"Математика","status":"closed"]]
    try expect(try plan(["records":[closedSubject,practice,lecture,task,debt]]).reminders.isEmpty,"archived subjects are quiet")
    for status in ["submitted","accepted"] {
        let completed:Object=["id":taskID,"data":object(task,"data").merging(["status":status],uniquingKeysWith:{_,n in n})]
        try expect(try plan(["records":[subject,completed]]).reminders.isEmpty,"handed-in tasks are quiet")
    }
    let closedDebt:Object=["id":debtID,"data":object(debt,"data").merging(["status":"closed"],uniquingKeysWith:{_,n in n})]
    try expect(try plan(["records":[subject,closedDebt]]).reminders.isEmpty,"closed debts are quiet")
    let late=try plan(at:CalendarRules.instant("2026-10-06T11:30:00Z")!).reminders
    try expect(late.count==1 && late[0].recordID==debtID,"never delivers past reminders on restart")
    let capped=try plan(limit:2)
    try expect(capped.reminders.count==2 && capped.truncated && capped.coveredUntil==capped.reminders.last?.fireAt,"queue bound exposes coverage date")
    var allTypes=prefs;allTypes["lessonTypes"]=["practice","lecture","lab"]
    try expect(try plan(["notifications":allTypes]).reminders.count==6,"enabling lectures adds reminders")
    let dstLesson=lesson.merging(["weekday":7,"startTime":"02:30","endTime":"04:00","validFrom":"2026-03-29","validUntil":"2026-03-29","weekOne":"2026-03-23","timezone":"Europe/Berlin"],uniquingKeysWith:{_,n in n})
    let dst=try plan(["records":[subject,["id":lid,"data":dstLesson]]],at:CalendarRules.instant("2026-03-28T00:00:00Z")!).reminders
    try expect(dst.first?.fireAt==CalendarRules.instant("2026-03-29T01:25:00Z"),"DST transition follows schedule time rules")
    print("PASS: \(assertions) reminder checks — preferences, transfer, offsets, timezone, moves, closure and queue coverage.")
}

@MainActor func runDeliveryTests() async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent("semestr-delivery-"+newID())
    defer{try? FileManager.default.removeItem(at:directory)}
    let store=try LocalStore(directory:directory),driver=TestReminderDelivery()
    let service=NotificationService(store:store,delivery:driver)
    let subject=try store.request(path:"/records",method:"POST",body:["data":["kind":"subject","title":"Предмет"]]) as! Object
    let task=try store.request(path:"/records",method:"POST",body:["data":["kind":"task","subjectId":text(subject,"id"),"title":"Проект","deadline":CalendarRules.iso(Date().addingTimeInterval(3*86400))]]) as! Object
    var prefs=ReminderPreferences.defaults;prefs["enabled"]=true
    _=try store.request(path:"/notifications",method:"PUT",body:prefs)
    _=await service.status();try check(driver.queue.isEmpty,"No scheduling without permission")
    _=try await service.requestPermission();try check(driver.queue.count==2,"Authorized service schedules both deadlines")
    let additions=driver.additions
    _=await service.status();try check(driver.additions==additions,"Refresh must not duplicate unchanged requests")
    let moved=object(task,"data").merging(["deadline":CalendarRules.iso(Date().addingTimeInterval(4*86400))],uniquingKeysWith:{_,n in n})
    _=try store.request(path:"/records/"+text(task,"id"),method:"PUT",body:["version":0,"data":moved])
    _=await service.status();try check(driver.queue.count==2 && driver.additions==additions+2,"Changed deadline replaces queue entries")
    driver.permission="denied";_=await service.status();try check(driver.queue.isEmpty,"Revocation clears pending reminders")
    driver.permission="authorized";_=await service.status();try check(driver.queue.count==2,"Grant restores future reminders")
    prefs["enabled"]=false;_=try store.request(path:"/notifications",method:"PUT",body:prefs)
    _=await service.status();try check(driver.queue.isEmpty,"Disable clears delivery queue")
    prefs["enabled"]=true;_=try store.request(path:"/notifications",method:"PUT",body:prefs)
    _=await service.status()
    _=try store.request(path:"/records/"+text(task,"id"),method:"PUT",body:["version":1,"data":moved.merging(["status":"accepted"],uniquingKeysWith:{_,n in n})])
    _=await service.status();try check(driver.queue.isEmpty,"Accepting task cancels pending reminders")
    print("PASS: 8 delivery checks — permission, deduplication, deadline edits, revocation, disable and completion.")
}
