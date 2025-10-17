import SwiftUI

struct FeedbackSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: String = "content_quality"
    @State private var message: String = ""
    @State private var email: String = ""
    @State private var includeDiagnostics: Bool = true
    let onCancel: () -> Void
    let onSubmit: (_ category: String, _ message: String?, _ email: String?, _ includeDiagnostics: Bool) -> Void
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("What could be better?")) {
                    Picker("Category", selection: $selectedCategory) {
                        Text("Audio").tag("audio_issue")
                        Text("Content").tag("content_quality")
                        Text("Scheduling").tag("scheduling")
                        Text("Other").tag("other")
                    }
                    .pickerStyle(.segmented)
                }
                Section(header: Text("Tell us more (optional)")) {
                    TextEditor(text: $message)
                        .frame(minHeight: 120)
                }
                Section(header: Text("Contact (optional)")) {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                Section {
                    Toggle("Include diagnostics", isOn: $includeDiagnostics)
                }
            }
            .navigationTitle("Feedback")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        onSubmit(selectedCategory, message.isEmpty ? nil : message, email.isEmpty ? nil : email, includeDiagnostics)
                        dismiss()
                    }
                }
            }
        }
    }
}