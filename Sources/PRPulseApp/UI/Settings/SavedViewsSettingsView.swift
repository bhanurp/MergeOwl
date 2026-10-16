import SwiftUI

struct SavedViewsSettingsView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var draft: SavedPRView?
    @State private var removing: SavedPRView?
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        Form {
            Section {
                Text("My PRs, Review Requested, and Watched are always available. Saved views combine matching PRs from those lists for this account only.")
                    .foregroundStyle(.secondary)
                Button("Create saved view", systemImage: "plus") { draft = SavedPRView(name: "") }
            }
            Section("Your views") {
                if viewModel.savedViews.isEmpty { Text("No saved views yet.").foregroundStyle(.secondary) }
                ForEach(Array(viewModel.savedViews.enumerated()), id: \.element.id) { index, view in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Toggle(view.name, isOn: Binding(get: { view.enabled }, set: { enabled in
                                var changed = view; changed.enabled = enabled
                                perform { try await viewModel.saveView(changed) }
                            }))
                            .accessibilityIdentifier("prpulse.view-enabled.\(view.name)")
                            Spacer()
                            Button("Edit") { draft = view }.accessibilityLabel("Edit \(view.name)")
                            Button("Delete", role: .destructive) { removing = view }.accessibilityLabel("Delete \(view.name)")
                        }
                        HStack {
                            Text(view.stateRule.rawValue).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Move up", systemImage: "arrow.up") { perform { try await viewModel.moveView(id: view.id, offset: -1) } }
                                .accessibilityLabel("Move \(view.name) up").disabled(index == 0)
                            Button("Move down", systemImage: "arrow.down") { perform { try await viewModel.moveView(id: view.id, offset: 1) } }
                                .accessibilityLabel("Move \(view.name) down").disabled(index == viewModel.savedViews.count - 1)
                        }
                    }.padding(.vertical, 4)
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
            if let storageError = viewModel.errorMessage { Text(storageError).foregroundStyle(.orange) }
        }
        .formStyle(.grouped)
        .disabled(busy)
        .sheet(item: $draft) { view in
            SavedViewEditor(view: view, viewModel: viewModel)
        }
        .confirmationDialog("Delete \(removing?.name ?? "view")?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Delete view", role: .destructive) {
                guard let id = removing?.id else { return }
                perform { try await viewModel.deleteView(id: id) }
                removing = nil
            }
        } message: { Text("Only this saved view is removed. Your PRs and triage marks are unchanged.") }
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        busy = true
        Task { defer { busy = false }; do { try await operation(); error = nil } catch { self.error = error.localizedDescription } }
    }
}

private struct SavedViewEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var view: SavedPRView
    @ObservedObject var viewModel: DashboardViewModel
    @State private var repositories = ""
    @State private var error: String?
    @State private var saving = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Saved view").font(.title2.weight(.semibold))
            Form {
                TextField("View name", text: $view.name).focused($nameFocused)
                    .accessibilityIdentifier("prpulse.view-name")
                Text("1–40 characters; unique within this account.").font(.caption).foregroundStyle(.secondary)
                TextField("Repositories (owner/repo, comma separated)", text: $repositories)
                Text("Leave empty to include all tracked repositories.").font(.caption).foregroundStyle(.secondary)
                Picker("PR state", selection: $view.stateRule) {
                    ForEach(SavedPRStateRule.allCases) { Text($0.rawValue).tag($0) }
                }
                TextField("Title or repository contains", text: $view.text)
                    .accessibilityIdentifier("prpulse.view-text")
                Toggle("Enabled", isOn: $view.enabled)
            }
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save view") {
                    view.repositories = repositories.split(separator: ",").map(String.init)
                    saving = true
                    Task {
                        defer { saving = false }
                        do { try await viewModel.saveView(view); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(24).frame(width: 520).disabled(saving)
        .onAppear { repositories = view.repositories.joined(separator: ", "); nameFocused = true }
    }
}
