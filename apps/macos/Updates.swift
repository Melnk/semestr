import AppKit
import CryptoKit

struct UpdateVersion: Comparable {
    let parts: [Int]
    init?(_ value: String) {
        guard value.range(of: "^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$", options: .regularExpression) != nil else { return nil }
        let parts=value.split(separator: ".").compactMap { Int($0) }
        guard parts.count==3 else { return nil }; self.parts=parts
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }
}

struct UpdateError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct AppRelease: Codable {
    static let repository="https://github.com/Melnk/semestr"
    static let endpoint=URL(string:"https://api.github.com/repos/Melnk/semestr/releases/latest")!
    static let installerName="Semestr-macOS-universal.dmg"
    static let maxInstallerSize=200_000_000
    let version: String
    let tag: String
    let size: Int
    var page: URL { URL(string:Self.repository+"/releases/tag/"+tag)! }
    var installer: URL { URL(string:Self.repository+"/releases/download/"+tag+"/"+Self.installerName)! }
    var checksums: URL { URL(string:Self.repository+"/releases/download/"+tag+"/SHA256SUMS.txt")! }
    var valid: Bool { UpdateVersion(version) != nil && tag=="v"+version && size>0 && size<=Self.maxInstallerSize }

    static func parse(_ data: Data) throws -> Self {
        struct Asset: Decodable { let name:String; let state:String; let size:Int; let browser_download_url:String }
        struct Release: Decodable { let tag_name:String; let draft:Bool; let prerelease:Bool; let assets:[Asset] }
        guard data.count<=1_000_000,let raw=try? JSONDecoder().decode(Release.self,from:data),
              !raw.draft,!raw.prerelease,raw.tag_name.hasPrefix("v") else {
            throw UpdateError(message:"Не удалось прочитать стабильный релиз GitHub. Попробуйте проверить позже.")
        }
        let installers=raw.assets.filter{$0.name==installerName},sums=raw.assets.filter{$0.name=="SHA256SUMS.txt"}
        guard installers.count==1,sums.count==1 else { throw UpdateError(message:"Установщик новой версии ещё не опубликован. Проверьте позже.") }
        let release=Self(version:String(raw.tag_name.dropFirst()),tag:raw.tag_name,size:installers[0].size)
        guard release.valid,installers[0].state=="uploaded",sums[0].state=="uploaded",sums[0].size>0,sums[0].size<=32_000,
              installers[0].browser_download_url==release.installer.absoluteString,sums[0].browser_download_url==release.checksums.absoluteString else {
            throw UpdateError(message:"Файлы релиза не прошли проверку. Попробуйте позже.")
        }
        return release
    }

    func verify(_ file: URL, manifest: Data) throws {
        guard manifest.count<=32_000,let content=String(data:manifest,encoding:.utf8) else { throw UpdateError(message:"Не удалось проверить контрольную сумму обновления.") }
        let hashes=content.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            let fields=line.split(whereSeparator: \.isWhitespace)
            guard fields.count==2,fields[1]==Self.installerName || fields[1]=="*"+Self.installerName else { return nil }
            return String(fields[0]).lowercased()
        }
        guard hashes.count==1,hashes[0].range(of:"^[0-9a-f]{64}$",options:.regularExpression) != nil,
              (try file.resourceValues(forKeys:[.fileSizeKey])).fileSize==size else { throw UpdateError(message:"Установщик загружен не полностью. Нажмите «Обновить», чтобы повторить.") }
        let handle=try FileHandle(forReadingFrom:file);defer{try? handle.close()}
        var hash=SHA256()
        while let chunk=try handle.read(upToCount:1_048_576),!chunk.isEmpty { hash.update(data:chunk) }
        guard hash.finalize().map({String(format:"%02x",$0)}).joined()==hashes[0] else { throw UpdateError(message:"Контрольная сумма не совпала. Установщик не открыт. Попробуйте скачать обновление ещё раз.") }
    }
}

protocol UpdateTransport {
    func data(from url: URL, limit: Int) async throws -> Data
    func download(from url: URL, to file: URL, limit: Int) async throws
}

/// Restricts redirects to GitHub's release infrastructure and bounds download size.
private final class UpdateDownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let limit: Int
    init(limit:Int) { self.limit=limit }
    static func allows(_ url:URL) -> Bool {
        url.scheme=="https" && url.user==nil && url.password==nil && (url.port==nil || url.port==443) &&
        ["api.github.com","github.com","release-assets.githubusercontent.com","objects.githubusercontent.com"].contains(url.host ?? "")
    }
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping(URLRequest?)->Void) {
        completionHandler(request.url.map(Self.allows)==true ? request:nil)
    }
    func urlSession(_ session:URLSession,downloadTask:URLSessionDownloadTask,didWriteData bytesWritten:Int64,totalBytesWritten:Int64,totalBytesExpectedToWrite:Int64) {
        if totalBytesWritten>limit || totalBytesExpectedToWrite>limit { downloadTask.cancel() }
    }
    func urlSession(_ session:URLSession,downloadTask:URLSessionDownloadTask,didFinishDownloadingTo location:URL) {}
}

final class GitHubUpdateTransport: UpdateTransport {
    private let session: URLSession
    init() {
        let configuration=URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage=nil;configuration.urlCredentialStorage=nil
        configuration.httpShouldSetCookies=false;configuration.waitsForConnectivity=false
        configuration.timeoutIntervalForRequest=20;configuration.timeoutIntervalForResource=180
        session=URLSession(configuration:configuration)
    }
    private func fetch(_ url:URL,limit:Int) async throws -> URL {
        guard UpdateDownloadDelegate.allows(url) else { throw UpdateError(message:"Недопустимый адрес обновления.") }
        var request=URLRequest(url:url,cachePolicy:.reloadIgnoringLocalCacheData)
        request.setValue("Semestr",forHTTPHeaderField:"User-Agent")
        if url.host=="api.github.com" {
            request.setValue("application/vnd.github+json",forHTTPHeaderField:"Accept")
            request.setValue("2022-11-28",forHTTPHeaderField:"X-GitHub-Api-Version")
        }
        let (file,response)=try await session.download(for:request,delegate:UpdateDownloadDelegate(limit:limit))
        do {
            guard let http=response as? HTTPURLResponse,http.statusCode==200 else {
                let status=(response as? HTTPURLResponse)?.statusCode
                throw UpdateError(message:status==403 || status==429 ? "GitHub временно ограничил проверки. Попробуйте позже.":"GitHub не вернул файл обновления. Попробуйте позже.")
            }
            guard let size=try file.resourceValues(forKeys:[.fileSizeKey]).fileSize,size<=limit else { throw UpdateError(message:"Файл обновления слишком большой.") }
            return file
        } catch { try? FileManager.default.removeItem(at:file);throw error }
    }
    func data(from url:URL,limit:Int) async throws -> Data {
        let file=try await fetch(url,limit:limit);defer{try? FileManager.default.removeItem(at:file)}
        return try Data(contentsOf:file)
    }
    func download(from url:URL,to file:URL,limit:Int) async throws {
        let temporary=try await fetch(url,limit:limit);defer{try? FileManager.default.removeItem(at:temporary)}
        try FileManager.default.moveItem(at:temporary,to:file)
    }
}

@MainActor final class UpdateService {
    private struct Cache: Codable {
        var automatic=true
        var lastAttempt:Date?
        var lastChecked:Date?
        var latest:AppRelease?
    }
    let currentVersion:String
    private let file:URL
    private let downloads:URL
    private let transport:UpdateTransport
    private let now:()->Date
    private let openInstaller:(URL)->Bool
    private var cache=Cache()
    private var checking=false
    private var downloading=false
    private var ready:URL?
    private var error=""
    var onChange:(()->Void)?

    init(directory:URL,downloads:URL,currentVersion:String,transport:UpdateTransport,now:@escaping()->Date=Date.init,openInstaller:@escaping(URL)->Bool={NSWorkspace.shared.open($0)}) {
        self.file=directory.appendingPathComponent("updates.json");self.downloads=downloads
        self.currentVersion=currentVersion;self.transport=transport;self.now=now;self.openInstaller=openInstaller
        if let data=try? Data(contentsOf:file),data.count<=64_000,let saved=try? JSONDecoder().decode(Cache.self,from:data) {
            cache=saved;if cache.latest?.valid != true {cache.latest=nil}
        }
    }
    private var available:AppRelease? {
        guard let release=cache.latest,let current=UpdateVersion(currentVersion),let latest=UpdateVersion(release.version),latest>current else {return nil}
        return release
    }
    func status() -> Object {
        ["currentVersion":currentVersion,"automatic":cache.automatic,"lastCheckedAt":cache.lastChecked.map(CalendarRules.iso) as Any? ?? null,
         "checking":checking,"downloading":downloading,"availableVersion":available?.version as Any? ?? null,
         "releaseURL":available?.page.absoluteString as Any? ?? null,"installerReady":ready != nil,"error":error]
    }
    private func persist() throws {
        try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
        try JSONEncoder().encode(cache).write(to:file,options:.atomic)
    }
    func setAutomatic(_ enabled:Bool) throws {
        let previous=cache.automatic;cache.automatic=enabled
        do {try persist()} catch {cache.automatic=previous;throw UpdateError(message:"Не удалось сохранить настройку обновлений.")}
        onChange?()
    }
    func refreshIfDue() { Task { @MainActor [weak self] in await self?.checkForUpdates() } }
    func checkForUpdates(force:Bool=false) async {
        guard !checking,!downloading else {return}
        let date=now()
        if !force {
            guard cache.automatic else{return}
            // A failed/offline attempt can retry in an hour; a successful check lasts a day.
            if let checked=cache.lastChecked,date>=checked,date.timeIntervalSince(checked)<86400{return}
            if let attempted=cache.lastAttempt,date>=attempted,date.timeIntervalSince(attempted)<3600{return}
        }
        checking=true;error="";cache.lastAttempt=date;try? persist();onChange?()
        defer {checking=false;onChange?()}
        do {
            let release=try AppRelease.parse(await transport.data(from:AppRelease.endpoint,limit:1_000_000))
            if cache.latest?.version != release.version {ready=nil}
            cache.latest=release;cache.lastChecked=now();try persist()
        } catch {self.error=message(error)}
    }
    func downloadUpdate() async {
        guard !checking,!downloading,let release=available else{return}
        downloading=true;error="";onChange?();defer{downloading=false;onChange?()}
        var staging:URL?
        do {
            // Fetch checksums again even for a previously downloaded installer.
            let manifest=try await transport.data(from:release.checksums,limit:32_000)
            if let ready=ready {
                try release.verify(ready,manifest:manifest)
                guard openInstaller(ready) else {throw UpdateError(message:"Не удалось открыть установщик. Попробуйте ещё раз.")}
                return
            }
            let folder=downloads.appendingPathComponent(newID(),isDirectory:true)
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700]);staging=folder
            let target=folder.appendingPathComponent("Semestr-"+release.version+".dmg")
            try await transport.download(from:release.installer,to:target,limit:release.size)
            try release.verify(target,manifest:manifest)
            // Preserve macOS checks for an installer obtained from the internet.
            let quarantine="0083;"+String(Int(now().timeIntervalSince1970),radix:16)+";Semestr;"+UUID().uuidString
            let result=quarantine.withCString { bytes in setxattr(target.path,"com.apple.quarantine",bytes,strlen(bytes),0,0) }
            guard result==0 else {throw UpdateError(message:"Не удалось подготовить установщик для macOS. Попробуйте скачать его со страницы релиза.")}
            guard openInstaller(target) else {throw UpdateError(message:"Не удалось открыть установщик. Попробуйте ещё раз.")}
            ready=target;staging=nil
        } catch {
            ready=nil;if let staging=staging {try? FileManager.default.removeItem(at:staging)}
            self.error=message(error)
        }
    }
    private func message(_ error:Error) -> String {
        if let error=error as? UpdateError {return error.message}
        if error is URLError {return "Не удалось связаться с GitHub. Проверьте интернет и попробуйте ещё раз."}
        return "Не удалось подготовить обновление. Проверьте свободное место и попробуйте ещё раз."
    }
}
