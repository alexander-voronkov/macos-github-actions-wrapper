import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RunnerTray Settings")
                .font(.title2.bold())

            Form {
                TextField("GitHub URL", text: $viewModel.settings.githubURL)
                TextField("Runner Name", text: $viewModel.settings.runnerName)
                TextField("Labels", text: $viewModel.settings.labels)
                TextField("Work Folder", text: $viewModel.settings.workFolder)

                Toggle("Use Existing Runner Folder", isOn: $viewModel.settings.useExistingFolder)
                HStack {
                    TextField("Runner Installation Folder", text: $viewModel.settings.installationFolder)
                    Button("Choose…") { viewModel.pickFolder() }
                }

                SecureField("Registration Token", text: $viewModel.registrationToken)
                Toggle("Unattended Configure", isOn: $viewModel.settings.unattendedConfigure)
                Toggle("Launch at Login", isOn: Binding(
                    get: { viewModel.settings.launchAtLogin },
                    set: { viewModel.setLaunchAtLogin($0) }
                ))
                Toggle("Start Runner Automatically After App Launch", isOn: $viewModel.settings.autoStartAfterLaunch)
            }

            HStack {
                Button("Configure Runner") { Task { await viewModel.configureRunner() } }
                Button("Save Settings") {
                    viewModel.persistSettings()
                    viewModel.refreshStatus()
                }
                Spacer()
                Text("Status: \(viewModel.status.menuDescription)")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Recent Log Lines")
                    .font(.headline)
                ScrollView {
                    Text(viewModel.latestLog)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(height: 170)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(16)
        .frame(width: 720, height: 620)
        .alert("RunnerTray", isPresented: Binding(get: { viewModel.alertMessage != nil }, set: { _ in viewModel.alertMessage = nil })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.alertMessage ?? "")
        }
    }
}
