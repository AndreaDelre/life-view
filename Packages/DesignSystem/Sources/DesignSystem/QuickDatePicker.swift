import SwiftUI

/// Compact date picker used by P5's new-task row.
///
/// Renders as a single short button (calendar icon + current-selection
/// label like "Auj.", "Demain", "16 mai", or "Date" when empty). Tap
/// opens a popover with four "good-enough" preset buttons plus a
/// graphical native ``DatePicker`` for arbitrary dates. The collapsed
/// shape stops the four presets from being squeezed mid-word into the
/// new-task row at typical panel widths.
///
/// Every date that flows out of this view goes through
/// ``QuickDatePresets/normalizeForDueDate(_:calendar:)`` so the
/// resulting `Date` is midnight UTC of the user's intended local day —
/// matching what the Google Tasks API expects for `due`.
public struct QuickDatePicker: View {
    @Binding private var date: Date?
    @State private var popoverOpen = false

    public init(date: Binding<Date?>) {
        _date = date
    }

    public var body: some View {
        Button {
            popoverOpen.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .imageScale(.small)
                Text(buttonLabel)
                    .font(.caption)
                    .lineLimit(1)
            }
            .foregroundStyle(date == nil ? Color.secondary : Color.primary)
        }
        .buttonStyle(.plain)
        .help("Date d'échéance")
        .accessibilityLabel("Date d'échéance")
        .popover(isPresented: $popoverOpen, arrowEdge: .bottom) {
            popoverContent
        }
    }

    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                presetButton("Aujourd'hui") {
                    date = QuickDatePresets.today()
                    popoverOpen = false
                }
                presetButton("Demain") {
                    date = QuickDatePresets.tomorrow()
                    popoverOpen = false
                }
                presetButton("Cette semaine") {
                    date = QuickDatePresets.endOfWeek()
                    popoverOpen = false
                }
            }
            HStack(spacing: 6) {
                presetButton("Aucune", emphasised: date == nil) {
                    date = nil
                    popoverOpen = false
                }
                Spacer(minLength: 0)
            }
            Divider()
            DatePicker(
                "",
                selection: customPickerBinding,
                displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.graphical)
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        // The graphical DatePicker expands to fill its container width;
        // pinning the popover width keeps the layout stable so the
        // calendar grid takes the whole available space instead of
        // hugging its intrinsic size on the leading edge.
        .frame(width: 280)
    }

    private var customPickerBinding: Binding<Date> {
        Binding(
            get: { date ?? QuickDatePresets.today() },
            // SwiftUI's graphical DatePicker emits a Date at midnight
            // **local**. Normalise to midnight UTC of the local day so
            // the wire format Google sees matches what the user picked.
            set: { date = QuickDatePresets.normalizeForDueDate($0) }
        )
    }

    private var buttonLabel: String {
        guard let date else { return "Date" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Auj." }
        if calendar.isDateInTomorrow(date) { return "Demain" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    private func presetButton(_ label: String, emphasised: Bool = false, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(emphasised ? Color.accentColor : Color.gray)
    }
}
