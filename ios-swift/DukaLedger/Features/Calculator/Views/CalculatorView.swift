import SwiftUI

struct QuickItem: Identifiable {
    let id = UUID()
    let name: String
    let price: Double
}

struct CalculatorView: View {
    @State private var runningTotal: Double = 0.0
    @State private var showingConfirmation = false
    @State private var saleType = "Cash"

    let quickItems: [QuickItem] = [
        QuickItem(name: "Sukuma (Fungu)", price: 20.0),
        QuickItem(name: "Nyanya (3pcs)", price: 50.0),
        QuickItem(name: "Kitunguu (Fungu)", price: 30.0),
        QuickItem(name: "Maziwa Mala 500ml", price: 65.0),
        QuickItem(name: "Mkate Broadways", price: 65.0),
        QuickItem(name: "Kiberiti Matchbox", price: 5.0)
    ]

    var body: some View {
        NavigationStack {
            VStack {
                // Running Total Header
                VStack(alignment: .trailing) {
                    Text("JUMLA / RUNNING TOTAL")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text(String(format: "KSh %.2f", runningTotal))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundColor(.green)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding()
                .background(Color.green.opacity(0.1))

                // Quick tap grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(quickItems) { item in
                        Button(action: { runningTotal += item.price }) {
                            VStack {
                                Text(item.name)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text(String(format: "KSh %.2f", item.price))
                                    .font(.subheadline)
                                    .foregroundColor(.green)
                            }
                            .frame(maxWidth: .infinity, minHeight: 70)
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }
                    }
                }
                .padding()

                Spacer()

                // Actions: Cash vs Credit
                HStack(spacing: 16) {
                    Button(action: {
                        saleType = "Cash"
                        showingConfirmation = true
                    }) {
                        Text("PESA TASLIMU\n(Cash Sale)")
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 60)
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }

                    Button(action: {
                        saleType = "Credit"
                        showingConfirmation = true
                    }) {
                        Text("WEKA KWA DENI\n(Put on Credit)")
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 60)
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                }
                .padding()
            }
            .navigationTitle("Kikokotoo")
            .alert("Thibitisha Mauzo", isPresented: $showingConfirmation) {
                Button("Ghairi", role: .cancel) { }
                Button("Thibitisha") {
                    runningTotal = 0.0
                }
            } message: {
                Text(String(format: "Uza kwa %@: KSh %.2f", saleType, runningTotal))
            }
        }
    }
}
