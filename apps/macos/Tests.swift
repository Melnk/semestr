import Foundation

/// Runs against a disposable database; never opens the user's study data.
func runStoreTests() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("semestr-test-"+newID())
    defer { try? FileManager.default.removeItem(at:directory) }
    let store = try LocalStore(directory:directory)
    var assertions=0
    func expect(_ condition:Bool,_ label:String) throws {try check(condition,"TEST: "+label);assertions+=1}
    func rejected(_ status:Int=422,_ operation:() throws -> Void) throws {
        do{try operation()}catch let error as LocalError{try expect(error.status==status,"expected \(status), got \(error.status): \(error.message)");return}
        try fail("TEST: invalid operation succeeded")
    }
    func call(_ path:String,_ method:String="GET",_ body:Object=[:]) throws -> Object {try store.request(path:path,method:method,body:body) as! Object}
    func create(_ data:Object) throws -> Object {try call("/records","POST",["data":data])}
    func account() throws -> Object {object(try call("/auth/session"),"account")}
    func update(_ record:Object,_ changes:Object) throws -> Object {
        try call("/records/"+text(record,"id"),"PUT",["version":number(record,"version"),"data":object(record,"data").merging(changes,uniquingKeysWith:{_,new in new})])
    }
    func remove(_ record:Object) throws {_=try store.request(path:"/records/\(text(record,"id"))?version=\(number(record,"version"))",method:"DELETE")}
    func schedule(_ from:String,_ until:String) throws -> [Object] {
        try store.request(path:"/schedule?from=\(from)&until=\(until)") as! [Object]
    }
    let originalAccount=try account()
    try expect(!text(originalAccount,"id").isEmpty && text(originalAccount,"email").isEmpty,"local account without login")
    var profile=object(originalAccount,"profile")
    profile["name"]="Тест";profile["timezone"]="Asia/Yekaterinburg";profile["weekOne"]="2026-09-07";profile["onboarded"]=true
    let updatedAccount=try call("/profile","PUT",["version":0,"profile":profile])
    try expect(number(updatedAccount,"version")==1 && number(updatedAccount,"revision")==1,"profile versions")
    try rejected(409){_=try call("/profile","PUT",["version":0,"profile":profile])}
    let subject=try create(["kind":"subject","title":"Математика","onlineUrl":"https://example.org/class"])
    let sid=text(subject,"id")
    try rejected{_=try create(["kind":"subject","title":" "])}
    try rejected{_=try create(["kind":"subject","title":"Unsafe","onlineUrl":"javascript:alert(1)"])}
    try rejected{_=try create(["kind":"note","subjectId":newID(),"text":"Orphan"])}
    let debt=try create(["kind":"debt","subjectId":sid,"nextStep":"Получить требования"])
    try rejected{_=try update(debt,["status":"closed"])}
    let closedDebt=try update(debt,["status":"closed","closedAt":"2026-10-07","confirmation":"Зачтено преподавателем"])
    try expect(text(object(closedDebt,"data"),"status")=="closed","confirmed debt closure")
    let task=try create(["kind":"task","subjectId":sid,"title":"Работа № 1","debtId":text(debt,"id")])
    let submitted=try update(task,["status":"submitted"])
    try expect(text(object(try call("/records/"+sid),"data"),"status")=="studying","submitted task does not close subject")
    try rejected(409){try remove(subject)}
    try rejected(409){try remove(closedDebt)}
    let other=try create(["kind":"subject","title":"Физика"])
    try rejected{_=try create(["kind":"task","subjectId":text(other,"id"),"title":"Mismatch","debtId":text(debt,"id")])}
    let note=try create(["kind":"note","subjectId":sid,"text":"Спросить на консультации"])
    let reopened=try LocalStore(directory:directory)
    let persisted=try reopened.request(path:"/records/"+text(note,"id")) as! Object
    try expect(text(object(persisted,"data"),"text")=="Спросить на консультации","SQLite survives reopening")
    let changed=try update(note,["text":"Уточнить формат"])
    try rejected(409){_=try reopened.request(path:"/records/"+text(note,"id"),method:"PUT",body:["version":0,"data":object(note,"data")])}
    try remove(changed)
    try rejected(404){_=try call("/records/"+text(note,"id"))}
    let page=try call("/records?limit=1")
    let page2=try call("/records?limit=1&cursor="+text(page,"nextCursor"))
    try expect(objects(page,"items").count==1 && text(objects(page,"items")[0],"id") != text(objects(page2,"items")[0],"id"),"cursor pagination")

    let lesson=try create(["kind":"lesson","subjectId":sid,"weekday":1,"startTime":"23:30","endTime":"00:30","validFrom":"2026-09-07","validUntil":"2026-12-31","timezone":"Asia/Yekaterinburg","parity":"odd","weekOne":"2026-09-07"])
    let lid=text(lesson,"id")
    let week=try schedule("2026-09-07T00:00:00Z","2026-09-21T00:00:00Z")
    try expect(week.count==1 && text(week[0],"startsAt")=="2026-09-07T18:30:00Z" && text(week[0],"endsAt")=="2026-09-07T19:30:00Z","timezone, odd weeks, overnight lesson")
    let cancel=try call("/schedule/"+lid+"/exception","PUT",["originalDate":"2026-09-07","startsAt":null,"endsAt":null])
    try expect(try schedule("2026-09-07T00:00:00Z","2026-09-08T00:00:00Z").isEmpty,"cancel one occurrence")
    let moved=try call("/schedule/"+lid+"/exception","PUT",["version":0,"originalDate":"2026-09-07","startsAt":"2026-10-08T08:00:00Z","endsAt":"2026-10-08T09:00:00Z"])
    let movedWindow=try schedule("2026-10-08T00:00:00Z","2026-10-09T00:00:00Z")
    try expect(movedWindow.count==1 && movedWindow[0]["changed"] as? Bool==true,"moved occurrence outside original date window")
    try rejected(409){_=try store.request(path:"/schedule/exceptions/\(text(cancel,"id"))?version=0",method:"DELETE")}
    try rejected{_=try update(lesson,["weekday":2])}
    _=try store.request(path:"/schedule/exceptions/\(text(moved,"id"))?version=1",method:"DELETE")
    try expect(try schedule("2026-09-07T00:00:00Z","2026-09-08T00:00:00Z").count==1,"restore occurrence")
    let collision=try create(object(lesson,"data").merging(["startTime":"23:45","endTime":"00:45"],uniquingKeysWith:{_,n in n}))
    let overlaps=try schedule("2026-09-07T00:00:00Z","2026-09-08T00:00:00Z")
    try expect(overlaps.count==2 && overlaps.allSatisfy{$0["conflict"] as? Bool==true},"overlap detection")
    try remove(collision)
    let spring=try CalendarRules.localTime("2026-03-29","02:30","Europe/Berlin")
    let autumn=try CalendarRules.localTime("2026-10-25","02:30","Europe/Berlin")
    try expect(CalendarRules.iso(spring)=="2026-03-29T01:30:00Z" && CalendarRules.iso(autumn)=="2026-10-25T00:30:00Z","DST gap and first overlap: \(CalendarRules.iso(spring)), \(CalendarRules.iso(autumn))")
    try rejected{_=try create(object(lesson,"data").merging(["endTime":"23:30:00"],uniquingKeysWith:{_,n in n}))}

    _=try call("/schedule/"+lid+"/exception","PUT",["originalDate":"2026-09-21","startsAt":null,"endsAt":null])
    let exported=try call("/export")
    let preview=try call("/import/preview","POST",exported)
    try expect(number(preview,"subjects")==2 && number(preview,"tasks")==1 && number(preview,"exceptions")==1,"export preview")
    var invalid=exported;var invalidRecords=objects(invalid,"records")
    invalidRecords.append(["id":newID(),"version":0,"data":["kind":"note","subjectId":newID(),"text":"Orphan"]])
    invalid["records"]=invalidRecords
    let before=try encoded(exported);let revision=number(try account(),"revision")
    try rejected{_=try call("/import","POST",["bundle":invalid,"mode":"replace","confirmed":true,"expectedRevision":revision])}
    try expect(try encoded(call("/export"))==before,"failed import rolls back everything")
    try rejected(409){_=try call("/import","POST",["bundle":exported,"mode":"add","expectedRevision":revision-1])}
    try rejected{_=try call("/import","POST",["bundle":exported,"mode":"replace","confirmed":false,"expectedRevision":revision])}
    _=try call("/import","POST",["bundle":exported,"mode":"add","expectedRevision":revision])
    let combined=try call("/export")
    try expect(objects(combined,"records").count==objects(exported,"records").count*2,"add import preserves existing records")
    let validated=try Rules.bundle(combined)
    try expect(validated.exceptions.count==2,"import remaps all references and exceptions")
    let replaceRevision=number(try account(),"revision")
    _=try call("/import","POST",["bundle":exported,"mode":"replace","confirmed":true,"expectedRevision":replaceRevision])
    try expect(objects(try call("/export"),"records").count==objects(exported,"records").count,"replace import")
    try expect(FileManager.default.fileExists(atPath:store.fileURL.path),"database file exists")
    // A file exported by one local account must work in an unrelated account.
    _=try call("/appearance/initialize","POST",["theme":"dark"])
    let settings=try call("/settings/export")
    let transferFile=directory.appendingPathComponent("settings.json")
    try encoded(settings).write(to:transferFile,options:.atomic)
    let fromFile=try JSONSerialization.jsonObject(with:Data(contentsOf:transferFile)) as! Object
    try expect(Set(fromFile.keys)==["format","formatVersion","profile","appearance"],"settings export contains no account ID or study records")
    let destination=try LocalStore(directory:directory.appendingPathComponent("other-account"))
    func dest(_ path:String,_ method:String="GET",_ body:Object=[:]) throws -> Object {try destination.request(path:path,method:method,body:body) as! Object}
    let destinationID=text(object(try dest("/auth/session"),"account"),"id")
    try expect(destinationID != text(try account(),"id"),"independent destination account")
    _=try dest("/import","POST",["bundle":exported,"mode":"add","expectedRevision":0])
    _=try dest("/appearance/initialize","POST",["theme":"light"])
    let destinationData=try dest("/export")
    let destinationBefore=object(try dest("/auth/session"),"account")
    let sourceBefore=try encoded(call("/settings/export"))
    let settingsPreview=try dest("/settings/preview","POST",fromFile)
    try expect(try encoded(object(dest("/auth/session"),"account"))==encoded(destinationBefore),"preview is read-only")
    let applied=try dest("/settings/import","POST",settingsPreview)
    let destinationAfter=object(applied,"account")
    try expect(text(destinationAfter,"id")==destinationID,"import keeps destination account identity")
    try expect(try encoded(object(destinationAfter,"profile"))==encoded(object(fromFile,"profile")),"profile transferred to another account")
    try expect(text(object(applied,"appearance"),"theme")=="dark","appearance transferred")
    let afterData=try dest("/export")
    try expect(try encoded(objects(afterData,"records"))==encoded(objects(destinationData,"records")) && encoded(objects(afterData,"exceptions"))==encoded(objects(destinationData,"exceptions")),"settings import preserves every study record and exception")
    try expect(number(destinationAfter,"version")==number(destinationBefore,"version")+1 && number(destinationAfter,"revision")==number(destinationBefore,"revision")+1,"settings import is one versioned transaction")
    try expect(try encoded(call("/settings/export"))==sourceBefore,"source account unchanged by transfer")
    try rejected(409){_=try dest("/settings/import","POST",settingsPreview)}
    let reopenedDestination=try LocalStore(directory:directory.appendingPathComponent("other-account"))
    let persistedSettings=try reopenedDestination.request(path:"/settings/export") as! Object
    try expect(try encoded(persistedSettings)==encoded(settings),"profile and theme survive reopening the destination database")
    try expect(text(try dest("/appearance/initialize","POST",["theme":"light"]),"theme")=="dark","legacy initialization cannot overwrite imported theme")
    let freshPreview=try dest("/settings/preview","POST",fromFile)
    _=try dest("/appearance","PUT",["theme":"light"])
    try rejected(409){_=try dest("/settings/import","POST",freshPreview)}
    let stableSettings=try encoded(dest("/settings/export"))
    let invalidChanges:[Object]=[["format":"another-app"],["formatVersion":2],["formatVersion":true],["formatVersion":1.5],["appearance":["theme":"unknown"]],["accountId":newID()],["profile":["name":"Incomplete"]]]
    for change in invalidChanges {
        let invalidSettings=fromFile.merging(change,uniquingKeysWith:{_,new in new})
        try rejected{_=try dest("/settings/preview","POST",invalidSettings)}
        try rejected{_=try dest("/settings/import","POST",["bundle":invalidSettings,"expectedRevision":number(object(try dest("/auth/session"),"account"),"revision")])}
    }
    try rejected{_=try dest("/settings/preview","POST",exported)}
    try expect(try encoded(dest("/settings/export"))==stableSettings,"invalid imports leave both profile and theme intact")
    // An academic difference can be entered with a title in an entirely empty workspace.
    let quickDirectory=directory.appendingPathComponent("quick-debt")
    let quickStore=try LocalStore(directory:quickDirectory)
    func quick(_ path:String,_ method:String="GET",_ body:Object=[:]) throws -> Object {try quickStore.request(path:path,method:method,body:body) as! Object}
    let quickBefore=try encoded(quick("/export"))
    let badRequests:[Object]=[
        ["subjectTitle":"  ","data":["kind":"debt"]],
        ["subjectTitle":String(repeating:"А",count:301),"data":["kind":"debt"]],
        ["subjectTitle":"Новый предмет","data":["kind":"debt","status":"closed"]],
        ["subjectTitle":"Новый предмет","data":["kind":"debt","deadline":"2026-02-30"]],
        ["subjectTitle":"Новый предмет","data":["kind":"note","text":"Wrong kind"]]
    ]
    for body in badRequests {
        try rejected{_=try quick("/debts/with-subject","POST",body)}
        try expect(try encoded(quick("/export"))==quickBefore && number(object(quick("/auth/session"),"account"),"revision")==0,"invalid debt leaves no subject and no revision change")
    }
    let quickResult=try quick("/debts/with-subject","POST",["subjectTitle":"  Теория вероятностей  ","data":["kind":"debt"]])
    let quickSubject=object(quickResult,"subject");let quickDebt=object(quickResult,"debt")
    try expect(text(object(quickSubject,"data"),"title")=="Теория вероятностей","debt creates a subject from its trimmed title")
    try expect(text(object(quickDebt,"data"),"subjectId")==text(quickSubject,"id") && text(object(quickDebt,"data"),"reason")=="difference" && text(object(quickDebt,"data"),"status")=="clarify","academic difference with minimal input")
    try expect(objects(try quick("/records"),"items").count==2 && number(object(try quick("/auth/session"),"account"),"revision")==1,"subject and debt saved in one transaction")
    let anotherPair=try quick("/debts/with-subject","POST",["subjectTitle":"Финансовая грамотность","data":["kind":"debt","subjectId":text(quickSubject,"id"),"teacher":"Преподаватель","requirements":"Два задания","deadline":"2026-12-15"]])
    let anotherSubject=object(anotherPair,"subject");let anotherDebt=object(anotherPair,"debt")
    try expect(text(object(anotherDebt,"data"),"subjectId")==text(anotherSubject,"id") && text(anotherSubject,"id") != text(quickSubject,"id"),"new debt uses its new subject, not the previously selected one")
    try expect(text(object(anotherSubject,"data"),"teacher")=="Преподаватель" && text(object(anotherDebt,"data"),"requirements")=="Два задания","optional debt details preserved")
    _=try quick("/records","POST",["data":["kind":"debt","subjectId":text(quickSubject,"id")]])
    try expect(objects(try quick("/records?kind=subject"),"items").count==2,"choosing an existing subject does not create a duplicate")
    let reopenedQuick=try LocalStore(directory:quickDirectory)
    try expect(objects(try reopenedQuick.request(path:"/records") as! Object,"items").count==5,"new subjects and debts survive reopening")
    _=submitted
    print("PASS: \(assertions) native storage checks — persistence, schedule, transfers and atomic subject/debt creation.")
}
