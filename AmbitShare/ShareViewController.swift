import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Receives a link or text from the share sheet and leaves it for Ambit to import.
private enum ShareOutcome {
    case saved
    case failed(String)

    var isSaved: Bool { if case .saved = self { true } else { false } }
    var message: String {
        switch self {
        case .saved: "Saved to Ambit. Open Ambit to review and import it."
        case .failed(let reason): reason
        }
    }
}

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        Task { await handle() }
    }

    private func handle() async {
        let outcome = await save()
        show(outcome)
        try? await Task.sleep(for: .seconds(outcome.isSaved ? 1.4 : 2.5))
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func save() async -> ShareOutcome {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }

        // Prefer a real URL (Safari shares the page address), then plain text.
        for type in [UTType.url, UTType.plainText] {
            for provider in providers where provider.hasItemConformingToTypeIdentifier(type.identifier) {
                guard let loaded = try? await provider.loadItem(forTypeIdentifier: type.identifier) else { continue }
                let string = (loaded as? URL)?.absoluteString ?? (loaded as? String)
                guard let string, let item = SharedInbox.item(forShared: string) else { continue }
                return SharedInbox.add(item)
                    ? .saved
                    : .failed("Ambit's shared storage isn't available. Open Ambit once and try again.")
            }
        }
        return .failed("Ambit can only import links and text.")
    }

    private func show(_ outcome: ShareOutcome) {
        let host = UIHostingController(rootView: ResultView(outcome: outcome.message, success: outcome.isSaved))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.backgroundColor = .clear
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}

private struct ResultView: View {
    let outcome: String
    let success: Bool

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(success ? .green : .orange)
            Text(outcome)
                .font(.headline)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: 320)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
