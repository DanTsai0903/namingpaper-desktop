import SwiftUI

struct DropZoneOverlay: View {
    var body: some View {
        ZStack {
            Color.accentColor.opacity(0.1)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accentColor)

                Text("Drop PDFs to add to library")
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.accentColor)
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10]))
            )
        }
        .allowsHitTesting(false)
    }
}
