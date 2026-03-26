//
//  tohata_ios_02App.swift
//  tohata_ios_02
//
//  Created by daichi0208 on 2025/11/13.
//

import SwiftUI
import UserNotifications

@main
struct tohata_ios_02App: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    requestNotificationPermission()
                }
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("[Notification] 通知権限リクエストエラー: \(error.localizedDescription)")
            }
        }
    }
}
