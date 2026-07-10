import UIKit
import UserNotifications

final class SettingsViewController: UITableViewController {

    private enum Section: Int, CaseIterable {
        case reminders
        case app
    }

    private let leadOptions = [0, 1, 7]

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = String(localized: "Settings")
        navigationController?.navigationBar.prefersLargeTitles = true
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .reminders:
            return leadOptions.count + 1
        case .app:
            return 2
        case .none:
            return 0
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .reminders:
            return String(localized: "Reminders")
        case .app:
            return String(localized: "App")
        case .none:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section) {
        case .reminders:
            return reminderCell(for: indexPath.row)
        case .app:
            return appCell(for: indexPath.row)
        case .none:
            return UITableViewCell()
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch Section(rawValue: indexPath.section) {
        case .reminders where indexPath.row < leadOptions.count:
            toggleLeadDays(leadOptions[indexPath.row])
        case .app where indexPath.row == 0:
            clearCachedResponses()
        case .app where indexPath.row == 1:
            openSystemSettings()
        default:
            break
        }
    }

    private func reminderCell(for row: Int) -> UITableViewCell {
        if row < leadOptions.count {
            let days = leadOptions[row]
            let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
            cell.textLabel?.text = reminderTitle(for: days)
            cell.detailTextLabel?.text = String(localized: "Applies to newly added and refreshed watchlist games")
            cell.accessoryType = AppSettings.notificationLeadDays.contains(days) ? .checkmark : .none
            return cell
        }

        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = String(localized: "Weekly digest")
        let digestSwitch = UISwitch()
        digestSwitch.isOn = AppSettings.weeklyDigestEnabled
        digestSwitch.addAction(UIAction { _ in
            AppSettings.weeklyDigestEnabled = digestSwitch.isOn
            if digestSwitch.isOn {
                ReminderService.shared.scheduleWeeklyDigest()
            } else {
                ReminderService.shared.cancelWeeklyDigest()
            }
        }, for: .valueChanged)
        cell.accessoryView = digestSwitch
        return cell
    }

    private func appCell(for row: Int) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)

        if row == 0 {
            cell.textLabel?.text = String(localized: "Clear offline cache")
            cell.detailTextLabel?.text = String(localized: "Forces the next launch to refresh game data")
            cell.imageView?.image = UIImage(systemName: "trash")
        } else {
            cell.textLabel?.text = String(localized: "Notification Settings")
            cell.detailTextLabel?.text = String(localized: "Open iOS settings for Gamer Calendar")
            cell.imageView?.image = UIImage(systemName: "bell.badge")
            cell.accessoryType = .disclosureIndicator
        }

        return cell
    }

    private func toggleLeadDays(_ days: Int) {
        var selected = AppSettings.notificationLeadDays
        if selected.contains(days), selected.count > 1 {
            selected.remove(days)
        } else {
            selected.insert(days)
        }
        AppSettings.notificationLeadDays = selected
        tableView.reloadSections(IndexSet(integer: Section.reminders.rawValue), with: .automatic)
    }

    private func reminderTitle(for days: Int) -> String {
        switch days {
        case 0:
            return String(localized: "Release day")
        case 1:
            return String(localized: "1 day before")
        default:
            return String(localized: "\(days) days before")
        }
    }

    private func clearCachedResponses() {
        CatalogCacheMaintenance.clear()
        let alert = UIAlertController(
            title: String(localized: "Cache cleared"),
            message: String(localized: "Fresh game data will load next time."),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

}

final class OnboardingViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground

        let titleLabel = UILabel()
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .center
        titleLabel.text = String(localized: "Track game releases")

        let subtitleLabel = UILabel()
        subtitleLabel.font = .systemFont(ofSize: 16)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0
        subtitleLabel.textAlignment = .center
        subtitleLabel.text = String(localized: "Search upcoming games, browse the calendar, and get release reminders.")

        var notificationsConfig = UIButton.Configuration.borderedProminent()
        notificationsConfig.title = String(localized: "Enable Notifications")
        notificationsConfig.image = UIImage(systemName: "bell")
        notificationsConfig.imagePadding = 8
        let notificationsButton = UIButton(configuration: notificationsConfig, primaryAction: UIAction { [weak self] action in
            guard let button = action.sender as? UIButton else { return }
            button.isEnabled = false
            button.configuration?.showsActivityIndicator = true

            Task {
                _ = try? await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound, .badge])
                await MainActor.run {
                    AppSettings.didShowOnboarding = true
                    self?.dismiss(animated: true)
                }
            }
        })

        var continueConfig = UIButton.Configuration.bordered()
        continueConfig.title = String(localized: "Continue")
        let continueButton = UIButton(configuration: continueConfig, primaryAction: UIAction { [weak self] _ in
            AppSettings.didShowOnboarding = true
            self?.dismiss(animated: true)
        })

        let stack = UIStackView(arrangedSubviews: [
            UIImageView(image: UIImage(systemName: "calendar.badge.clock")),
            titleLabel,
            subtitleLabel,
            notificationsButton,
            continueButton
        ])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        if let iconView = stack.arrangedSubviews.first as? UIImageView {
            iconView.tintColor = .systemBlue
            iconView.contentMode = .scaleAspectFit
            iconView.widthAnchor.constraint(equalToConstant: 72).isActive = true
            iconView.heightAnchor.constraint(equalToConstant: 72).isActive = true
        }

        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            notificationsButton.widthAnchor.constraint(equalTo: stack.widthAnchor),
            continueButton.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

}
