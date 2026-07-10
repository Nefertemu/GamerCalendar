//
//  SceneDelegate.swift
//  Gamer's Calendar
//
//  Created by Богдан Анищенков on 04.05.2022.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate, UITabBarControllerDelegate {

    var window: UIWindow?

    private let gameService: GameCatalogService = CachedGameCatalogService()


    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }

        // Корень приложения — таб-бар: лента релизов, календарная сетка
        // и отслеживаемые игры.
        // Grouped-стиль: заголовки месяцев не прилипают к навбару при скролле.
        let feedViewController = TableViewController(style: .grouped, gameService: gameService)
        feedViewController.tabBarItem = UITabBarItem(
            title: String(localized: "Feed"),
            image: UIImage(systemName: "list.bullet.below.rectangle"),
            tag: 0
        )

        let gridViewController = MonthGridViewController(gameService: gameService)
        gridViewController.tabBarItem = UITabBarItem(
            title: String(localized: "Calendar"),
            image: UIImage(systemName: "calendar"),
            tag: 1
        )

        let watchlistViewController = WatchlistViewController(gameService: gameService)
        watchlistViewController.tabBarItem = UITabBarItem(
            title: String(localized: "Watchlist"),
            image: UIImage(systemName: "bell"),
            tag: 2
        )

        let tabBarController = UITabBarController()
        tabBarController.delegate = self
        let settingsViewController = SettingsViewController()
        settingsViewController.tabBarItem = UITabBarItem(
            title: String(localized: "Settings"),
            image: UIImage(systemName: "gearshape"),
            tag: 3
        )

        tabBarController.viewControllers = [
            UINavigationController(rootViewController: feedViewController),
            UINavigationController(rootViewController: gridViewController),
            UINavigationController(rootViewController: watchlistViewController),
            UINavigationController(rootViewController: settingsViewController)
        ]

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = tabBarController
        window.makeKeyAndVisible()
        self.window = window

        // Запуск по ссылке из виджета или из Spotlight.
        if let url = connectionOptions.urlContexts.first?.url {
            handle(url)
        }
        if let userActivity = connectionOptions.userActivities.first {
            self.scene(scene, continue: userActivity)
        }

        showOnboardingIfNeeded(from: tabBarController)
    }

    // MARK: - Deep links (виджет, шаринг) и Spotlight

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        handle(url)
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard let gameID = GameDeepLink.gameID(from: userActivity) else { return }
        openGame(id: gameID)
    }

    /// Разбирает ссылки вида gamercalendar://game/123.
    private func handle(_ url: URL) {
        guard let gameID = GameDeepLink.gameID(from: url) else { return }
        openGame(id: gameID)
    }

    private func openGame(id: Int) {
        guard let tabBarController = window?.rootViewController as? UITabBarController,
              let navigation = tabBarController.selectedViewController as? UINavigationController else { return }

        Task {
            guard let game = try? await gameService.fetchGames(ids: [id]).first else { return }
            navigation.pushViewController(
                GameDetailViewController(game: game, gameService: gameService),
                animated: true
            )
        }
    }

    private func showOnboardingIfNeeded(from tabBarController: UITabBarController) {
        guard !AppSettings.didShowOnboarding else { return }

        let onboarding = OnboardingViewController()
        onboarding.modalPresentationStyle = .formSheet
        tabBarController.present(onboarding, animated: true)
    }

    // MARK: - UITabBarControllerDelegate

    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        // Повторный тап по текущему табу прокручивает список к началу.
        if viewController === tabBarController.selectedViewController,
           let navigation = viewController as? UINavigationController,
           let tableController = navigation.topViewController as? UITableViewController {
            let topOffset = CGPoint(x: 0, y: -tableController.tableView.adjustedContentInset.top)
            tableController.tableView.setContentOffset(topOffset, animated: true)
        }
        return true
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Пересчитываем еженедельный дайджест: список отслеживаемых игр
        // и их даты могли измениться.
        if AppSettings.weeklyDigestEnabled {
            ReminderService.shared.scheduleWeeklyDigest()
        }
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
        // Use this method to undo the changes made on entering the background.
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Use this method to save data, release shared resources, and store enough scene-specific state information
        // to restore the scene back to its current state.
    }


}
