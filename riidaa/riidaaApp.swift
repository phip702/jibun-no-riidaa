//
//  riidaaApp.swift
//  riidaa
//
//  Created by Pierre on 2025/02/12.
//

import SwiftUI
import SwiftData
import Apollo
import UIKit

// MARK: - AppDelegate (orientation lock)

class AppDelegate: NSObject, UIApplicationDelegate {
    /// Set to .landscape while the manga reader is presented; .all otherwise.
    static var orientationLock: UIInterfaceOrientationMask = .all

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        AppDelegate.orientationLock
    }
}

@main
struct riidaaApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    let CoreController = CoreDataManager.shared
    @StateObject var appManager: AppManager = AppManager.shared
    @StateObject var settings: SettingsModel = SettingsModel()
    
    var body: some Scene {
        WindowGroup {
            if appManager.isLoading {
                VStack {
                    ProgressView()
                    Text("Loading dictionaries")
                }
            } else {
                HomeView()
                    .environment(\.managedObjectContext, CoreController.context)
                    .environmentObject(appManager)
                    .environmentObject(settings)
                    .onAppear {
                        Task.detached {
                            await settings.syncWaniKaniInBackground()
                        }
                    }
            }
        }
    }
}
