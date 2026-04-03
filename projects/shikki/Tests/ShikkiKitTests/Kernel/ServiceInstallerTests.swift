import Foundation
import Testing
@testable import ShikkiKit

// MARK: - LaunchdInstaller Tests

@Suite("LaunchdInstaller")
struct LaunchdInstallerTests {

    @Test("Persistent plist contains correct Label")
    func persistentPlistLabel() {
        let plist = LaunchdInstaller.generatePersistentPlist(binaryPath: "/usr/local/bin/shi")
        #expect(plist.contains("<string>dev.shikki.daemon</string>"))
    }

    @Test("Persistent plist contains ProgramArguments with binary path")
    func persistentPlistBinaryPath() {
        let plist = LaunchdInstaller.generatePersistentPlist(binaryPath: "/opt/homebrew/bin/shi")
        #expect(plist.contains("<string>/opt/homebrew/bin/shi</string>"))
        #expect(plist.contains("<string>daemon</string>"))
    }

    @Test("Persistent plist contains KeepAlive")
    func persistentPlistKeepAlive() {
        let plist = LaunchdInstaller.generatePersistentPlist(binaryPath: "/usr/local/bin/shi")
        #expect(plist.contains("<key>KeepAlive</key><true/>"))
    }

    @Test("Persistent plist contains RunAtLoad")
    func persistentPlistRunAtLoad() {
        let plist = LaunchdInstaller.generatePersistentPlist(binaryPath: "/usr/local/bin/shi")
        #expect(plist.contains("<key>RunAtLoad</key><true/>"))
    }

    @Test("Persistent plist contains correct log paths")
    func persistentPlistLogPaths() {
        let plist = LaunchdInstaller.generatePersistentPlist(binaryPath: "/usr/local/bin/shi")
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(plist.contains("\(home)/.shikki/logs/daemon.stdout.log"))
        #expect(plist.contains("\(home)/.shikki/logs/daemon.stderr.log"))
    }

    @Test("Persistent plist contains PATH environment variable")
    func persistentPlistPATH() {
        let plist = LaunchdInstaller.generatePersistentPlist(binaryPath: "/usr/local/bin/shi")
        #expect(plist.contains("<key>PATH</key>"))
        #expect(plist.contains("/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"))
    }

    @Test("Persistent plist is valid XML structure")
    func persistentPlistXMLStructure() {
        let plist = LaunchdInstaller.generatePersistentPlist(binaryPath: "/usr/local/bin/shi")
        #expect(plist.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"))
        #expect(plist.contains("<!DOCTYPE plist"))
        #expect(plist.contains("<plist version=\"1.0\">"))
        #expect(plist.contains("</plist>"))
    }

    @Test("Scheduled plist contains StartInterval of 30")
    func scheduledPlistStartInterval() {
        let plist = LaunchdInstaller.generateScheduledPlist(binaryPath: "/usr/local/bin/shi")
        #expect(plist.contains("<key>StartInterval</key>"))
        #expect(plist.contains("<integer>30</integer>"))
    }

    @Test("Scheduled plist does NOT contain KeepAlive")
    func scheduledPlistNoKeepAlive() {
        let plist = LaunchdInstaller.generateScheduledPlist(binaryPath: "/usr/local/bin/shi")
        #expect(!plist.contains("KeepAlive"))
    }

    @Test("Scheduled plist has different Label than persistent")
    func scheduledPlistLabel() {
        let plist = LaunchdInstaller.generateScheduledPlist(binaryPath: "/usr/local/bin/shi")
        #expect(plist.contains("<string>dev.shikki.daemon-scheduled</string>"))
    }

    @Test("Scheduled plist contains --mode scheduled arguments")
    func scheduledPlistModeArguments() {
        let plist = LaunchdInstaller.generateScheduledPlist(binaryPath: "/usr/local/bin/shi")
        #expect(plist.contains("<string>--mode</string>"))
        #expect(plist.contains("<string>scheduled</string>"))
    }

    @Test("Plist path for persistent mode")
    func plistPathPersistent() {
        let path = LaunchdInstaller.plistPath(for: .persistent)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(path == "\(home)/Library/LaunchAgents/dev.shikki.daemon.plist")
    }

    @Test("Plist path for scheduled mode")
    func plistPathScheduled() {
        let path = LaunchdInstaller.plistPath(for: .scheduled)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(path == "\(home)/Library/LaunchAgents/dev.shikki.daemon-scheduled.plist")
    }

    @Test("isInstalled returns false when plist does not exist")
    func isInstalledReturnsFalse() {
        #expect(!LaunchdInstaller.isInstalled(mode: .persistent))
    }
}

// MARK: - SystemdInstaller Tests

@Suite("SystemdInstaller")
struct SystemdInstallerTests {

    @Test("Persistent unit contains Type=simple")
    func persistentUnitTypeSimple() {
        let unit = SystemdInstaller.generatePersistentUnit(binaryPath: "/usr/local/bin/shi")
        #expect(unit.contains("Type=simple"))
    }

    @Test("Persistent unit contains Restart=always")
    func persistentUnitRestartAlways() {
        let unit = SystemdInstaller.generatePersistentUnit(binaryPath: "/usr/local/bin/shi")
        #expect(unit.contains("Restart=always"))
    }

    @Test("Persistent unit contains correct ExecStart")
    func persistentUnitExecStart() {
        let unit = SystemdInstaller.generatePersistentUnit(binaryPath: "/opt/bin/shi")
        #expect(unit.contains("ExecStart=/opt/bin/shi daemon"))
    }

    @Test("Persistent unit contains RestartSec=5")
    func persistentUnitRestartSec() {
        let unit = SystemdInstaller.generatePersistentUnit(binaryPath: "/usr/local/bin/shi")
        #expect(unit.contains("RestartSec=5"))
    }

    @Test("Persistent unit contains WantedBy=default.target")
    func persistentUnitWantedBy() {
        let unit = SystemdInstaller.generatePersistentUnit(binaryPath: "/usr/local/bin/shi")
        #expect(unit.contains("WantedBy=default.target"))
    }

    @Test("Persistent unit contains Description")
    func persistentUnitDescription() {
        let unit = SystemdInstaller.generatePersistentUnit(binaryPath: "/usr/local/bin/shi")
        #expect(unit.contains("Description=Shikki Daemon"))
    }

    @Test("Persistent unit contains PATH environment")
    func persistentUnitPATH() {
        let unit = SystemdInstaller.generatePersistentUnit(binaryPath: "/usr/local/bin/shi")
        #expect(unit.contains("Environment=PATH=/usr/local/bin:/usr/bin:/bin"))
    }

    @Test("Scheduled service contains Type=oneshot")
    func scheduledServiceOneshot() {
        let unit = SystemdInstaller.generateScheduledService(binaryPath: "/usr/local/bin/shi")
        #expect(unit.contains("Type=oneshot"))
    }

    @Test("Scheduled service contains --mode scheduled")
    func scheduledServiceModeArg() {
        let unit = SystemdInstaller.generateScheduledService(binaryPath: "/usr/local/bin/shi")
        #expect(unit.contains("ExecStart=/usr/local/bin/shi daemon --mode scheduled"))
    }

    @Test("Scheduled service does NOT contain Restart=always")
    func scheduledServiceNoRestart() {
        let unit = SystemdInstaller.generateScheduledService(binaryPath: "/usr/local/bin/shi")
        #expect(!unit.contains("Restart=always"))
    }

    @Test("Scheduled timer contains OnCalendar")
    func scheduledTimerOnCalendar() {
        let timer = SystemdInstaller.generateScheduledTimer()
        #expect(timer.contains("OnCalendar=*:*:0/30"))
    }

    @Test("Scheduled timer contains Persistent=true")
    func scheduledTimerPersistent() {
        let timer = SystemdInstaller.generateScheduledTimer()
        #expect(timer.contains("Persistent=true"))
    }

    @Test("Scheduled timer contains WantedBy=timers.target")
    func scheduledTimerWantedBy() {
        let timer = SystemdInstaller.generateScheduledTimer()
        #expect(timer.contains("WantedBy=timers.target"))
    }

    @Test("Unit path for persistent mode")
    func unitPathPersistent() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = SystemdInstaller.unitPath(for: .persistent)
        #expect(path == "\(home)/.config/systemd/user/shikki-daemon.service")
    }

    @Test("Unit path for scheduled mode returns service path")
    func unitPathScheduled() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = SystemdInstaller.unitPath(for: .scheduled)
        #expect(path == "\(home)/.config/systemd/user/shikki-daemon-scheduled.service")
    }

    @Test("Timer path for scheduled mode")
    func timerPath() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = SystemdInstaller.timerPath()
        #expect(path == "\(home)/.config/systemd/user/shikki-daemon-scheduled.timer")
    }

    @Test("isInstalled returns false when unit does not exist")
    func isInstalledReturnsFalse() {
        #expect(!SystemdInstaller.isInstalled(mode: .persistent))
    }
}

// MARK: - DaemonMode Tests

@Suite("DaemonMode")
struct DaemonModeTests {

    @Test("DaemonMode raw values")
    func rawValues() {
        #expect(DaemonMode.persistent.rawValue == "persistent")
        #expect(DaemonMode.scheduled.rawValue == "scheduled")
    }
}
