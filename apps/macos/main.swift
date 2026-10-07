import AppKit
import WebKit
import UniformTypeIdentifiers

final class DesktopBridge: NSObject, WKScriptMessageHandlerWithReply {
    let store: LocalStore
    let assets: URL
    private let testTransferDirectory:URL?
    init(store:LocalStore,assets:URL,testTransferDirectory:URL?=nil){self.store=store;self.assets=assets;self.testTransferDirectory=testTransferDirectory}
    private func chooseTransferFile(settings:Bool,saving:Bool,completion:@escaping(URL?)->Void){
        // UI tests use actual files in their own temporary directory, bypassing only the picker.
        if let directory=testTransferDirectory {completion(directory.appendingPathComponent(settings ? "settings.json":"study-data.json"));return}
        if saving {
            let panel=NSSavePanel();panel.allowedContentTypes=[.json]
            panel.nameFieldStringValue="Семестр\(settings ? " — настройки":"") — \(CalendarRules.dateString(Date())).json"
            panel.title=settings ? "Сохранить настройки Семестра":"Сохранить данные Семестра"
            panel.begin{completion($0 == .OK ? panel.url:nil)}
        }else{
            let panel=NSOpenPanel();panel.allowedContentTypes=[.json];panel.allowsMultipleSelection=false;panel.canChooseDirectories=false
            panel.title=settings ? "Загрузить настройки Семестра":"Импортировать данные Семестра"
            panel.begin{completion($0 == .OK ? panel.url:nil)}
        }
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
        guard message.frameInfo.isMainFrame, let source=message.frameInfo.request.url,source.isFileURL,source.standardizedFileURL.path.hasPrefix(assets.standardizedFileURL.path+"/"),let request=message.body as? Object else {replyHandler(nil,"Недопустимый источник запроса");return}
        func success(_ result:Any = NSNull()){replyHandler(["ok":true,"data":result],nil)}
        func failure(_ error:Error){let e=error as? LocalError;replyHandler(["ok":false,"status":e?.status ?? 500,"code":e?.code ?? "storage","message":e?.message ?? "Не удалось выполнить действие. Данные не изменены."],nil)}
        do {
            switch text(request,"action") {
            case "api": success(try store.request(path:text(request,"path"),method:text(request,"method"),body:object(request,"body")))
            case "copy":
                let value=text(request,"text");try check(value.utf8.count<=2_000_000,"Текст слишком большой")
                NSPasteboard.general.clearContents();NSPasteboard.general.setString(value,forType:.string);success()
            case "export", "exportSettings":
                let settings=text(request,"action")=="exportSettings"
                let data=try JSONSerialization.data(withJSONObject:store.request(path:settings ? "/settings/export":"/export"),options:[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes])
                chooseTransferFile(settings:settings,saving:true) { url in
                    guard let url=url else{success(["saved":false]);return}
                    do{try data.write(to:url,options:.atomic);success(["saved":true])}catch{failure(error)}
                }
            case "import", "importSettings":
                let settings=text(request,"action")=="importSettings"
                chooseTransferFile(settings:settings,saving:false) { url in
                    guard let url=url else{success(null);return}
                    do{
                        let limit=settings ? 64_000:5_000_000
                        let size=(try url.resourceValues(forKeys:[.fileSizeKey])).fileSize ?? 0
                        try check(size<=limit,settings ? "Файл настроек должен быть меньше 64 КБ":"Файл должен быть меньше 5 МБ")
                        let data=try Data(contentsOf:url)
                        try check(data.count<=limit,"Файл слишком большой")
                        guard let b=try JSONSerialization.jsonObject(with:data) as? Object else{try fail("Неверный JSON-файл")}
                        if settings{try Rules.settingsBundle(b)}else{_=try Rules.bundle(b)}
                        success(b)
                    }catch{failure(error)}
                }
            case "dataFolder": NSWorkspace.shared.open(store.fileURL.deletingLastPathComponent());success()
            default:try fail("Операция недоступна",404,"not_found")
            }
        }catch{failure(error)}
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate {
    var window:NSWindow!
    var webView:WKWebView!
    var bridge:DesktopBridge!
    let testing=CommandLine.arguments.contains("--ui-test")
    var testStarted=false
    func applicationDidFinishLaunching(_ notification:Notification){
        do {
            let resources=Bundle.main.resourceURL!
            let assets=resources.appendingPathComponent("web")
            let directory:URL
            if testing{directory=FileManager.default.temporaryDirectory.appendingPathComponent("semestr-ui-"+newID())}
            else{directory=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Semestr")}
            bridge=DesktopBridge(store:try LocalStore(directory:directory),assets:assets,testTransferDirectory:testing ? directory:nil)
            let controller=WKUserContentController()
            controller.addScriptMessageHandler(bridge,contentWorld:.page,name:"semestr")
            controller.addUserScript(WKUserScript(source:"document.addEventListener('DOMContentLoaded',()=>document.documentElement.classList.add('native-app'));",injectionTime:.atDocumentStart,forMainFrameOnly:true))
            let config=WKWebViewConfiguration();config.userContentController=controller
            config.preferences.javaScriptCanOpenWindowsAutomatically=false
            if testing{config.websiteDataStore = .nonPersistent()}
            webView=WKWebView(frame:.zero,configuration:config);webView.navigationDelegate=self;webView.uiDelegate=self
            window=NSWindow(contentRect:NSRect(x:0,y:0,width:1380,height:880),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
            window.title="Семестр";window.minSize=NSSize(width:780,height:600)
            window.contentView=webView;window.center();window.isReleasedWhenClosed=false
            if !testing{window.setFrameAutosaveName("SemestrMainWindow")}
            buildMenus()
            window.makeKeyAndOrderFront(nil)
            if !testing{NSApp.activate(ignoringOtherApps:true)}
            webView.loadFileURL(assets.appendingPathComponent("index.html"),allowingReadAccessTo:assets)
            if testing{DispatchQueue.main.asyncAfter(deadline:.now()+30){self.finishTest(false,"UI test timed out")}}
        }catch {
            if testing{finishTest(false,"Native launch failed: \(error)");return}
            let alert=NSAlert();alert.messageText="Не удалось открыть Семестр";alert.informativeText=(error as? LocalError)?.message ?? error.localizedDescription;alert.alertStyle = .critical;alert.runModal();NSApp.terminate(nil)
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool{true}
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool{window.makeKeyAndOrderFront(nil);return true}
    func buildMenus(){
        let bar=NSMenu();let appItem=NSMenuItem();bar.addItem(appItem)
        let appMenu=NSMenu();appItem.submenu=appMenu
        appMenu.addItem(withTitle:"О программе «Семестр»",action:#selector(NSApplication.orderFrontStandardAboutPanel(_:)),keyEquivalent:"")
        appMenu.addItem(.separator());appMenu.addItem(withTitle:"Скрыть Семестр",action:#selector(NSApplication.hide(_:)),keyEquivalent:"h")
        appMenu.addItem(.separator());appMenu.addItem(withTitle:"Завершить Семестр",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        let file=NSMenu(title:"Файл");let fileItem=NSMenuItem();fileItem.submenu=file;bar.addItem(fileItem)
        let add=NSMenuItem(title:"Новый предмет",action:#selector(newSubject),keyEquivalent:"n");add.target=self;file.addItem(add)
        let export=NSMenuItem(title:"Экспортировать данные…",action:#selector(exportData),keyEquivalent:"e");export.target=self;file.addItem(export)
        file.addItem(.separator());file.addItem(withTitle:"Закрыть окно",action:#selector(NSWindow.performClose(_:)),keyEquivalent:"w")
        let edit=NSMenu(title:"Правка");let editItem=NSMenuItem();editItem.submenu=edit;bar.addItem(editItem)
        for (title,selector,key) in [("Отменить","undo:","z"),("Вырезать","cut:","x"),("Копировать","copy:","c"),("Вставить","paste:","v"),("Выделить всё","selectAll:","a")]{edit.addItem(withTitle:title,action:Selector(selector),keyEquivalent:key)}
        let windowMenu=NSMenu(title:"Окно");let windowItem=NSMenuItem();windowItem.submenu=windowMenu;bar.addItem(windowItem)
        windowMenu.addItem(withTitle:"Свернуть",action:#selector(NSWindow.performMiniaturize(_:)),keyEquivalent:"m")
        windowMenu.addItem(withTitle:"Увеличить",action:#selector(NSWindow.performZoom(_:)),keyEquivalent:"")
        NSApp.mainMenu=bar;NSApp.windowsMenu=windowMenu
    }
    @objc func newSubject(){webView.evaluateJavaScript("window.dispatchEvent(new Event('semestr:new-subject'))",completionHandler:nil)}
    @objc func exportData(){webView.evaluateJavaScript("window.dispatchEvent(new Event('semestr:export'))",completionHandler:nil)}
    func webView(_ webView:WKWebView,decidePolicyFor action:WKNavigationAction,decisionHandler:@escaping(WKNavigationActionPolicy)->Void){
        guard let url=action.request.url else{decisionHandler(.cancel);return}
        if url.isFileURL && url.standardizedFileURL.path.hasPrefix(bridge.assets.standardizedFileURL.path+"/"){decisionHandler(.allow);return}
        if action.navigationType == .linkActivated {openExternal(url)}
        decisionHandler(.cancel)
    }
    func webView(_ webView:WKWebView,createWebViewWith configuration:WKWebViewConfiguration,for action:WKNavigationAction,windowFeatures:WKWindowFeatures)->WKWebView?{
        if let url=action.request.url{openExternal(url)};return nil
    }
    private func openExternal(_ url:URL){if ["http","https"].contains(url.scheme ?? "") && url.user==nil && url.password==nil{NSWorkspace.shared.open(url)}}
    func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!){if testing && !testStarted{testStarted=true;runUITest()}}
    func webView(_ webView:WKWebView,didFailProvisionalNavigation navigation:WKNavigation!,withError error:Error){if testing{finishTest(false,"Loading local UI failed: \(error)")}}
    private func runUITest(){
        let script="""
        const wait = ms => new Promise(resolve => setTimeout(resolve,ms));
        for(let i=0;i<80 && !document.querySelector('h1');i++) await wait(100);
        if(!document.querySelector('h1')) throw new Error('React did not render: '+document.body.innerText+'; HTML: '+document.head.innerHTML);
        const request=async(path,method='GET',body={})=>{
            const reply=await window.webkit.messageHandlers.semestr.postMessage({action:'api',path,method,body});
            if(!reply.ok) throw new Error(reply.message);return reply.data;
        };
        const s=await request('/auth/session');
        if(!s.account || document.body.textContent.includes('С возвращением'))throw new Error('Local profile failed');
        const until=async(test,label)=>{for(let i=0;i<60;i++){if(test())return;await wait(100)}throw new Error(label)};
        const fill=async(element,value)=>{
            if(!element)throw new Error('Input missing');
            const proto=element.tagName==='TEXTAREA'?HTMLTextAreaElement.prototype:HTMLInputElement.prototype;
            Object.getOwnPropertyDescriptor(proto,'value').set.call(element,value);
            element.dispatchEvent(new Event('input',{bubbles:true}));await wait(50);
        };
        const openDebt=async()=>{
            document.querySelector('.add-menu').open=true;
            [...document.querySelectorAll('.add-menu button')].find(b=>b.textContent.includes('Академический долг')).click();
            await until(()=>document.querySelector('#debt-subject-title'),'New debt title field missing');
        };
        await openDebt();
        await fill(document.querySelector('#debt-subject-title'),'Теория вероятностей');
        document.querySelector('dialog [aria-label="Закрыть окно"]').click();
        await until(()=>!document.querySelector('dialog'),'Cancel debt failed');
        if((await request('/records')).items.length!==0)throw new Error('Cancel created an empty subject');
        await openDebt();
        if(document.querySelector('#debt-subject-title').value!=='Теория вероятностей')throw new Error('New debt title draft was lost');
        document.querySelector('dialog .dialog-footer button').click();
        await until(()=>!document.querySelector('dialog'),'Title-only debt save failed');
        let debtsPage=await request('/records');
        const debtSubject=debtsPage.items.find(r=>r.data.kind==='subject'&&r.data.title==='Теория вероятностей');
        const academicDebt=debtsPage.items.find(r=>r.data.kind==='debt');
        if(!debtSubject||!academicDebt||academicDebt.data.subjectId!==debtSubject.id||academicDebt.data.reason!=='difference')throw new Error('Subject/debt pair not persisted');
        await until(()=>document.querySelector('.dossier h2')?.textContent==='Теория вероятностей','New debt subject not selected');
        await openDebt();
        if(document.querySelector('#debt-subject-title').value!=='')throw new Error('Previous subject was prefilled for a new debt');
        await fill(document.querySelector('#debt-subject-title'),'Теория вероятностей');
        await until(()=>document.querySelector('.subject-matches button'),'Existing subject suggestion missing');
        document.querySelector('.subject-matches button').click();
        await until(()=>document.querySelector('#debt-existing-subject')?.value===debtSubject.id,'Existing subject not selected');
        document.querySelector('dialog .dialog-footer button').click();
        await until(()=>!document.querySelector('dialog'),'Existing subject debt failed');
        debtsPage=await request('/records');
        if(debtsPage.items.filter(r=>r.data.kind==='subject').length!==1||debtsPage.items.filter(r=>r.data.kind==='debt').length!==2)throw new Error('Existing subject duplicated');
        window.dispatchEvent(new Event('semestr:new-subject'));
        await until(()=>document.querySelector('dialog[open]'),'Native new subject menu failed');
        await fill(document.querySelector('dialog input'),'Математический анализ');
        document.querySelector('dialog .dialog-footer button').click();
        await until(()=>!document.querySelector('dialog'),'Subject editor did not save');
        let page=await request('/records');
        const record=page.items.find(r=>r.data.title==='Математический анализ');
        if(!record)throw new Error('Subject not persisted');
        [...document.querySelectorAll('nav button')].find(b=>b.textContent.includes('Предметы')).click();
        await until(()=>document.querySelector('h1').textContent.includes('Каждому'),'Subject navigation failed');
        await until(()=>document.querySelector('.full-row'),'Subject row not rendered');
        [...document.querySelectorAll('.full-row')].find(row=>row.textContent.includes('Математический анализ')).click();
        await until(()=>document.querySelector('.dossier h2')?.textContent==='Математический анализ','Subject selection failed');
        const addNote=[...document.querySelectorAll('.dossier button')].find(b=>b.textContent.includes('Добавить заметку'));
        addNote.click();await until(()=>document.querySelector('dialog textarea'),'Note editor failed');
        await fill(document.querySelector('dialog textarea'),'Уточнить требования на консультации.');
        document.querySelector('dialog .dialog-footer button').click();
        await until(()=>!document.querySelector('dialog'),'Note editor did not save');
        page=await request('/records');
        if(!page.items.some(r=>r.data.kind==='note'&&r.data.subjectId===record.id&&r.data.text.includes('консультации')))throw new Error('Note not persisted');
        [...document.querySelectorAll('.sidebar-bottom button')].find(b=>b.textContent.includes('Настройки')).click();
        await until(()=>document.querySelector('.settings'),'Settings did not open');
        if(!document.body.textContent.includes('Данные на этом Mac')||document.body.textContent.includes('Удалить аккаунт'))throw new Error('Desktop settings failed');
        await fill(document.querySelector('.settings input'),'Студент');
        document.querySelector('.settings form button.primary').click();
        await until(()=>document.querySelector('.toast')?.textContent.includes('Профиль сохранён'),'Profile save failed');
        const updated=await request('/auth/session');
        if(updated.account.profile.name!=='Студент'||!updated.account.profile.onboarded)throw new Error('Profile not persisted');
        [...document.querySelectorAll('.theme-options button')].find(b=>b.textContent.includes('Тёмная')).click();
        await until(()=>document.documentElement.dataset.theme==='dark','Dark theme failed');
        const transferButton=label=>[...document.querySelectorAll('.settings-transfer button')].find(b=>b.textContent.includes(label));
        transferButton('Сохранить настройки').click();
        await until(()=>document.querySelector('.toast')?.textContent.includes('Файл настроек сохранён'),'Settings file export failed');
        await fill(document.querySelector('.settings input'),'Получатель');
        document.querySelector('.settings form button.primary').click();
        await until(()=>document.querySelector('.toast')?.textContent.includes('Профиль сохранён'),'Destination profile save failed');
        [...document.querySelectorAll('.theme-options button')].find(b=>b.textContent.includes('Светлая')).click();
        await until(()=>document.documentElement.dataset.theme==='light','Light theme failed');
        const beforeTransfer=await request('/records');
        transferButton('Загрузить настройки').click();
        await until(()=>document.querySelector('.settings-preview'),'Settings file preview failed');
        if(!document.querySelector('.settings-preview').textContent.includes('Студент')||!document.querySelector('.settings-preview').textContent.includes('Тёмная'))throw new Error('Incomplete settings preview');
        document.querySelector('.settings-preview .text-button').click();
        await until(()=>!document.querySelector('.settings-preview'),'Cancel preview failed');
        if((await request('/auth/session')).account.profile.name!=='Получатель'||(await request('/appearance')).theme!=='light')throw new Error('Cancel changed settings');
        transferButton('Загрузить настройки').click();
        await until(()=>document.querySelector('.settings-preview'),'Settings reload failed');
        document.querySelector('.settings-preview button.primary').click();
        await until(()=>!document.querySelector('.settings-preview')&&document.querySelector('.settings input').value==='Студент'&&document.documentElement.dataset.theme==='dark','Settings import did not update profile and appearance');
        const afterTransfer=await request('/records');
        if(beforeTransfer.items.length!==afterTransfer.items.length||beforeTransfer.items.some(r=>!afterTransfer.items.some(after=>after.id===r.id&&after.version===r.version)))throw new Error('Settings import changed study data');
        if((await request('/appearance')).theme!=='dark')throw new Error('Imported theme not persisted');
        [...document.querySelectorAll('.theme-options button')].find(b=>b.textContent.includes('Светлая')).click();
        await until(()=>document.documentElement.dataset.theme==='light','Restoring test theme failed');
        [...document.querySelectorAll('nav button')].find(b=>b.textContent.includes('Долги')).click();
        await until(()=>document.querySelector('h1').textContent.includes('Закрыть'),'Debt navigation failed');
        await openDebt();
        await fill(document.querySelector('#debt-subject-title'),'Основы финансовой грамотности');
        const toast=document.querySelector('.toast .icon-button');if(toast)toast.click();
        await wait(350);
        return {title:document.querySelector('dialog h2').textContent,subjectSaved:true,noteSaved:true,profileSaved:true,themes:true,settingsFileRoundtrip:true,previewCancellation:true,studyDataPreserved:true,titleOnlyDebt:true,debtDraftRestored:true,existingSubjectReused:true,networkResources:performance.getEntriesByType('resource').filter(r=>/^https?:/.test(r.name)).length};
        """
        webView.callAsyncJavaScript(script,arguments:[:],in:nil,in:.page){result in
            switch result {
            case .failure(let error):self.finishTest(false,"UI: \(error)")
            case .success(let value):
                let values=value as? Object ?? [:]
                if number(values,"networkResources") != 0 {self.finishTest(false,"Unexpected network resources");return}
                self.webView.takeSnapshot(with:nil){image,error in
                    if let directory=ProcessInfo.processInfo.environment["SEMESTR_TEST_OUTPUT"]{
                        try? FileManager.default.createDirectory(atPath:directory,withIntermediateDirectories:true)
                        if let image=image,let tiff=image.tiffRepresentation,let bitmap=NSBitmapImageRep(data:tiff),let png=bitmap.representation(using:.png,properties:[:]){try? png.write(to:URL(fileURLWithPath:directory).appendingPathComponent("native-app.png"))}
                    }
                    self.finishTest(error==nil,"Native UI: title-only debt, draft, existing subject, profile and settings transfer passed; zero HTTP resources. \(values)")
                }
            }
        }
    }
    private func finishTest(_ success:Bool,_ message:String){
        print(success ? "PASS: \(message)":"FAIL: \(message)")
        if let directory=bridge?.store.fileURL.deletingLastPathComponent(),directory.lastPathComponent.hasPrefix("semestr-ui-"){try? FileManager.default.removeItem(at:directory)}
        exit(success ? 0:1)
    }
}

func createIcon(_ output:String) throws {
    let size=NSSize(width:1024,height:1024)
    let image=NSImage(size:size)
    image.lockFocus()
    NSColor(calibratedRed:0.10,green:0.24,blue:0.19,alpha:1).setFill()
    NSBezierPath(roundedRect:NSRect(x:38,y:38,width:948,height:948),xRadius:218,yRadius:218).fill()
    let style=NSMutableParagraphStyle();style.alignment = .center
    let letter="С" as NSString
    letter.draw(in:NSRect(x:120,y:148,width:784,height:710),withAttributes:[.font:NSFont(name:"Georgia",size:660) ?? NSFont.systemFont(ofSize:660),.foregroundColor:NSColor(calibratedRed:0.96,green:0.95,blue:0.88,alpha:1),.paragraphStyle:style])
    NSColor(calibratedRed:0.67,green:0.75,blue:0.56,alpha:1).setFill()
    let mark=NSBezierPath(roundedRect:NSRect(x:655,y:212,width:146,height:31),xRadius:15,yRadius:15);mark.fill()
    image.unlockFocus()
    guard let data=image.tiffRepresentation,let bitmap=NSBitmapImageRep(data:data),let png=bitmap.representation(using:.png,properties:[:]) else{try fail("Icon render failed")}
    try png.write(to:URL(fileURLWithPath:output))
}

if CommandLine.arguments.contains("--self-test") {
    do{try runStoreTests();exit(0)}catch{fputs("FAIL: \(error)\n",stderr);exit(1)}
}
if let index=CommandLine.arguments.firstIndex(of:"--make-icon"),CommandLine.arguments.count>index+1{
    do{try createIcon(CommandLine.arguments[index+1]);exit(0)}catch{fputs("Icon failed: \(error)\n",stderr);exit(1)}
}
let app=NSApplication.shared
app.setActivationPolicy(.regular)
let delegate=AppDelegate()
app.delegate=delegate
app.run()
