import SwiftUI

extension View {
    /// Unlocks an encrypted backup once `backup` is set: asks for its passphrase
    /// in an alert (again, with the reason, after a wrong one), or opens it with
    /// this device's backup key when it was sealed with that. Hands the plaintext
    /// payload to `onUnlock` and clears `backup` either way.
    func backupPassphraseAlert(
        for backup: Binding<BackupFileImport.LockedBackup?>,
        onUnlock: @escaping (Data) -> Void,
    ) -> some View {
        modifier(BackupPassphraseAlert(backup: backup, onUnlock: onUnlock))
    }
}

private struct BackupPassphraseAlert: ViewModifier {
    @Binding var backup: BackupFileImport.LockedBackup?
    let onUnlock: (Data) -> Void

    @State private var passphrase = ""
    @State private var showingPrompt = false
    /// Why the last passphrase didn't open the backup, shown when the prompt returns.
    @State private var promptFailure: String?
    /// Why a backup sealed with a device key didn't open.
    @State private var keyFailure: String?

    func body(content: Content) -> some View {
        content
            .onChange(of: backup?.id) { _, id in
                guard id != nil, let backup else { return }
                if backup.needsPassphrase {
                    showingPrompt = true
                } else {
                    unlock(backup, passphrase: nil)
                }
            }
            .alert("Enter Passphrase", isPresented: $showingPrompt) {
                SecureField("Passphrase", text: $passphrase)
                #if canImport(UIKit)
                    .textContentType(.password)
                #endif
                Button("Cancel", role: .cancel) { finish() }
                Button("Unlock") {
                    if let backup { unlock(backup, passphrase: passphrase) }
                }
                .disabled(passphrase.isEmpty)
            } message: {
                Text(promptFailure ?? String(localized: "This backup is encrypted. Enter the passphrase it was made with."))
            }
            .alert("Restore Failed", isPresented: keyFailureBinding, presenting: keyFailure) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
    }

    private var keyFailureBinding: Binding<Bool> {
        Binding(get: { keyFailure != nil }, set: { if !$0 { keyFailure = nil } })
    }

    private func unlock(_ locked: BackupFileImport.LockedBackup, passphrase: String?) {
        Task {
            do {
                let plaintext = try await BackupFileImport.unlock(locked, passphrase: passphrase)
                finish()
                onUnlock(plaintext)
            } catch {
                if locked.needsPassphrase {
                    self.passphrase = ""
                    promptFailure = error.localizedDescription
                    showingPrompt = true
                } else {
                    finish()
                    keyFailure = error.localizedDescription
                }
            }
        }
    }

    private func finish() {
        backup = nil
        passphrase = ""
        promptFailure = nil
    }
}
