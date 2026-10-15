import SwiftUI

struct SettingsView: View {
    @Binding var hasAPIKey: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var keyInput: String = ""
    @State private var showSavedBadge = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Settings")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Groq API Key")
                    .font(.system(size: 13, weight: .semibold))

                Text("Scribe uses your own Groq API key to transcribe and summarize audio. Get one free at console.groq.com/keys.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                SecureField("gsk_...", text: $keyInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))

                if hasAPIKey {
                    Text("A key is currently saved on this Mac.")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                }
            }

            HStack {
                if showSavedBadge {
                    Text("Saved")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.green)
                        .transition(.opacity)
                }
                Spacer()

                if hasAPIKey {
                    Button("Remove Key") {
                        KeychainStore.clear()
                        hasAPIKey = false
                        keyInput = ""
                    }
                    .foregroundStyle(.red)
                }

                Button("Save") {
                    let trimmed = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    KeychainStore.save(trimmed)
                    hasAPIKey = true
                    withAnimation { showSavedBadge = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        withAnimation { showSavedBadge = false }
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
