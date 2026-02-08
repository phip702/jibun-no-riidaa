import SwiftUI

struct LookupsView: View {

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Lookups")
                    .font(.largeTitle)
                    .bold()
                Text("Search and lookup resources")
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding()
            .navigationTitle("Lookups")
        }
    }

}

#Preview {
    LookupsView()
}
