import SwiftUI

private struct DemoCard: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let summary: String
    let detail: [DemoRow]
}

private struct DemoRow: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    var tint: Color = .secondary
}

@main
struct NotchAgentTesterApp: App {
    var body: some Scene {
        WindowGroup("AI Agent Card Tester") {
            TesterView()
                .frame(minWidth: 860, minHeight: 620)
        }
        .windowResizability(.contentSize)
    }
}

private struct TesterView: View {
    @State private var selected: DemoCard?
    @State private var period = "Today"

    private let cards: [DemoCard] = [
        DemoCard(id: "limits", title: "Limits", symbol: "gauge.with.dots.needle.33percent",
                 summary: "Session 62% left · Weekly 38% left",
                 detail: [
                    DemoRow(label: "Claude · Session", value: "62% remaining", tint: .orange),
                    DemoRow(label: "Claude · Weekly", value: "38% remaining", tint: .orange),
                    DemoRow(label: "Codex · 5-hour", value: "81% remaining", tint: .blue),
                    DemoRow(label: "Codex · Weekly", value: "54% remaining", tint: .blue),
                    DemoRow(label: "Next reset", value: "2h 18m"),
                    DemoRow(label: "Last checked", value: "34 seconds ago")
                 ]),
        DemoCard(id: "live", title: "Live", symbol: "waveform.path.ecg",
                 summary: "3 active sessions · 18m 42s",
                 detail: [
                    DemoRow(label: "Claude · storefront", value: "Opus 4.1 · 12m 08s", tint: .orange),
                    DemoRow(label: "Codex · api-refactor", value: "GPT-5 · 5m 54s", tint: .blue),
                    DemoRow(label: "OpenCode · docs", value: "Claude Sonnet · 0m 40s", tint: .green),
                    DemoRow(label: "Tokens", value: "Input 184K · Output 24.6K"),
                    DemoRow(label: "Estimated cost", value: "$3.84")
                 ]),
        DemoCard(id: "spend", title: "Spend", symbol: "dollarsign.circle",
                 summary: "$18.42 · 1.8M tokens · 27% cached",
                 detail: [
                    DemoRow(label: "Claude", value: "$8.92 · 812K tokens", tint: .orange),
                    DemoRow(label: "Codex", value: "$6.31 · 604K tokens", tint: .blue),
                    DemoRow(label: "OpenCode", value: "$3.19 · 332K tokens", tint: .green),
                    DemoRow(label: "GitHub Copilot", value: "≥ $0.00 · 91K tokens", tint: .teal),
                    DemoRow(label: "Cache savings", value: "$4.77"),
                    DemoRow(label: "Requests", value: "428")
                 ]),
        DemoCard(id: "trend", title: "Trend", symbol: "chart.bar.xaxis",
                 summary: "Peak 14:00 · $18.42 today",
                 detail: [
                    DemoRow(label: "09:00", value: "$1.12 · 108K tokens"),
                    DemoRow(label: "10:00", value: "$2.84 · 286K tokens"),
                    DemoRow(label: "11:00", value: "$0.64 · 52K tokens"),
                    DemoRow(label: "12:00", value: "$4.21 · 404K tokens", tint: .orange),
                    DemoRow(label: "13:00", value: "$3.77 · 351K tokens"),
                    DemoRow(label: "14:00", value: "$5.84 · 498K tokens", tint: .orange)
                 ]),
        DemoCard(id: "models", title: "Models", symbol: "cpu",
                 summary: "Opus 4.1 · GPT-5 · Sonnet",
                 detail: [
                    DemoRow(label: "Claude Opus 4.1", value: "$6.22 · 34%", tint: .orange),
                    DemoRow(label: "GPT-5", value: "$5.18 · 28%", tint: .blue),
                    DemoRow(label: "Claude Sonnet 4", value: "$3.44 · 19%", tint: .green),
                    DemoRow(label: "Gemini 2.5 Pro", value: "$2.31 · 12%"),
                    DemoRow(label: "Other models", value: "$1.27 · 7%")
                 ]),
        DemoCard(id: "projects", title: "Projects", symbol: "folder",
                 summary: "storefront · api · docs",
                 detail: [
                    DemoRow(label: "storefront", value: "$8.44 · 46%"),
                    DemoRow(label: "api-refactor", value: "$5.91 · 32%"),
                    DemoRow(label: "docs", value: "$2.84 · 15%"),
                    DemoRow(label: "dotfiles", value: "$1.23 · 7%")
                 ]),
        DemoCard(id: "activity", title: "Activity", symbol: "square.grid.3x3.fill",
                 summary: "18 active days · 6-day streak",
                 detail: [
                    DemoRow(label: "Today", value: "$18.42 · 428 requests", tint: .orange),
                    DemoRow(label: "Yesterday", value: "$11.08 · 263 requests"),
                    DemoRow(label: "Monday", value: "$7.64 · 189 requests"),
                    DemoRow(label: "Active days", value: "18 of 30"),
                    DemoRow(label: "Busiest day", value: "Today")
                 ]),
        DemoCard(id: "resets", title: "Resets", symbol: "arrow.counterclockwise.circle",
                 summary: "3 available · next expires tomorrow",
                 detail: [
                    DemoRow(label: "Available", value: "3", tint: .blue),
                    DemoRow(label: "Next expiry", value: "Tomorrow at 09:30"),
                    DemoRow(label: "Second expiry", value: "Friday at 16:00"),
                    DemoRow(label: "Account", value: "Codex · Personal"),
                    DemoRow(label: "Action", value: "Use reset requires confirmation")
                 ])
    ]

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AI Agent Card Tester").font(.system(size: 24, weight: .bold))
                        Text("Standalone fake-data preview — click any card to inspect its expanded reader.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("Period", selection: $period) {
                        Text("Today").tag("Today")
                        Text("This week").tag("This week")
                        Text("This month").tag("This month")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
                Text("Compact cards")
                    .font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 245), spacing: 12)], spacing: 12) {
                    ForEach(cards) { card in
                        Button { selected = card } label: {
                            compact(card)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer()
                Label("Click a card to open its expanded information view. Escape or Close returns here.",
                      systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(28)
            if let selected {
                expanded(selected)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onExitCommand { self.selected = nil }
    }

    private func compact(_ card: DemoCard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: card.symbol).foregroundStyle(Color.accentColor)
                Text(card.title).font(.headline)
                Spacer()
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(card.summary)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.accentColor.opacity(0.25))
                .frame(height: 5)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.08)))
    }

    private func expanded(_ card: DemoCard) -> some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { selected = nil }
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label(card.title, systemImage: card.symbol)
                        .font(.title2.bold())
                    Spacer()
                    Button("Close") { selected = nil }
                        .keyboardShortcut(.cancelAction)
                }
                Text("Expanded information")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(card.detail) { row in
                            HStack {
                                Text(row.label)
                                Spacer()
                                Text(row.value)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(row.tint)
                            }
                            .padding(.vertical, 5)
                            Divider()
                        }
                    }
                }
            }
            .padding(24)
            .frame(width: 520, height: 430)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .shadow(radius: 24)
        }
    }
}
