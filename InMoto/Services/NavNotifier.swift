import Foundation
import UserNotifications

/// Notifiche locali degli eventi di navigazione. iOS le rispecchia
/// automaticamente sull'Apple Watch quando l'iPhone è bloccato o a schermo
/// spento (utile in moto, con il telefono in tasca/borsa).
enum NavNotifier {

    /// Delegate per mostrare le notifiche anche con l'app in primo piano.
    private static let foregroundDelegate = ForegroundDelegate()

    /// Da chiamare una volta all'avvio dell'app.
    static func configure() {
        UNUserNotificationCenter.current().delegate = foregroundDelegate
    }

    /// Richiede il permesso (idempotente: se già deciso non mostra nulla).
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Invia una notifica immediata (consegnata anche all'Apple Watch abbinato).
    static func post(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            // trigger nil = consegna immediata
            let request = UNNotificationRequest(identifier: UUID().uuidString,
                                                content: content, trigger: nil)
            center.add(request)
        }
    }

    private final class ForegroundDelegate: NSObject, UNUserNotificationCenterDelegate {
        func userNotificationCenter(_ center: UNUserNotificationCenter,
                                    willPresent notification: UNNotification,
                                    withCompletionHandler completionHandler:
                                    @escaping (UNNotificationPresentationOptions) -> Void) {
            completionHandler([.banner, .sound])
        }
    }
}
