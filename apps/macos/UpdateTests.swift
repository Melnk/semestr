import Foundation
import CryptoKit

final class TestUpdateTransport: UpdateTransport {
    var version="0.6.0"
    var failure=false
    var corrupt=false
    var checks=0
    var downloads=0
    var releaseOverride:Data?
    let installer=Data("Disposable installer fixture — never opened by macOS".utf8)
    func release() throws -> Data {
        try encoded(["tag_name":"v"+version,"draft":false,"prerelease":false,"assets":[
            ["name":AppRelease.installerName,"state":"uploaded","size":installer.count,"browser_download_url":AppRelease.repository+"/releases/download/v"+version+"/"+AppRelease.installerName],
            ["name":"SHA256SUMS.txt","state":"uploaded","size":100,"browser_download_url":AppRelease.repository+"/releases/download/v"+version+"/SHA256SUMS.txt"]]])
    }
    func data(from url:URL,limit:Int) async throws -> Data {
        if url==AppRelease.endpoint {checks+=1}
        await Task.yield()
        if failure {throw URLError(.notConnectedToInternet)}
        if url==AppRelease.endpoint {return try releaseOverride ?? release()}
        return Data((SHA256.hash(data:installer).map{String(format:"%02x",$0)}.joined()+"  "+AppRelease.installerName+"\n").utf8)
    }
    func download(from url:URL,to file:URL,limit:Int) async throws {
        downloads+=1
        try (corrupt ? Data(repeating:0,count:installer.count):installer).write(to:file)
    }
}

@MainActor func runUpdateTests() async throws {
    var assertions=0
    func expect(_ value:Bool,_ name:String) throws {try check(value,"UPDATE TEST: "+name);assertions+=1}
    try expect(UpdateVersion("0.10.0")!>UpdateVersion("0.9.9")!,"numeric minor comparison")
    try expect(UpdateVersion("1.0.0")!>UpdateVersion("0.99.99")!,"major comparison")
    try expect(UpdateVersion("0.5.10")!>UpdateVersion("0.5.9")!,"numeric patch comparison")
    for invalid in ["v0.5.0","0.5.0-beta","0.5","0.05.0","../0.5.0","1.0.0/evil","999999999999999999999.0.0"] {
        try expect(UpdateVersion(invalid)==nil,"reject invalid stable version")
    }
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent("semestr-updates-"+newID())
    defer{try? FileManager.default.removeItem(at:directory)}
    let driver=TestUpdateTransport()
    var date=Date(timeIntervalSince1970:1_800_000_000)
    var opened=[URL]()
    func service(_ version:String="0.5.0") -> UpdateService {
        UpdateService(directory:directory,downloads:directory.appendingPathComponent("downloads"),currentVersion:version,transport:driver,now:{date},openInstaller:{opened.append($0);return true})
    }
    let first=service()
    try expect(first.status()["automatic"] as? Bool==true,"daily checks enabled by default")
    await first.checkForUpdates()
    try expect(text(first.status(),"availableVersion")=="0.6.0" && driver.checks==1,"new release appears on first check")
    await first.checkForUpdates()
    let reopened=service();await reopened.checkForUpdates()
    try expect(driver.checks==1 && text(reopened.status(),"availableVersion")=="0.6.0","cached availability and daily throttle survive restart")
    date=date.addingTimeInterval(86400);await reopened.checkForUpdates()
    try expect(driver.checks==2,"checks after a day without restart")
    try reopened.setAutomatic(false);date=date.addingTimeInterval(86400);await reopened.checkForUpdates()
    try expect(driver.checks==2 && service().status()["automatic"] as? Bool==false,"disabled automatic check persists")
    await reopened.checkForUpdates(force:true)
    try expect(driver.checks==3,"manual check works when automatic is off")
    let updated=service("0.6.0")
    try expect(updated.status()["availableVersion"] is NSNull,"updated app hides cached release")
    await updated.checkForUpdates(force:true)
    try expect(updated.status()["availableVersion"] is NSNull,"equal version is current")
    let newer=service("0.7.0");await newer.checkForUpdates(force:true)
    try expect(newer.status()["availableVersion"] is NSNull,"no downgrade offered")
    try reopened.setAutomatic(true)
    date=date.addingTimeInterval(86400);driver.failure=true;await reopened.checkForUpdates()
    try expect(!text(reopened.status(),"error").isEmpty && text(reopened.status(),"availableVersion")=="0.6.0","offline failure preserves known update")
    let attempts=driver.checks;await reopened.checkForUpdates()
    try expect(driver.checks==attempts,"offline failures do not retry every timer tick")
    date=date.addingTimeInterval(3600);driver.failure=false;await reopened.checkForUpdates()
    try expect(driver.checks==attempts+1 && text(reopened.status(),"error").isEmpty,"retries recover after connectivity failure")
    date=date.addingTimeInterval(-864000);await reopened.checkForUpdates()
    try expect(driver.checks==attempts+2,"clock rollback does not suppress checks indefinitely")
    async let a:Void=reopened.checkForUpdates(force:true)
    async let b:Void=reopened.checkForUpdates(force:true)
    await a;await b
    try expect(driver.checks==attempts+3,"overlapping manual and scheduled checks coalesce")

    let good=try JSONSerialization.jsonObject(with:driver.release()) as! Object
    for patch:Object in [["draft":true],["prerelease":true],["assets":[]],["tag_name":"v0.6.0-rc1"]] {
        do { _=try AppRelease.parse(encoded(good.merging(patch,uniquingKeysWith:{_,n in n})));try fail("Invalid release accepted",500) }
        catch is UpdateError {try expect(true,"invalid or incomplete release rejected")}
    }
    var bad=good;var assets=objects(good,"assets");assets[0]["browser_download_url"]="https://example.com/app.dmg";bad["assets"]=assets
    do {_=try AppRelease.parse(encoded(bad));try fail("Untrusted asset accepted",500)}catch is UpdateError {try expect(true,"external installer URL rejected")}
    driver.releaseOverride=Data("malformed".utf8);await reopened.checkForUpdates(force:true)
    try expect(text(reopened.status(),"availableVersion")=="0.6.0" && !text(reopened.status(),"error").isEmpty,"malformed response preserves cached update")
    driver.releaseOverride=nil

    driver.corrupt=true;await reopened.downloadUpdate()
    try expect(opened.isEmpty && !text(reopened.status(),"error").isEmpty,"checksum mismatch never opens installer")
    let downloads=directory.appendingPathComponent("downloads")
    try expect(try FileManager.default.contentsOfDirectory(atPath:downloads.path).isEmpty,"failed download removed")
    driver.corrupt=false;await reopened.downloadUpdate()
    try expect(opened.count==1 && reopened.status()["installerReady"] as? Bool==true,"verified download can open installer")
    if let target=opened.first {
        try expect(getxattr(target.path,"com.apple.quarantine",nil,0,0,0)>0,"installer retains macOS quarantine")
        let count=driver.downloads;await reopened.downloadUpdate()
        try expect(opened.count==2 && driver.downloads==count,"reopen verified cached installer without downloading again")
        try Data(repeating:0,count:driver.installer.count).write(to:target)
        await reopened.downloadUpdate()
        try expect(opened.count==2 && reopened.status()["installerReady"] as? Bool==false,"modified cached installer blocked")
    }
    print("PASS: \(assertions) update checks — stable versions, daily scheduling, restart, offline recovery, trusted assets, checksums and installer opening.")
}
