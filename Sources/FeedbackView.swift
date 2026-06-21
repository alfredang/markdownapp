import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Feedback tab — Title + Message → opens WhatsApp (Tertiary Infotech house style).
struct FeedbackView: View {
    private let whatsAppNumber = "6588666375"   // +65 8866 6375, no "+"/spaces

    @State private var title = ""
    @State private var message = ""

    private var canSend: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Feedback").font(.largeTitle.bold())
                Text("Tell us what you love or what could be better.")
                    .foregroundStyle(Theme.mutedInk)

                VStack(alignment: .leading, spacing: 14) {
                    Text("TITLE").font(.caption.weight(.semibold)).foregroundStyle(Theme.mutedInk)
                    TextField("Short summary", text: $title)
                        .textFieldStyle(.roundedBorder)

                    Text("MESSAGE").font(.caption.weight(.semibold)).foregroundStyle(Theme.mutedInk)
                    ZStack(alignment: .topLeading) {
                        if message.isEmpty {
                            Text("Your message…")
                                .foregroundStyle(Theme.mutedInk)
                                .padding(.top, 8).padding(.leading, 5)
                        }
                        TextEditor(text: $message)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 160)
                    }
                    .padding(8)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .appCard()

                Button(action: send) {
                    Label("Send via WhatsApp", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSend)
            }
            .padding(22)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
    }

    private func send() {
        var body = ""
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let m = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { body += "*\(t)*\n" }
        body += m

        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "wa.me"
        comps.path = "/\(whatsAppNumber)"
        comps.queryItems = [URLQueryItem(name: "text", value: body)]
        guard let url = comps.url else { return }
        #if canImport(UIKit)
        UIApplication.shared.open(url)
        #elseif canImport(AppKit)
        NSWorkspace.shared.open(url)
        #endif
    }
}
