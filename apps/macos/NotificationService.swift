import AppKit
import UserNotifications

protocol ReminderDelivery:AnyObject {
    func authorization() async -> String
    func requestPermission() async throws -> String
    func pending() async -> [String:String]
    func add(_ reminder:Reminder) async throws
    func remove(_ ids:[String])
    func clearDelivered()
}

final class MacReminderDelivery:NSObject,ReminderDelivery,UNUserNotificationCenterDelegate {
    private let center=UNUserNotificationCenter.current()
    var onOpen:((String)->Void)?
    var shouldPresent:(()->Bool)?
    override init(){super.init();center.delegate=self}
    func authorization() async -> String {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined:return "notDetermined"
        case .denied:return "denied"
        case .authorized:return "authorized"
        case .provisional:return "provisional"
        @unknown default:return "denied"
        }
    }
    func requestPermission() async throws -> String {
        _=try await center.requestAuthorization(options:[.alert,.sound])
        return await authorization()
    }
    func pending() async -> [String:String] {
        let requests=await center.pendingNotificationRequests()
        return Dictionary(uniqueKeysWithValues:requests.filter{$0.identifier.hasPrefix(ReminderPlanner.prefix)}.map{($0.identifier,$0.content.userInfo["signature"] as? String ?? "")})
    }
    func add(_ reminder:Reminder) async throws {
        let content=UNMutableNotificationContent()
        content.title=reminder.title;content.body=reminder.body
        content.sound=reminder.sound ? .default:nil
        content.userInfo=["signature":reminder.signature,"subjectID":reminder.subjectID,"recordID":reminder.recordID]
        var components=CalendarRules.calendar().dateComponents([.year,.month,.day,.hour,.minute,.second],from:reminder.fireAt)
        components.calendar=CalendarRules.calendar();components.timeZone=CalendarRules.utc
        let trigger=UNCalendarNotificationTrigger(dateMatching:components,repeats:false)
        try await center.add(UNNotificationRequest(identifier:reminder.id,content:content,trigger:trigger))
    }
    func remove(_ ids:[String]){center.removePendingNotificationRequests(withIdentifiers:ids)}
    func clearDelivered(){center.removeAllDeliveredNotifications()}
    func userNotificationCenter(_ center:UNUserNotificationCenter,willPresent notification:UNNotification,withCompletionHandler completionHandler:@escaping(UNNotificationPresentationOptions)->Void){
        DispatchQueue.main.async {completionHandler(self.shouldPresent?()==true ? [.banner,.list,.sound]:[])}
    }
    func userNotificationCenter(_ center:UNUserNotificationCenter,didReceive response:UNNotificationResponse,withCompletionHandler completionHandler:@escaping()->Void){
        let subject=response.notification.request.content.userInfo["subjectID"] as? String ?? ""
        DispatchQueue.main.async {if !subject.isEmpty{self.onOpen?(subject)};completionHandler()}
    }
}

/// The same scheduling path is exercised in UI tests, with an isolated delivery queue.
final class TestReminderDelivery:ReminderDelivery {
    var permission="notDetermined"
    var queue=[String:Reminder]()
    var additions=0
    func authorization() async -> String {permission}
    func requestPermission() async throws -> String {permission="authorized";return permission}
    func pending() async -> [String:String] {queue.mapValues(\.signature)}
    func add(_ reminder:Reminder) async throws {queue[reminder.id]=reminder;additions+=1}
    func remove(_ ids:[String]){for id in ids{queue.removeValue(forKey:id)}}
    func clearDelivered(){}
}

/// All reads and queue reconciliation run on the main actor. A second change during
/// an awaited OS operation queues another pass, so stale settings cannot win.
@MainActor final class NotificationService {
    let store:LocalStore
    let delivery:ReminderDelivery
    private var task:Task<Void,Never>?
    private var refreshAgain=false
    private var error=""
    private var coveredUntil:Date?
    private var truncated=false
    init(store:LocalStore,delivery:ReminderDelivery){self.store=store;self.delivery=delivery}
    func refresh(){
        refreshAgain=true
        guard task==nil else{return}
        task=Task {
            while self.refreshAgain {self.refreshAgain=false;await self.reconcile()}
            self.task=nil
        }
    }
    func status() async -> Object {
        refresh();await task?.value
        let permission=await delivery.authorization(),pending=await delivery.pending()
        return ["authorization":permission,"pendingCount":pending.count,"coveredUntil":coveredUntil.map(CalendarRules.iso) as Any? ?? null,"truncated":truncated,"error":error]
    }
    func requestPermission() async throws -> Object {
        _=try await delivery.requestPermission()
        return await status()
    }
    private func reconcile() async {
        do {
            let snapshot=try store.reminderSnapshot()
            let permission=await delivery.authorization()
            let pending=await delivery.pending()
            guard object(snapshot,"notifications")["enabled"] as? Bool==true,["authorized","provisional"].contains(permission) else {
                delivery.remove(Array(pending.keys));delivery.clearDelivered();coveredUntil=nil;truncated=false;error="";return
            }
            let plan=try ReminderPlanner.plan(snapshot)
            let ids=Set(plan.reminders.map(\.id))
            delivery.remove(pending.keys.filter{!ids.contains($0)})
            for reminder in plan.reminders where reminder.fireAt>Date() && pending[reminder.id] != reminder.signature {try await delivery.add(reminder)}
            coveredUntil=plan.coveredUntil;truncated=plan.truncated;error=""
        } catch {
            // Remove potentially obsolete reminders after a failed recalculation.
            delivery.remove(Array((await delivery.pending()).keys));coveredUntil=nil
            self.error=(error as? LocalError)?.message ?? "Не удалось запланировать уведомления. Проверьте разрешение macOS и повторите."
        }
    }
}
