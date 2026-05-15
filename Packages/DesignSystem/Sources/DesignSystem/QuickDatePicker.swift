import SwiftUI

/// Compact date picker used by P5's new-task row. Offers four
/// "good-enough" presets that cover most quick-capture cases and a
/// disclosed native ``DatePicker`` for arbitrary dates.
///
/// `Binding<Date?>` rather than `Binding<Date>` because "no due date"
/// is a first-class option, not a sentinel value.
public struct QuickDatePicker: View {
    @Binding private var date: Date?
    @State private var customPickerOpen = false

    public init(date: Binding<Date?>) {
        _date = date
    }

    public var body: some View {
        HStack(spacing: 4) {
            presetButton(label: "Auj.") { date = QuickDatePresets.today() }
            presetButton(label: "Demain") { date = QuickDatePresets.tomorrow() }
            presetButton(label: "Cette sem.") { date = QuickDatePresets.endOfWeek() }
            presetButton(label: "Aucune", emphasised: date == nil) { date = nil }

            Button {
                customPickerOpen.toggle()
            } label: {
                Image(systemName: "calendar")
                    .imageScale(.small)
            }
            .buttonStyle(.plain)
            .help("Choisir une date")
            .popover(isPresented: $customPickerOpen, arrowEdge: .bottom) {
                DatePicker(
                    "",
                    selection: Binding(
                        get: { date ?? QuickDatePresets.today() },
                        set: { date = $0 }
                    ),
                    displayedComponents: .date
                )
                .labelsHidden()
                .datePickerStyle(.graphical)
                .padding(8)
            }
        }
        .font(.caption)
    }

    private func presetButton(label: String, emphasised: Bool = false, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(emphasised ? Color.accentColor.opacity(0.15) : .clear)
            )
    }
}
