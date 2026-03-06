import SwiftUI

struct LogViewerView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Runner Diagnostics")
                    .font(.title3.bold())
                Spacer()
                Button("Reveal in Finder") { viewModel.openLogsFolder() }
                Button("Refresh") { viewModel.refreshStatus() }
            }

            ScrollView {
                Text(viewModel.latestLog)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(14)
        .frame(minWidth: 760, minHeight: 500)
    }
}
