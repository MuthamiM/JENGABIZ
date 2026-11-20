import SwiftUI

struct Debtor: Identifiable {
    let id = UUID()
    let name: String
    let phone: String
    let debt: Double
    let trustScore: String
}

struct BalancesView: View {
    let sampleDebtors: [Debtor] = [
        Debtor(name: "Mama Brian", phone: "0712345678", debt: 1450.0, trustScore: "Good"),
        Debtor(name: "John Kamau", phone: "0722000111", debt: 820.0, trustScore: "Normal"),
        Debtor(name: "Baba Otis", phone: "0733445566", debt: 2300.0, trustScore: "Risky"),
    ]

    var body: some View {
        NavigationStack {
            List(sampleDebtors) { debtor in
                HStack {
                    VStack(alignment: .leading) {
                        Text(debtor.name)
                            .font(.headline)
                        Text("\(debtor.phone) • Hali: \(debtor.trustScore)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    Text(String(format: "KSh %.2f", debtor.debt))
                        .font(.headline)
                        .foregroundColor(.red)
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("Madeni ya Wateja")
        }
    }
}
