import Foundation
import Combine

class TradingBot: ObservableObject {
    @Published var running = false
    @Published var balance: Double = 100
    @Published var pnl: Double = 0
    @Published var log = ""
    @Published var symbol = "BTCUSDT"
    var apiKey = ""
    var secret = ""
    let symbols = ["BTCUSDT","ETHUSDT","SOLUSDT"]
    private var timer: Timer?
    private var prices: [Double] = []
    private let maxRisk: Double = 0.02
    private var position: Double = 0

    func start() { running = true; log = "Started"; timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in self.tick() }; tick() }
    func stop() { running = false; timer?.invalidate(); timer = nil; log = "Stopped" }
    func switchSymbol() { prices = []; position = 0; log = "Switched to \(symbol)" }

    private func tick() {
        guard running else { return }
        if balance <= 0 { stop(); log = "Safety stop: balance <= 0"; return }
        BinanceClient.price(symbol: symbol) { [weak self] p in
            guard let self = self, let p = p else { return }
            DispatchQueue.main.async {
                self.prices.append(p)
                if self.prices.count > 50 { self.prices.removeFirst() }
                self.decide(price: p)
            }
        }
    }

    private func decide(price: Double) {
        guard prices.count >= 10 else { log = "Warming up"; return }
        let ema = prices.suffix(10).reduce(0,+) / 10.0
        let trendUp = price > ema
        let riskAmount = balance * maxRisk
        if trendUp && position <= 0 && riskAmount > 0 {
            let qty = riskAmount
            position = qty / price
            balance -= riskAmount
            BinanceClient.marketOrder(symbol: symbol, side: "BUY", quoteQty: riskAmount, apiKey: apiKey, secret: secret) { ok in
                DispatchQueue.main.async { self.log = ok ? "Buy \(self.symbol) @ \(price)" : "Buy failed" }
            }
        } else if !trendUp && position > 0 {
            let proceeds = position * price
            BinanceClient.marketOrder(symbol: symbol, side: "SELL", quoteQty: proceeds, apiKey: apiKey, secret: secret) { ok in
                DispatchQueue.main.async { self.log = ok ? "Sell \(self.symbol) @ \(price)" : "Sell failed" }
            }
            balance += proceeds
            pnl += (price - (prices.first ?? price)) * position
            position = 0
        } else {
            log = "Hold \(symbol) @ \(price)"
        }
        if balance < 0 { balance = 0; stop(); log = "Safety: clamped to 0" }
    }
}
