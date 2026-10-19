import SwiftUI

enum AppTheme {
    static let ink = Color(red: 0.10, green: 0.14, blue: 0.22)
    static let muted = Color(red: 0.43, green: 0.48, blue: 0.56)
    static let canvas = Color(red: 0.96, green: 0.97, blue: 0.98)
    static let accent = Color(red: 0.28, green: 0.39, blue: 0.91)
    static let mint = Color(red: 0.17, green: 0.66, blue: 0.55)
}

struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if let icon { Image(systemName: icon) }
                Text(title).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .foregroundStyle(.white)
            .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
    }
}

struct SectionHeading: View {
    let title: String
    var trailing: String? = nil
    var body: some View {
        HStack {
            Text(title).font(.system(size: 19, weight: .bold, design: .rounded)).foregroundStyle(AppTheme.ink)
            Spacer()
            if let trailing { Text(trailing).font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.accent) }
        }
    }
}

