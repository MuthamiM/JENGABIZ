import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            CalculatorView()
                .tabItem {
                    Label("Mauzo", systemImage: "plus.forwardslash.minus")
                }
                .tag(0)

            BalancesView()
                .tabItem {
                    Label("Madeni", systemImage: "person.2.fill")
                }
                .tag(1)

            StockView()
                .tabItem {
                    Label("Stoo", systemImage: "shippingbox.fill")
                }
                .tag(2)

            SummaryView()
                .tabItem {
                    Label("Muhtasari", systemImage: "chart.bar.fill")
                }
                .tag(3)

            SettingsView()
                .tabItem {
                    Label("Mipangilio", systemImage: "gearshape.fill")
                }
                .tag(4)
        }
        .tint(Color(red: 0.0, green: 0.48, blue: 0.24)) // Kenyan Emerald
    }
}

struct StockView: View {
    var body: some View {
        NavigationStack {
            Text("Usimamizi wa Stoo / Stock Management")
                .navigationTitle("Stoo")
        }
    }
}

struct SummaryView: View {
    var body: some View {
        NavigationStack {
            Text("Muhtasari wa Siku / Daily Summary")
                .navigationTitle("Muhtasari")
        }
    }
}

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            Text("Mipangilio ya Duka / Settings")
                .navigationTitle("Mipangilio")
        }
    }
}
