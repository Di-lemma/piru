import SwiftUI

// The system share sheet for `items`, presented from a `.sheet`.
#if canImport(UIKit)
    import UIKit

    struct ShareSheet: UIViewControllerRepresentable {
        let items: [Any]

        func makeUIViewController(context _: Context) -> UIActivityViewController {
            UIActivityViewController(activityItems: items, applicationActivities: nil)
        }

        func updateUIViewController(_: UIActivityViewController, context _: Context) {}
    }

#elseif canImport(AppKit)
    import AppKit

    struct ShareSheet: NSViewRepresentable {
        let items: [Any]

        func makeCoordinator() -> Coordinator {
            Coordinator()
        }

        func makeNSView(context _: Context) -> NSView {
            NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            guard !context.coordinator.presented else { return }
            context.coordinator.presented = true
            DispatchQueue.main.async {
                let picker = NSSharingServicePicker(items: items)
                picker.show(relativeTo: nsView.bounds, of: nsView, preferredEdge: .minY)
            }
        }

        final class Coordinator {
            var presented = false
        }
    }
#endif
