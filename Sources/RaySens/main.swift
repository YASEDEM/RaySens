import SwiftUI
import Foundation
import ServiceManagement

@MainActor
final class Monitor: ObservableObject {
    @Published var cpuFrequency = "Reading system frequency…"
    @Published var cpuTemperature = "Unavailable · start live monitor"
    @Published var frequencySource = ""
    @Published var turboStatus = "Checking status…"
    @Published var turboActivity = "Waiting for a sample"
    @Published var turboEnabled = true
    @Published var autoDisableOnStartup = false
    @Published var autoStartupMessage = "Turbo remains unchanged on the next startup."
    @Published var launchAtLogin = false
    @Published var loginItemMessage = ""
    @Published var isWorking = false
    @Published var frequencyMonitorRunning = false
    @Published var frequencyMonitorMessage = "Live monitoring is off; nominal frequency is shown without permission."
    @Published var updatedAt = ""
    private var timer: Timer?
    private var sampling = false

    func start() {
        guard timer == nil else {
            refreshTurboState()
            refreshFrequencyState()
            return
        }
        cpuFrequency = Self.nominalFrequency() ?? "Unavailable"
        frequencySource = "Nominal/base frequency · no permission needed"
        autoDisableOnStartup = FileManager.default.fileExists(atPath: Self.turboStartupDaemonPath)
        autoStartupMessage = autoDisableOnStartup ? "Turbo will be disabled during macOS startup." : "Turbo remains unchanged on the next startup."
        let loginStatus = SMAppService.mainApp.status
        launchAtLogin = loginStatus == .enabled || loginStatus == .requiresApproval
        loginItemMessage = loginStatus == .requiresApproval ? "Allow RaySens in System Settings → General → Login Items." : ""
        refreshTurboState()
        refreshFrequencyState()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshFrequencyState() }
        }
    }

    func refreshTurboState() {
        Task.detached(priority: .utility) {
            let isDisabled = Self.turboKextIsLoaded()
            await MainActor.run {
                self.turboEnabled = !isDisabled
                self.turboStatus = isDisabled ? "Disabled · RaySens extension loaded" : "Enabled · RaySens extension not loaded"
            }
        }
    }

    func setTurbo(_ enabled: Bool) {
        guard enabled != turboEnabled, !isWorking else { return }
        isWorking = true
        turboStatus = enabled ? "Enabling Turbo…" : "Disabling Turbo…"
        Task.detached(priority: .userInitiated) {
            let result = Self.setTurboWithAdminPrompt(enabled)
            let isDisabled = Self.turboKextIsLoaded()
            await MainActor.run {
                self.isWorking = false
                self.turboEnabled = !isDisabled
                if result.success && (self.turboEnabled == enabled) {
                    self.turboStatus = enabled ? "Enabled" : "Disabled"
                } else {
                    self.turboStatus = result.message
                }
            }
        }
    }

    func setAutoDisableOnStartup(_ enabled: Bool) {
        guard enabled != autoDisableOnStartup, !isWorking else { return }
        isWorking = true
        autoStartupMessage = enabled ? "Setting up startup control…" : "Removing startup control…"
        Task.detached(priority: .userInitiated) {
            let result = Self.setTurboStartupEnabled(enabled)
            await MainActor.run {
                self.isWorking = false
                if result.success {
                    self.autoDisableOnStartup = enabled
                    self.autoStartupMessage = enabled ? "Turbo will be disabled during macOS startup." : "Startup auto-disable is off."
                } else {
                    self.autoStartupMessage = result.message
                }
            }
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            let status = SMAppService.mainApp.status
            launchAtLogin = status == .enabled || status == .requiresApproval
            loginItemMessage = status == .requiresApproval
                ? "Allow RaySens in System Settings → General → Login Items."
                : (enabled ? "RaySens will open after you sign in." : "RaySens will not open at login.")
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            loginItemMessage = error.localizedDescription
        }
    }

    func toggleFrequencyMonitor() {
        guard !isWorking else { return }
        isWorking = true
        frequencyMonitorMessage = frequencyMonitorRunning ? "Stopping frequency monitor…" : "Starting frequency monitor…"
        let shouldRun = !frequencyMonitorRunning
        Task.detached(priority: .userInitiated) {
            let result = Self.setFrequencyMonitorRunning(shouldRun)
            let running = Self.frequencySamplerIsRunning()
            await MainActor.run {
                self.isWorking = false
                self.frequencyMonitorRunning = running
                self.frequencyMonitorMessage = result.success
                    ? (running ? "Live CPU frequency monitoring is running." : "Starting monitor; waiting for the first sample…")
                    : result.message
            }
        }
    }

    func refreshFrequencyState() {
        guard !sampling else { return }
        sampling = true
        Task.detached(priority: .utility) {
            let running = Self.frequencySamplerIsRunning()
            let reading = Self.cpuFrequencyReading()
            await MainActor.run {
                self.frequencyMonitorRunning = running
                if let reading {
                    self.cpuFrequency = reading.frequency
                    self.frequencySource = "Live average · powermetrics"
                    self.turboActivity = reading.turbo
                    self.cpuTemperature = reading.temperature ?? "SMC temperature unavailable"
                } else if !running {
                    self.turboActivity = "Live sample unavailable while monitor is off"
                }
                if reading == nil, let error = Self.frequencyError() {
                    self.frequencyMonitorMessage = error
                } else if running, reading == nil {
                    self.frequencyMonitorMessage = "Waiting for powermetrics sample…"
                }
                self.updatedAt = Date.now.formatted(date: .omitted, time: .shortened)
                self.sampling = false
            }
        }
    }

    nonisolated private static func run(_ path: String, _ args: [String]) -> String? {
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do {
            try p.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch { return nil }
    }

    nonisolated private static func turboKextIsLoaded() -> Bool {
        guard let output = run("/usr/bin/kmutil", ["showloaded"]) else { return false }
        return output.localizedCaseInsensitiveContains("dev.raysens.DisableTurboBoost")
    }

    nonisolated private static let frequencyDirectory = "/Library/Application Support/RaySens"
    nonisolated private static var frequencyLogPath: String { frequencyDirectory + "/powermetrics.log" }
    nonisolated private static var frequencyErrorPath: String { frequencyDirectory + "/powermetrics.err" }
    nonisolated private static var frequencyDaemonPath: String { "/Library/LaunchDaemons/dev.raysens.powermetrics.plist" }
    nonisolated private static var turboStartupDaemonPath: String { "/Library/LaunchDaemons/dev.raysens.turbo-startup.plist" }

    nonisolated private static func nominalFrequency() -> String? {
        guard let value = run("/usr/sbin/sysctl", ["-n", "hw.cpufrequency"]),
              let hz = Double(value) else { return nil }
        return String(format: "%.2f GHz", hz / 1_000_000_000)
    }

    nonisolated private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    nonisolated private static func runWithAdminPrompt(_ command: String) -> (success: Bool, message: String) {
        let appleScriptCommand = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "do shell script \"\(appleScriptCommand)\" with administrator privileges"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return process.terminationStatus == 0 ? (true, "Completed") : (false, output.isEmpty ? "Cancelled or command failed" : output)
        } catch { return (false, error.localizedDescription) }
    }

    nonisolated private static func frequencySamplerIsRunning() -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: frequencyLogPath),
              let modified = attributes[.modificationDate] as? Date else { return false }
        return Date().timeIntervalSince(modified) < 8
    }

    nonisolated private static func setFrequencyMonitorRunning(_ running: Bool) -> (success: Bool, message: String) {
        let dir = shellQuote(frequencyDirectory)
        let daemon = shellQuote(frequencyDaemonPath)
        let command: String
        if running {
            guard let resources = Bundle.main.resourceURL else { return (false, "The frequency monitor resources are missing.") }
            let sourceScript = shellQuote(resources.appendingPathComponent("powermetrics-loop.sh").path)
            let sourceSMCHelper = shellQuote(resources.appendingPathComponent("smc-temperature").path)
            let sourcePlist = shellQuote(resources.appendingPathComponent("dev.raysens.powermetrics.plist").path)
            let installedScript = shellQuote(frequencyDirectory + "/powermetrics-loop.sh")
            let installedSMCHelper = shellQuote(frequencyDirectory + "/smc-temperature")
            command = "mkdir -p \(dir) /Library/LaunchDaemons && chown root:wheel \(dir) && chmod 755 \(dir) && /usr/bin/ditto \(sourceScript) \(installedScript) && /usr/bin/ditto \(sourceSMCHelper) \(installedSMCHelper) && /usr/bin/ditto \(sourcePlist) \(daemon) && chown root:wheel \(installedScript) \(installedSMCHelper) \(daemon) && chmod 755 \(installedScript) \(installedSMCHelper) && chmod 644 \(daemon) && (/bin/launchctl bootout system \(daemon) >/dev/null 2>&1 || true) && rm -f \(shellQuote(frequencyLogPath)) \(shellQuote(frequencyLogPath + ".tmp")) \(shellQuote(frequencyErrorPath)) && /bin/launchctl bootstrap system \(daemon) && /bin/launchctl kickstart -k system/dev.raysens.powermetrics"
        } else {
            command = "(/bin/launchctl bootout system \(daemon) >/dev/null 2>&1 || true); rm -f \(daemon) \(shellQuote(frequencyLogPath)) \(shellQuote(frequencyLogPath + ".tmp")) \(shellQuote(frequencyErrorPath))"
        }
        return runWithAdminPrompt(command)
    }

    nonisolated private static func frequencyError() -> String? {
        guard let value = try? String(contentsOfFile: frequencyErrorPath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value.components(separatedBy: .newlines).suffix(2).joined(separator: " ")
    }

    nonisolated private static func setTurboStartupEnabled(_ enabled: Bool) -> (success: Bool, message: String) {
        let daemon = shellQuote(turboStartupDaemonPath)
        if !enabled {
            return runWithAdminPrompt("(/bin/launchctl bootout system \(daemon) >/dev/null 2>&1 || true); rm -f \(daemon)")
        }
        guard let resources = Bundle.main.resourceURL else { return (false, "RaySens startup resources are missing.") }
        let sourceKext = shellQuote(resources.appendingPathComponent("DisableTurboBoost.64bits.kext").path)
        let sourceScript = shellQuote(resources.appendingPathComponent("disable-turbo-on-start.sh").path)
        let sourcePlist = shellQuote(resources.appendingPathComponent("dev.raysens.turbo-startup.plist").path)
        let installedKext = shellQuote(frequencyDirectory + "/DisableTurboBoost.64bits.kext")
        let installedScript = shellQuote(frequencyDirectory + "/disable-turbo-on-start.sh")
        let command = "mkdir -p \(shellQuote(frequencyDirectory)) /Library/LaunchDaemons && chown root:wheel \(shellQuote(frequencyDirectory)) && chmod 755 \(shellQuote(frequencyDirectory)) && /usr/bin/ditto \(sourceKext) \(installedKext) && /usr/bin/ditto \(sourceScript) \(installedScript) && /usr/bin/ditto \(sourcePlist) \(daemon) && chown -R root:wheel \(installedKext) && chown root:wheel \(installedScript) \(daemon) && chmod 755 \(installedScript) && chmod 644 \(daemon)"
        return runWithAdminPrompt(command)
    }

    nonisolated private static func setTurboWithAdminPrompt(_ enabled: Bool) -> (success: Bool, message: String) {
        guard let resourceURL = Bundle.main.resourceURL?.appendingPathComponent("DisableTurboBoost.64bits.kext"),
              FileManager.default.fileExists(atPath: resourceURL.path) else {
            return (false, "The bundled Turbo Boost extension was not found.")
        }
        let installedPath = "/Library/Application Support/RaySens/DisableTurboBoost.64bits.kext"
        let quote: (String) -> String = { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let command: String
        if enabled {
            command = "/sbin/kextunload -v -b dev.raysens.DisableTurboBoost"
        } else {
            command = "/bin/mkdir -p '/Library/Application Support/RaySens' && /usr/bin/ditto \(quote(resourceURL.path)) \(quote(installedPath)) && /usr/sbin/chown -R root:wheel \(quote(installedPath)) && /usr/bin/kextutil -v \(quote(installedPath))"
        }
        return runWithAdminPrompt(command)
    }

    nonisolated private static func cpuFrequencyReading() -> (frequency: String, turbo: String, temperature: String?)? {
        guard let out = try? String(contentsOfFile: frequencyLogPath, encoding: .utf8) else { return nil }

        // Intel powermetrics output reports average frequency as a percentage of
        // nominal and in MHz. This percentage is the best available non-invasive
        // indication of whether turbo frequencies were reached in this sample.
        let pattern = #"(?i)System Average frequency as fraction of nominal:\s*([0-9.]+)%\s*\(([0-9.]+)\s*M(?:hz|Hz)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.matches(in: out, range: NSRange(out.startIndex..., in: out)).last,
              let percentRange = Range(match.range(at: 1), in: out),
              let mhzRange = Range(match.range(at: 2), in: out),
              let percent = Double(out[percentRange]) else { return nil }
        let mhz = Double(out[mhzRange]) ?? 0
        let turbo = percent > 100 ? "Turbo frequency observed · \(String(format: "%.0f", percent))% of nominal" : "No turbo frequency in this sample"
        // SMC sensor labels vary by firmware and VirtualSMC plugin. Prefer a
        // CPU-labelled temperature from the direct SMC helper; accept any
        // temperature row as a compatibility fallback, excluding GPU rows.
        let temperaturePattern = #"(?im)^([^\n]*(?:CPU|processor)[^\n]*temperature[^:\n]*):\s*([0-9]+(?:\.[0-9]+)?)\s*(?:°?C)\b[^\n]*$"#
        let fallbackTemperaturePattern = #"(?im)^([^\n]*temperature[^:\n]*):\s*([0-9]+(?:\.[0-9]+)?)\s*(?:°?C)\b[^\n]*$"#
        let temperature: String?
        let range = NSRange(out.startIndex..., in: out)
        let cpuMatches = (try? NSRegularExpression(pattern: temperaturePattern))?.matches(in: out, range: range) ?? []
        let fallbackMatches = (try? NSRegularExpression(pattern: fallbackTemperaturePattern))?.matches(in: out, range: range) ?? []
        if let match = (cpuMatches.last ?? fallbackMatches.last),
           let valueRange = Range(match.range(at: 2), in: out) {
            temperature = "\(out[valueRange]) °C"
        } else if out.contains("CPU temperature unavailable: no CPU sensor key in SMC") {
            temperature = "No CPU sensor key in SMC"
        } else if out.contains("CPU temperature unavailable:") {
            temperature = "SMC sensor read failed"
        } else {
            temperature = nil
        }
        return (String(format: "%.2f GHz", mhz / 1000), turbo, temperature)
    }

}

@main
struct RaySensApp: App {
    @StateObject private var monitor = Monitor()

    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 9) {
                    Image(systemName: "speedometer").font(.system(size: 21, weight: .semibold)).foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("RaySens").font(.headline)
                    }
                    Spacer()
                    if monitor.isWorking { ProgressView().controlSize(.small) }
                }
                Divider()
                reading("CPU frequency", value: monitor.cpuFrequency, icon: "cpu")
                Text(monitor.frequencySource).font(.caption2).foregroundStyle(.secondary).padding(.leading, 28)
                reading("CPU temperature", value: monitor.cpuTemperature, icon: "thermometer.medium")
                reading("Turbo Boost", value: monitor.turboStatus, icon: "bolt.fill")
                reading("Turbo activity", value: monitor.turboActivity, icon: "waveform.path.ecg")
                HStack(spacing: 8) {
                    Button("Disable Turbo") { monitor.setTurbo(false) }
                        .buttonStyle(.bordered)
                        .disabled(monitor.isWorking || !monitor.turboEnabled)
                    Button("Enable Turbo") { monitor.setTurbo(true) }
                        .buttonStyle(.bordered)
                        .disabled(monitor.isWorking || monitor.turboEnabled)
                }
                Toggle("Disable Turbo on system startup", isOn: Binding(
                    get: { monitor.autoDisableOnStartup },
                    set: { monitor.setAutoDisableOnStartup($0) }
                )).disabled(monitor.isWorking)
                Text(monitor.autoStartupMessage).font(.caption2).foregroundStyle(.secondary)
                Divider()
                Button(monitor.frequencyMonitorRunning ? "Stop live frequency monitor" : "Start live frequency monitor") {
                    monitor.toggleFrequencyMonitor()
                }
                .disabled(monitor.isWorking)
                Text(monitor.frequencyMonitorMessage)
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Toggle("Open RaySens at login", isOn: Binding(
                    get: { monitor.launchAtLogin },
                    set: { monitor.setLaunchAtLogin($0) }
                ))
                Text(monitor.loginItemMessage).font(.caption2).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Refresh") { monitor.refreshFrequencyState(); monitor.refreshTurboState() }
                }
                Text("Updated: \(monitor.updatedAt)").font(.caption2).foregroundStyle(.tertiary)
                Divider()
                Button("Quit RaySens") { NSApplication.shared.terminate(nil) }
            }
            .padding(14)
            .frame(width: 350)
            .onAppear { monitor.start() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: monitor.turboEnabled ? "bolt.fill" : "bolt.slash.fill")
                Text(monitor.cpuFrequency)
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
            }
            .onAppear { monitor.start() }
        }
        .menuBarExtraStyle(.window)
    }

    private func reading(_ title: String, value: String, icon: String) -> some View {
        HStack(alignment: .top) {
            Image(systemName: icon).frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.system(.body, design: .rounded).weight(.semibold))
            }
            Spacer()
        }
    }
}
