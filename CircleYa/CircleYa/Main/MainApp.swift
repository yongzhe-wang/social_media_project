import SwiftUI
import FirebaseCore
import FirebaseAuth

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FirebaseApp.configure()
        return true
    }
}

@main
struct CircleYaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    @State private var isLoggedIn = false
    @State private var isFirebaseReady = false
    @State private var authListener: AuthStateDidChangeListenerHandle?

    var body: some Scene {
        WindowGroup {
            contentView
                .onAppear(perform: setupAutoLogin)
                .onDisappear { detachAuthListener() }
                .onReceive(NotificationCenter.default.publisher(for: .userDidSignOut)) { _ in
                    print("🚪 Received sign-out notification")
                    isLoggedIn = false
                }
        }
    }

    // MARK: - Views
    @ViewBuilder
    private var contentView: some View {
        if !isFirebaseReady {
            ProgressView("Loading…")
        } else if isLoggedIn {
            MainTabView()
                .onAppear { print("✅ MainTabView loaded") }
        } else {
            LoginView(isLoggedIn: $isLoggedIn)
                .onAppear { print("🔵 Showing LoginView") }
        }
    }

    // MARK: - Auto login
    private func setupAutoLogin() {
        // Attach once; Firebase will fire immediately with current user (if any)
        guard authListener == nil else { return }
        authListener = Auth.auth().addStateDidChangeListener { _, user in
            isLoggedIn = (user != nil)
            isFirebaseReady = true
            print("🔐 Auth state changed. Logged in:", isLoggedIn)
        }
    }

    private func detachAuthListener() {
        if let authListener {
            Auth.auth().removeStateDidChangeListener(authListener)
            self.authListener = nil
        }
    }
}
//
//
//
//// CircleYa/Main/MainApp.swift
//import SwiftUI
//import FirebaseCore
//import FirebaseAuth
//
//class AppDelegate: NSObject, UIApplicationDelegate {
//    func application(_ application: UIApplication,
//                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
//        FirebaseApp.configure()
//        return true
//    }
//}
//
//@main
//struct CircleYaApp: App {
//    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
//
//    @State private var isLoggedIn = false
//    @State private var isFirebaseReady = false
//    @State private var authListener: AuthStateDidChangeListenerHandle?
//    #if DEBUG
//    @State private var didSeed = false
//    #endif
//
//    var body: some Scene {
//        WindowGroup {
//            contentView
//                .onAppear(perform: setupAutoLogin)
//                .onDisappear { detachAuthListener() }
//                .onReceive(NotificationCenter.default.publisher(for: .userDidSignOut)) { _ in
//                    print("🚪 Received sign-out notification")
//                    isLoggedIn = false
//                }
//        }
//    }
//
//    // MARK: - Views
//    @ViewBuilder
//    private var contentView: some View {
//        if !isFirebaseReady {
//            ProgressView("Loading…")
//        } else if isLoggedIn {
//            MainTabView()
//                .onAppear { print("✅ MainTabView loaded") }
//        } else {
//            LoginView(isLoggedIn: $isLoggedIn)
//                .onAppear { print("🔵 Showing LoginView") }
//        }
//    }
//
//    // MARK: - Auto login + one-time DEV seed
//    private func setupAutoLogin() {
//        guard authListener == nil else { return }
//        authListener = Auth.auth().addStateDidChangeListener { _, user in
//            isLoggedIn = (user != nil)
//            isFirebaseReady = true
//            print("🔐 Auth state changed. Logged in:", isLoggedIn)
//
//            #if DEBUG
//            // Seed exactly once after Firebase is up (regardless of auth state)
//            if !didSeed {
//                didSeed = true
//                Task {
//                    do { try await DevSeeder.run() }
//                    catch { print("❌ DevSeeder failed:", error.localizedDescription) }
//                }
//            }
//            #endif
//        }
//    }
//
//    private func detachAuthListener() {
//        if let authListener {
//            Auth.auth().removeStateDidChangeListener(authListener)
//            self.authListener = nil
//        }
//    }
//}
