import SwiftUI

struct ContentView: View {
    @StateObject var bot = TradingBot()
    @State var apiKey = ""
    @State var secret = ""
    var body: some View {
        VStack(spacing: 16) {
            Text("Live Trading Bot").font(.title)
            Text("Platform: Binance (free, 24/7)").font(.caption)
            Text("Asset: \(bot.symbol)").font(.headline)
            Text("Balance: $\(String(format: "%.2f", bot.balance))")
            Text("Status: \(bot.running ? "Running" : "Stopped")")
            Text("PnL: $\(String(format: "%.2f", bot.pnl))")
            HStack {
                Button("Start") { bot.apiKey = apiKey; bot.secret = secret; bot.start() }.buttonStyle(.borderedProminent)
                Button("Stop") { bot.stop() }.buttonStyle(.bordered)
            }
            Picker("Symbol", selection: $bot.symbol) {
                ForEach(bot.symbols, id: \.self) { s in Text(s) }
            }.pickerStyle(.segmented).onChange(of: bot.symbol) { _ in bot.switchSymbol() }
            SecureField("Binance API Key", text: $apiKey)
            SecureField("Binance Secret", text: $secret)
            Text(bot.log).font(.caption).lineLimit(10)
        }.padding()
    }
}
