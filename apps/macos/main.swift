import AppKit
import WebKit
import UniformTypeIdentifiers

@MainActor final class DesktopBridge: NSObject, WKScriptMessageHandlerWithReply {
    let store: LocalStore
    let assets: URL
    var notifications:NotificationService?
    var updates:UpdateService?
    private let testTransferDirectory:URL?
    private var transferPanel:NSSavePanel?
    private var lastTransferDirectory:URL?
    private var transferFiles=[String:URL]()
    private var transferFileOrder=[String]()
    init(store:LocalStore,assets:URL,testTransferDirectory:URL?=nil){self.store=store;self.assets=assets;self.testTransferDirectory=testTransferDirectory}
    private func fileDetails(_ url:URL,size:Int) -> Object {
        let token=newID();transferFiles[token]=url;transferFileOrder.append(token)
        if transferFileOrder.count>50{transferFiles.removeValue(forKey:transferFileOrder.removeFirst())}
        let folder=url.deletingLastPathComponent().path
        let home=FileManager.default.homeDirectoryForCurrentUser.path
        return ["token":token,"name":url.lastPathComponent,"folder":folder.hasPrefix(home+"/") ? "~"+folder.dropFirst(home.count):folder,"size":size]
    }
    private func chooseTransferFile(settings:Bool,saving:Bool,window:NSWindow?,completion:@escaping(URL?)->Void){
        // UI tests use actual files in their own temporary directory, bypassing only the picker.
        if let directory=testTransferDirectory {completion(directory.appendingPathComponent(settings ? "settings.json":"study-data.json"));return}
        let panel:NSSavePanel
        if saving {
            panel=NSSavePanel();panel.canCreateDirectories=true
            panel.nameFieldStringValue="Семестр\(settings ? " — настройки":"") — \(CalendarRules.dateString(Date())).json"
            panel.title=settings ? "Сохранить настройки Семестра":"Сохранить данные Семестра"
            panel.prompt="Сохранить файл"
            panel.message="Выберите папку для файла. После сохранения его можно показать в Finder."
        }else{
            let open=NSOpenPanel();open.allowsMultipleSelection=false;open.canChooseDirectories=false;open.canChooseFiles=true;open.resolvesAliases=true
            open.title=settings ? "Выбрать файл настроек":"Выбрать файл учебных данных"
            open.prompt="Выбрать файл"
            open.message="Выберите JSON-файл, сохранённый в «Семестре». Перед импортом покажем его содержимое."
            panel=open
        }
        panel.allowedContentTypes=[.json];panel.allowsOtherFileTypes=false;panel.isExtensionHidden=false
        panel.directoryURL=lastTransferDirectory ?? FileManager.default.urls(for:.downloadsDirectory,in:.userDomainMask).first
        transferPanel=panel
        let finished:(NSApplication.ModalResponse)->Void={ [self] response in
            let url=response == .OK ? panel.url:nil
            if let url=url{lastTransferDirectory=url.deletingLastPathComponent()}
            transferPanel=nil;completion(url)
        }
        if let window=window{window.makeKeyAndOrderFront(nil);panel.beginSheetModal(for:window,completionHandler:finished)}else{panel.begin(completionHandler:finished)}
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
        guard message.frameInfo.isMainFrame, let source=message.frameInfo.request.url,source.isFileURL,source.standardizedFileURL.path.hasPrefix(assets.standardizedFileURL.path+"/"),let request=message.body as? Object else {replyHandler(nil,"Недопустимый источник запроса");return}
        func success(_ result:Any = NSNull()){replyHandler(["ok":true,"data":result],nil)}
        func failure(_ error:Error){let e=error as? LocalError;replyHandler(["ok":false,"status":e?.status ?? 500,"code":e?.code ?? "storage","message":e?.message ?? "Не удалось выполнить действие. Данные не изменены."],nil)}
        do {
            switch text(request,"action") {
            case "updateStatus":
                guard let updates=updates else{try fail("Обновления недоступны")};success(updates.status())
            case "updatePreferences":
                guard let updates=updates,let enabled=request["automatic"] as? Bool else{try fail("Неверная настройка обновлений")}
                try updates.setAutomatic(enabled);success(updates.status());if enabled{updates.refreshIfDue()}
            case "updateCheck", "updateDownload":
                guard let updates=updates else{try fail("Обновления недоступны")}
                Task { @MainActor in
                    if text(request,"action")=="updateCheck" {await updates.checkForUpdates(force:true)}else{await updates.downloadUpdate()}
                    success(updates.status())
                }
            case "api":
                let result=try store.request(path:text(request,"path"),method:text(request,"method"),body:object(request,"body"))
                if text(request,"method") != "GET" {notifications?.refresh()}
                success(result)
            case "notificationStatus", "notificationPermission":
                guard let notifications=notifications else{try fail("Уведомления недоступны")}
                Task { @MainActor in
                    do {success(try await (text(request,"action")=="notificationPermission" ? notifications.requestPermission():notifications.status()))}
                    catch {failure(LocalError(status:500,code:"notifications",message:"Не удалось запросить разрешение macOS. Откройте системные настройки уведомлений."))}
                }
            case "notificationSystemSettings":
                if testTransferDirectory==nil {NSWorkspace.shared.open(URL(fileURLWithPath:"/System/Applications/System Settings.app"))}
                success()
            case "copy":
                let value=text(request,"text");try check(value.utf8.count<=2_000_000,"Текст слишком большой")
                NSPasteboard.general.clearContents();NSPasteboard.general.setString(value,forType:.string);success()
            case "export", "exportSettings":
                try check(transferPanel==nil,"Сначала завершите выбор файла в открытом окне.")
                let settings=text(request,"action")=="exportSettings"
                let data=try JSONSerialization.data(withJSONObject:store.request(path:settings ? "/settings/export":"/export"),options:[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes])
                chooseTransferFile(settings:settings,saving:true,window:message.webView?.window) { [self] url in
                    guard let url=url else{success(["saved":false]);return}
                    do{try data.write(to:url,options:.atomic);success(["saved":true,"file":fileDetails(url,size:data.count)])}
                    catch{failure(LocalError(status:500,code:"file_write",message:"Не удалось сохранить файл. Выберите доступную папку и проверьте свободное место."))}
                }
            case "revealTransferFile":
                guard let url=transferFiles[text(request,"token")] else{try fail("Этот файл больше недоступен. Сохраните его заново.")}
                try check(FileManager.default.fileExists(atPath:url.path),"Файл перемещён или удалён. Сохраните его заново.")
                if testTransferDirectory==nil{NSWorkspace.shared.activateFileViewerSelecting([url])}
                success(["revealed":true,"name":url.lastPathComponent])
            case "import", "importSettings":
                try check(transferPanel==nil,"Сначала завершите выбор файла в открытом окне.")
                let settings=text(request,"action")=="importSettings"
                chooseTransferFile(settings:settings,saving:false,window:message.webView?.window) { [self] url in
                    guard let url=url else{success(null);return}
                    do{
                        let limit=settings ? 64_000:5_000_000
                        let size=(try url.resourceValues(forKeys:[.fileSizeKey])).fileSize ?? 0
                        try check(size<=limit,settings ? "Файл настроек должен быть меньше 64 КБ":"Файл должен быть меньше 5 МБ")
                        let data=try Data(contentsOf:url)
                        try check(data.count<=limit,"Файл слишком большой")
                        guard let b=(try? JSONSerialization.jsonObject(with:data)) as? Object else{try fail("Не удалось прочитать JSON. Выберите файл, сохранённый в «Семестре».")}
                        if settings && b["records"] != nil{try fail("Это файл учебных данных. Выберите его в разделе «Ваши данные — с вами».")}
                        if !settings && text(b,"format")=="semestr-settings"{try fail("Это файл настроек. Выберите его в разделе «Перенос настроек».")}
                        if settings{try Rules.settingsBundle(b)}else{_=try Rules.bundle(b)}
                        success(["bundle":b,"file":fileDetails(url,size:data.count)])
                    }catch{failure(error)}
                }
            case "dataFolder": NSWorkspace.shared.open(store.fileURL.deletingLastPathComponent());success()
            default:try fail("Операция недоступна",404,"not_found")
            }
        }catch{failure(error)}
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate {
    var window:NSWindow!
    var webView:WKWebView!
    var bridge:DesktopBridge!
    let testing=CommandLine.arguments.contains("--ui-test")
    var testStarted=false
    var notificationService:NotificationService?
    var updateService:UpdateService?
    var reminderTimer:Timer?
    var pendingSubjectID:String?
    func applicationDidFinishLaunching(_ notification:Notification){
        do {
            let resources=Bundle.main.resourceURL!
            let assets=resources.appendingPathComponent("web")
            let directory:URL
            if testing{directory=FileManager.default.temporaryDirectory.appendingPathComponent("semestr-ui-"+newID())}
            else{directory=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Semestr")}
            bridge=DesktopBridge(store:try LocalStore(directory:directory),assets:assets,testTransferDirectory:testing ? directory:nil)
            let updateDownloads=testing ? directory.appendingPathComponent("updates"):FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask)[0].appendingPathComponent("Semestr/Updates")
            let updates=UpdateService(directory:directory,downloads:updateDownloads,currentVersion:Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "0.0.0",transport:testing ? TestUpdateTransport():GitHubUpdateTransport(),openInstaller:{ [weak self] url in self?.testing==true ? true:NSWorkspace.shared.open(url) })
            updateService=updates;bridge.updates=updates
            updates.onChange={ [weak self] in self?.webView?.evaluateJavaScript("window.dispatchEvent(new Event('semestr:update-status'))",completionHandler:nil) }
            let delivery:ReminderDelivery
            if testing {delivery=TestReminderDelivery()}
            else {
                let native=MacReminderDelivery()
                native.onOpen={ [weak self] id in self?.showReminderSubject(id) }
                native.shouldPresent={ [weak self] in (try? self?.bridge.store.reminderSnapshot()).map{object($0,"notifications")["enabled"] as? Bool==true} ?? false }
                delivery=native
            }
            let notifications=NotificationService(store:bridge.store,delivery:delivery)
            notificationService=notifications;bridge.notifications=notifications
            notifications.refresh()
            reminderTimer=Timer.scheduledTimer(withTimeInterval:60,repeats:true){ [weak self] _ in Task { @MainActor in self?.notificationService?.refresh();self?.updateService?.refreshIfDue() } }
            NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(refreshReminders),name:NSWorkspace.didWakeNotification,object:nil)
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
            NSApp.activate(ignoringOtherApps:true)
            webView.loadFileURL(assets.appendingPathComponent("index.html"),allowingReadAccessTo:assets)
            updates.refreshIfDue()
            if testing{DispatchQueue.main.asyncAfter(deadline:.now()+120){
                self.webView.evaluateJavaScript("window.semestrTestStage || 'launch'"){value,_ in self.finishTest(false,"UI test timed out at \(value ?? "unknown"); updates: \(updates.status())")}
            }}
        }catch {
            if testing{finishTest(false,"Native launch failed: \(error)");return}
            let alert=NSAlert();alert.messageText="Не удалось открыть Семестр";alert.informativeText=(error as? LocalError)?.message ?? error.localizedDescription;alert.alertStyle = .critical;alert.runModal();NSApp.terminate(nil)
        }
    }
    @objc func refreshReminders(){notificationService?.refresh();updateService?.refreshIfDue()}
    func applicationDidBecomeActive(_ notification:Notification){notificationService?.refresh();updateService?.refreshIfDue()}
    func showReminderSubject(_ id:String){
        pendingSubjectID=id
        window?.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
        if webView?.isLoading==false {openReminderSubject()}
    }
    private func openReminderSubject(){
        guard let id=pendingSubjectID,let data=try? encoded(id),let value=String(data:data,encoding:.utf8) else{return}
        webView.evaluateJavaScript("window.semestrPendingSubject="+value+";window.dispatchEvent(new CustomEvent('semestr:show-subject',{detail:"+value+"}))",completionHandler:nil)
        pendingSubjectID=nil
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool{true}
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool{window.makeKeyAndOrderFront(nil);return true}
    func buildMenus(){
        let bar=NSMenu();let appItem=NSMenuItem();bar.addItem(appItem)
        let appMenu=NSMenu();appItem.submenu=appMenu
        appMenu.addItem(withTitle:"О программе «Семестр»",action:#selector(NSApplication.orderFrontStandardAboutPanel(_:)),keyEquivalent:"")
        let updateItem=NSMenuItem(title:"Проверить обновление…",action:#selector(checkUpdates),keyEquivalent:"");updateItem.target=self;appMenu.addItem(updateItem)
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
    @objc func checkUpdates(){window.makeKeyAndOrderFront(nil);webView.evaluateJavaScript("window.dispatchEvent(new Event('semestr:check-updates'))",completionHandler:nil)}
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
    func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!){openReminderSubject();if testing && !testStarted{testStarted=true;runUITest()}}
    func webView(_ webView:WKWebView,didFailProvisionalNavigation navigation:WKNavigation!,withError error:Error){if testing{finishTest(false,"Loading local UI failed: \(error)")}}
    private func runUITest(){
        let script="""
        window.semestrTestStage='start';
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
        window.semestrTestStage='debt';
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
        window.semestrTestStage='profile';
        await fill(document.querySelector('.settings form input'),'Студент');
        document.querySelector('.settings form button.primary').click();
        await until(()=>document.querySelector('.toast')?.textContent.includes('Профиль сохранён'),'Profile save failed');
        const updated=await request('/auth/session');
        if(updated.account.profile.name!=='Студент'||!updated.account.profile.onboarded)throw new Error('Profile not persisted');
        [...document.querySelectorAll('.theme-options button')].find(b=>b.textContent.includes('Тёмная')).click();
        await until(()=>document.documentElement.dataset.theme==='dark','Dark theme failed');
        const transferButton=label=>[...document.querySelectorAll('.settings-transfer button')].find(b=>b.textContent.includes(label));
        transferButton('Сохранить настройки').click();
        await until(()=>document.querySelector('.saved-file-notice')?.textContent.includes('Файл настроек сохранён'),'Settings file export failed');
        if(!document.querySelector('.saved-file-notice').textContent.includes('settings.json')||!document.querySelector('.reveal-file'))throw new Error('Saved settings receipt missing');
        document.querySelector('.reveal-file').click();await wait(100);
        if(document.querySelector('.saved-file-notice .error'))throw new Error('Finder action failed');
        await fill(document.querySelector('.settings form input'),'Получатель');
        document.querySelector('.settings form button.primary').click();
        await until(()=>document.querySelector('.toast')?.textContent.includes('Профиль сохранён'),'Destination profile save failed');
        [...document.querySelectorAll('.theme-options button')].find(b=>b.textContent.includes('Светлая')).click();
        await until(()=>document.documentElement.dataset.theme==='light','Light theme failed');
        const beforeTransfer=await request('/records');
        document.querySelector('.choose-settings-file').click();
        await until(()=>document.querySelector('.settings-preview'),'Settings file preview failed');
        if(!document.querySelector('.settings-preview').textContent.includes('Студент')||!document.querySelector('.settings-preview').textContent.includes('Тёмная'))throw new Error('Incomplete settings preview');
        document.querySelector('.settings-preview .text-button').click();
        await until(()=>!document.querySelector('.settings-preview'),'Cancel preview failed');
        if((await request('/auth/session')).account.profile.name!=='Получатель'||(await request('/appearance')).theme!=='light')throw new Error('Cancel changed settings');
        document.querySelector('.choose-settings-file').click();
        await until(()=>document.querySelector('.settings-preview'),'Settings reload failed');
        document.querySelector('.settings-preview button.primary').click();
        await until(()=>!document.querySelector('.settings-preview')&&document.querySelector('.settings form input').value==='Студент'&&document.documentElement.dataset.theme==='dark','Settings import did not update profile and appearance');
        const afterTransfer=await request('/records');
        if(beforeTransfer.items.length!==afterTransfer.items.length||beforeTransfer.items.some(r=>!afterTransfer.items.some(after=>after.id===r.id&&after.version===r.version)))throw new Error('Settings import changed study data');
        if((await request('/appearance')).theme!=='dark')throw new Error('Imported theme not persisted');
        const themeLabel=testTheme==='light'?'Светлая':'Тёмная';
        [...document.querySelectorAll('.theme-options button')].find(b=>b.textContent.includes(themeLabel)).click();
        await until(()=>document.documentElement.dataset.theme===testTheme,'Test theme failed');
        [...document.querySelectorAll('nav button')].find(b=>b.textContent.includes('Предметы')).click();
        await until(()=>document.querySelector('.full-row'),'Subject list missing');
        [...document.querySelectorAll('.full-row')].find(row=>row.textContent.includes('Математический анализ')).click();
        await until(()=>document.querySelector('.dossier h2')?.textContent==='Математический анализ','Context selection failed');
        const requirements=()=>document.querySelector('.requirements-card');
        if(!requirements()?.classList.contains('is-empty')||getComputedStyle(requirements()).backgroundImage!=='none')throw new Error('Empty requirements are not readable');
        requirements().click();
        await until(()=>document.querySelector('dialog textarea'),'Requirements editor missing');
        const conditions=`Сдать две практические работы.\nЗащитить проект на консультации.\nФормат: короткая презентация и ответы на вопросы.`;
        const requirementsArea=[...document.querySelectorAll('dialog label')].find(l=>l.textContent.includes('Условия сдачи')).querySelector('textarea');
        await fill(requirementsArea,conditions);
        document.querySelector('dialog .dialog-footer button').click();
        await until(()=>!document.querySelector('dialog')&&requirements()?.textContent.includes('две практические'),'Requirements save failed');
        if(requirements().querySelector('.requirements-text').textContent!==conditions||getComputedStyle(requirements().querySelector('.requirements-text')).whiteSpace!=='pre-wrap')throw new Error('Requirements line breaks lost');
        const openLesson=async()=>{
            document.querySelector('.schedule-detail [aria-label="Добавить занятие"]').click();
            await until(()=>document.querySelectorAll('dialog .time-field').length===2,'Time fields missing');
        };
        await openLesson();
        const startTime=document.querySelector('dialog .time-field input');
        const endTime=document.querySelectorAll('dialog .time-field input')[1];
        const clickTime=async element=>{element.focus();element.click();await wait(30)};
        const selectedPart=()=>document.querySelector('.time-segments button[aria-pressed=true]').textContent;
        await clickTime(startTime);
        if(startTime.selectionStart!==0||startTime.selectionEnd!==2||selectedPart()!=='Часы')throw new Error('First time click did not select hours');
        await clickTime(startTime);
        if(startTime.selectionStart!==3||startTime.selectionEnd!==5||selectedPart()!=='Минуты')throw new Error('Repeated time click did not select minutes');
        await clickTime(startTime);
        if(startTime.selectionStart!==0||selectedPart()!=='Часы')throw new Error('Third click did not select hours');
        const key=async(element,key,extra={})=>{element.dispatchEvent(new KeyboardEvent('keydown',{key,bubbles:true,cancelable:true,...extra}));await wait(30)};
        for(const digit of '1750')await key(startTime,digit);
        if(startTime.value!=='17:50'||selectedPart()!=='Минуты')throw new Error('Four-digit time entry failed: '+startTime.value);
        await key(startTime,'ArrowUp');
        if(startTime.value!=='17:51')throw new Error('Minute adjustment failed');
        await key(startTime,'ArrowDown');
        await key(startTime,'ArrowLeft');
        await key(startTime,'Tab');
        if(startTime.selectionStart!==3)throw new Error('Keyboard segment navigation failed');
        await key(startTime,'Tab',{shiftKey:true});
        if(startTime.selectionStart!==0)throw new Error('Reverse keyboard segment navigation failed');
        const paste=async(element,value)=>{
            const clipboardData=new DataTransfer();clipboardData.setData('text/plain',value);
            element.dispatchEvent(new ClipboardEvent('paste',{bubbles:true,cancelable:true,clipboardData}));await wait(30);
        };
        await paste(endTime,'24:70');
        if(endTime.checkValidity()||endTime.value!=='10:30')throw new Error('Invalid pasted time was accepted');
        await paste(endTime,'19:20');
        if(!endTime.checkValidity()||endTime.value!=='19:20')throw new Error('Valid pasted time was rejected');
        const today=new Intl.DateTimeFormat('en-CA',{timeZone:s.account.profile.timezone,year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
        const weekday=new Date(today+'T12:00:00').getDay()||7;
        const weekdayField=[...document.querySelectorAll('dialog label')].find(l=>l.textContent.includes('День недели')).querySelector('select');
        weekdayField.value=String(weekday);weekdayField.dispatchEvent(new Event('change',{bubbles:true}));
        await wait(50);
        document.querySelector('dialog .dialog-footer button').click();
        await until(()=>!document.querySelector('dialog'),'Lesson save failed');
        page=await request('/records');
        const lesson=page.items.find(r=>r.data.kind==='lesson');
        if(!lesson||lesson.data.startTime!=='17:50'||lesson.data.endTime!=='19:20')throw new Error('Edited lesson times not persisted');
        // Fixtures are private to this test's temporary database.
        const day=new Date(today+'T12:00:00');day.setDate(day.getDate()-7);
        const from=[day.getFullYear(),String(day.getMonth()+1).padStart(2,'0'),String(day.getDate()).padStart(2,'0')].join('-');
        for(const [type,startTime,endTime,lessonDay,room] of [['lecture','09:00','10:30',1,'Аудитория 204'],['practice','11:00','12:30',2,'Разбор задач'],['lab','10:00','11:30',4,'Лаборатория 3'],['lecture','11:45','13:15',2,'Пересечение']]){
            await request('/records','POST',{data:{...lesson.data,type,startTime,endTime,weekday:lessonDay,validFrom:from,room}});
        }
        document.querySelector('.toolbar .refresh').click();
        [...document.querySelectorAll('nav button')].find(b=>b.textContent.includes('Неделя')).click();
        await until(()=>document.querySelector('.timeline-event.lesson-lecture')&&document.querySelector('.timeline-event.lesson-practice')&&document.querySelector('.timeline-event.lesson-lab'),'Calendar lesson type markers missing');
        const practice=document.querySelector('.timeline-event.lesson-practice');
        const lecture=document.querySelector('.timeline-event.lesson-lecture');
        if(!practice.querySelector('.lesson-badge')?.title.includes('Практика')||!lecture.querySelector('.lesson-badge')?.title.includes('Лекция'))throw new Error('Calendar lesson labels missing');
        if(getComputedStyle(practice).backgroundColor===getComputedStyle(lecture).backgroundColor||parseFloat(getComputedStyle(practice).borderLeftWidth)<=parseFloat(getComputedStyle(lecture).borderLeftWidth))throw new Error('Practice is not visually emphasized');
        if(!document.querySelector('.timeline-event.overlap .lesson-badge')||!document.querySelector('.day-lesson-marks .lesson-practice'))throw new Error('Conflict or date-strip type marker missing');
        const native=async(action,parameters={})=>{
            const reply=await window.webkit.messageHandlers.semestr.postMessage({action,...parameters});
            if(!reply.ok)throw new Error(reply.message);return reply.data;
        };
        await request('/records','POST',{data:{kind:'subject',title:'Язык',assessment:'credit'}});
        await request('/records','POST',{data:{kind:'subject',title:'Экзамен по алгебре',assessment:'exam'}});
        await request('/records','POST',{data:{kind:'task',subjectId:record.id,title:'Проект к дедлайну',deadline:new Date(Date.now()+3*86400000).toISOString()}});
        document.querySelector('.toolbar .refresh').click();
        [...document.querySelectorAll('nav button')].find(b=>b.textContent.includes('Предметы')).click();
        await until(()=>document.querySelectorAll('.full-row').length===3,'Regular subject list or sorting fixtures missing');
        if(!document.querySelector('.full-row').textContent.includes('Экзамен по алгебре'))throw new Error('Exam subjects are not first');
        [...document.querySelectorAll('.sidebar-bottom button')].find(b=>b.textContent.includes('Настройки')).click();
        await until(()=>document.querySelector('#notification-enabled'),'Notification settings missing');
        if(document.querySelector('#notification-enabled').checked)throw new Error('Notifications must be opt-in');
        document.querySelector('#notification-enabled').click();
        document.querySelector('#notification-sound').click();
        document.querySelector('.notification-settings button.primary').click();
        await until(()=>document.querySelector('.toast')?.textContent.includes('Настройки уведомлений сохранены'),'Notification settings save failed');
        const prefs=await request('/notifications');
        if(!prefs.enabled||prefs.sound||prefs.lessonMinutes!==5||prefs.lessonTypes.join(',')!=='practice'||prefs.deadlineMinutes.join(',')!=='60,1440')throw new Error('Notification preferences not persisted');
        const enabledStatus=await native('notificationStatus');
        if(enabledStatus.authorization!=='authorized'||enabledStatus.pendingCount<2)throw new Error('Notifications not scheduled after enabling');
        const file=await request('/settings/export');
        if(!file.notifications.enabled)throw new Error('Notifications missing from settings transfer');
        document.querySelector('#notification-enabled').click();
        document.querySelector('.notification-settings button.primary').click();
        await until(()=>document.querySelector('.toast')?.textContent.includes('Уведомления отключены'),'Notification disable failed');
        if((await native('notificationStatus')).pendingCount!==0)throw new Error('Disable left pending notifications');
        await request('/settings/import','POST',await request('/settings/preview','POST',file));
        document.querySelector('.toolbar .refresh').click();
        await until(()=>document.querySelector('#notification-enabled')?.checked,'Imported notification preferences did not update UI');
        if((await native('notificationStatus')).pendingCount<2)throw new Error('Import did not restore reminder schedule');
        window.semestrTestStage='updates loaded';
        await until(()=>document.querySelector('.update-settings .update-check'),'Update settings missing');
        if(!document.querySelector('#update-automatic').checked)throw new Error('Daily update check default missing');
        if((await native('updateStatus')).availableVersion!=='0.6.0')throw new Error('Available update not exposed');
        window.semestrTestStage='updates automatic';
        document.querySelector('#update-automatic').click();
        await until(()=>!document.querySelector('#update-automatic').checked&&!document.querySelector('.update-check').disabled,'Update preference did not save');
        if((await native('updateStatus')).automatic)throw new Error('Daily check preference not persisted');
        window.semestrTestStage='updates check';
        document.querySelector('.update-check').click();await wait(100);
        await until(()=>!document.querySelector('.update-check').disabled,'Manual update check did not finish');
        window.semestrTestStage='updates records';
        const canonical=value=>Array.isArray(value)?value.map(canonical):value&&typeof value==='object'?Object.fromEntries(Object.keys(value).sort().map(key=>[key,canonical(value[key])])):value;
        const studySnapshot=async()=>JSON.stringify(canonical((await request('/records')).items.sort((a,b)=>a.id.localeCompare(b.id))));
        const studyBeforeUpdate=await studySnapshot();
        window.semestrTestStage='updates download';
        document.querySelector('.update-download').click();
        try {await until(()=>document.querySelector('.update-download')?.textContent.includes('Открыть установщик'),'Verified installer did not open')}
        catch(e){throw new Error(e.message+': '+JSON.stringify(await native('updateStatus')))}
        window.semestrTestStage='updates ready';
        if(!(await native('updateStatus')).installerReady)throw new Error('Installer ready state missing');
        if(studyBeforeUpdate!==await studySnapshot())throw new Error('Update modified study data');
        document.querySelector('#update-automatic').click();
        await until(()=>document.querySelector('#update-automatic').checked&&!document.querySelector('.update-check').disabled,'Daily update checks not restored');
        window.semestrTestStage='updates menu';
        window.dispatchEvent(new Event('semestr:check-updates'));await wait(100);
        await until(()=>!document.querySelector('.update-check').disabled,'Native update menu failed');
        window.semestrTestStage='file transfers';
        const exportButton=document.querySelector('.export-data');
        exportButton.click();
        await until(()=>document.querySelector('.saved-file-notice')?.textContent.includes('study-data.json'),'Study export receipt missing');
        if(!document.querySelector('.saved-file-notice').textContent.includes('Показать в Finder'))throw new Error('Finder button missing');
        const savedFile=await native('export');
        if(!savedFile.saved||savedFile.file.name!=='study-data.json'||savedFile.file.size<=0)throw new Error('Export file metadata missing');
        if(!(await native('revealTransferFile',{token:savedFile.file.token})).revealed)throw new Error('Known file not revealable');
        let unknownRejected=false;try{await native('revealTransferFile',{token:'/etc/passwd'})}catch{unknownRejected=true}
        if(!unknownRejected)throw new Error('Arbitrary Finder path accepted');
        const importedFile=await native('import');
        if(importedFile.file.name!=='study-data.json'||importedFile.bundle.records.length!==(await request('/records')).items.length)throw new Error('Exported study file did not roundtrip');
        const originalData=await studySnapshot();
        document.querySelector('.choose-data-file').click();
        await until(()=>document.querySelector('.data-preview'),'Study file preview missing');
        if(!document.querySelector('.data-preview').textContent.includes('study-data.json'))throw new Error('Selected filename missing');
        const mode=document.querySelector('.data-preview select');mode.value='replace';mode.dispatchEvent(new Event('change',{bubbles:true}));await wait(100);
        if(!document.querySelector('.data-preview button.primary').disabled)throw new Error('Replace does not require confirmation');
        document.querySelector('.data-preview .text-button').click();
        await until(()=>!document.querySelector('.data-preview'),'Import cancellation failed');
        if(originalData!==await studySnapshot())throw new Error('Preview or cancellation modified records');
        document.querySelector('.choose-data-file').click();
        await until(()=>document.querySelector('.data-preview'),'File reselection failed');
        if(document.querySelector('.data-preview select').value!=='add')throw new Error('Reselection must default to adding');
        document.querySelector('.data-preview button.primary').click();
        await until(()=>!document.querySelector('.data-preview')&&document.querySelector('.toast')?.textContent.includes('Данные импортированы'),'Study file import failed');
        if((await request('/records')).items.length!==importedFile.bundle.records.length*2)throw new Error('Study records not imported');
        window.dispatchEvent(new Event('semestr:export'));
        await until(()=>document.querySelector('.saved-file-notice')?.textContent.includes('study-data.json'),'Native export menu receipt missing');
        const scrollSection=selector=>{const area=document.querySelector('.workspace');const section=document.querySelector(selector);area.scrollTop+=section.getBoundingClientRect().top-area.getBoundingClientRect().top-80};
        if(testView==='transfer'){
            document.querySelector('.choose-data-file').click();
            await until(()=>document.querySelector('.data-preview'),'Transfer screenshot preview missing');
            if(document.querySelector('.data-transfer input[type=file]'))throw new Error('Duplicate browser file picker in native app');
            scrollSection('.data-transfer');
        }else if(testView==='updates'){
            scrollSection('.update-settings');
        }else if(testView!=='notifications'){
            [...document.querySelectorAll('nav button')].find(b=>b.textContent.includes('Неделя')).click();
            await until(()=>document.querySelector('.time-grid'),'Calendar not restored');
        }else{
            scrollSection('.notification-settings');
        }
        const toast=document.querySelector('.toast .icon-button');if(toast)toast.click();
        window.semestrTestStage='snapshot';
        if(testView==='time'){
            await openLesson();
            const field=document.querySelector('dialog .time-field input');
            await clickTime(field);await clickTime(field);
        }
        await wait(350);
        return {subjectSaved:true,noteSaved:true,profileSaved:true,themes:true,settingsFileRoundtrip:true,previewCancellation:true,studyDataPreserved:true,titleOnlyDebt:true,debtDraftRestored:true,existingSubjectReused:true,requirements:true,timeClickToggle:true,timeKeyboard:true,timePasteValidation:true,lessonTimesPersisted:true,calendarTypes:true,practiceEmphasis:true,examsFirst:true,notifications:true,notificationDisable:true,notificationSettingsTransfer:true,theme:testTheme,updates:true,updatePreference:true,updateDownload:true,exportReceipt:true,finderReveal:true,studyFileRoundtrip:true,importPreview:true,importCancellation:true,networkResources:performance.getEntriesByType('resource').filter(r=>/^https?:/.test(r.name)).length};
        """
        webView.callAsyncJavaScript(script,arguments:["testTheme":ProcessInfo.processInfo.environment["SEMESTR_TEST_THEME"] ?? "dark","testView":ProcessInfo.processInfo.environment["SEMESTR_TEST_VIEW"] ?? "calendar"],in:nil,in:.page){result in
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
                    self.finishTest(error==nil,"Native UI: study data, settings transfer, readable requirements, time input, calendar types, exam order, notifications, updates and file transfers passed; zero HTTP resources. \(values)")
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

if CommandLine.arguments.contains("--update-self-test") {
    Task { @MainActor in
        do{try await runUpdateTests();exit(0)}catch{fputs("FAIL: \(error)\n",stderr);exit(1)}
    }
    RunLoop.main.run()
}
if CommandLine.arguments.contains("--update-check") || CommandLine.arguments.contains("--update-download-check") {
    Task { @MainActor in
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("semestr-update-check-"+newID())
        defer{try? FileManager.default.removeItem(at:directory)}
        let download=CommandLine.arguments.contains("--update-download-check")
        let service=UpdateService(directory:directory,downloads:directory,currentVersion:download ? "0.0.0":Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "0.0.0",transport:GitHubUpdateTransport(),openInstaller:{_ in download})
        await service.checkForUpdates(force:true)
        if download {await service.downloadUpdate()}
        let status=service.status()
        if let data=try? encoded(status),let json=String(data:data,encoding:.utf8){print(json)}
        let success=text(status,"error").isEmpty && (!download || status["installerReady"] as? Bool==true)
        try? FileManager.default.removeItem(at:directory)
        exit(success ? 0:1)
    }
    RunLoop.main.run()
}
if CommandLine.arguments.contains("--notification-self-test") {
    Task { @MainActor in
        do{try await runDeliveryTests();exit(0)}catch{fputs("FAIL: \(error)\n",stderr);exit(1)}
    }
    RunLoop.main.run()
}
if CommandLine.arguments.contains("--notification-status") {
    Task { @MainActor in
        let delivery=MacReminderDelivery()
        print("Notification authorization: \(await delivery.authorization()); pending: \(await delivery.pending().count)")
        exit(0)
    }
    RunLoop.main.run()
}
if CommandLine.arguments.contains("--self-test") {
    do{try runStoreTests();try runReminderTests();exit(0)}catch{fputs("FAIL: \(error)\n",stderr);exit(1)}
}
if let index=CommandLine.arguments.firstIndex(of:"--make-icon"),CommandLine.arguments.count>index+1{
    do{try createIcon(CommandLine.arguments[index+1]);exit(0)}catch{fputs("Icon failed: \(error)\n",stderr);exit(1)}
}
let app=NSApplication.shared
app.setActivationPolicy(.regular)
let delegate=MainActor.assumeIsolated { AppDelegate() }
app.delegate=delegate
app.run()
