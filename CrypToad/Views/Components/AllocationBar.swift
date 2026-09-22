import SwiftUI

struct AllocationBar: View {
    let label: String
    let percentage: Int
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.gray)
                Spacer()
                Text("\(percentage)%")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.gray)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(red: 0.26, green: 0.26, blue: 0.28))
                        .frame(height: 8)
                        .cornerRadius(4)

                    Rectangle()
                        .fill(color)
                        .frame(width: geometry.size.width * CGFloat(percentage) / 100, height: 8)
                        .cornerRadius(4)
                }
            }
            .frame(height: 8)
        }
    }
}
