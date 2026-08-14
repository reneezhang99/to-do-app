import SwiftUI
import TootShared

/// One sticky's face, as it appears in the home stack — a read-only preview
/// (real editing happens in `MobileStickyDetailView`, opened by tapping
/// this). Same paper/ink/title language as the Mac app so a sticky looks
/// like the same sticky on both devices.
struct MobileStickyCardView: View {
    let data: StickyData
    var cornerRadius: CGFloat = 20

    private var color: StickyColor { data.colorID }
    private var visibleItems: [TodoItem] { data.items.filter { !$0.text.isEmpty } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Self.dateFormatter.string(from: data.day))
                .font(.system(size: 13))
                .foregroundStyle(color.ink.opacity(0.35))

            Text(data.title.isEmpty ? "To Do" : data.title)
                .font(.custom("HelveticaNeue", size: 30))
                .tracking(30 * -0.06)
                .foregroundStyle(color.titleInk)
                .lineLimit(2)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(visibleItems.prefix(6)) { item in
                    row(item)
                }
            }
            .padding(.top, 6)

            if visibleItems.count > 6 {
                Text("+ \(visibleItems.count - 6) more")
                    .font(.system(size: 12))
                    .foregroundStyle(color.ink.opacity(0.4))
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(color.paper, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private func row(_ item: TodoItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                if item.isDone {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(color.ink.opacity(0.3))
                        .frame(width: 14, height: 14)
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(color.paper)
                } else {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .stroke(color.ink.opacity(0.3), lineWidth: 1.1)
                        .frame(width: 14, height: 14)
                }
            }
            .padding(.top, 2)
            Text(item.text)
                .font(.system(size: 15))
                .foregroundStyle(item.isDone ? color.inkSecondary : color.ink.opacity(0.85))
                .strikethrough(item.isDone, color: color.inkSecondary)
                .lineLimit(2)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()
}
