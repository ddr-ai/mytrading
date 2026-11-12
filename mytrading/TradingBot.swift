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

    func start() { running = true; log = "Started (Bitstamp NYC)"; timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in self.tick() }; tick() }
    func stop() { running = false; timer?.invalidate(); timer = nil; log = "Stopped" }
    func switchSymbol() { prices = []; position = 0; log = "Switched to \(symbol)" }

    private func tick() {
        guard running else { return }
        if balance <= 0 { stop(); log = "Safety stop: balance <= 0"; return }
        BitstampClient.price(symbol: symbol) { [weak self] p in
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
            position = riskAmount / price
            balance -= riskAmount
            BitstampClient.marketOrder(symbol: symbol, side: "BUY", amount: riskAmount / price, apiKey: apiKey, secret: secret) { ok in
                DispatchQueue.main.async { self.log = ok ? "Buy \(self.symbol) @ \(price) (Bitstamp)" : "Buy failed" }
            }
        } else if !trendUp && position > 0 {
            let proceeds = position * price
            BitstampClient.marketOrder(symbol: symbol, side: "SELL", amount: position, apiKey: apiKey, secret: secret) { ok in
                DispatchQueue.main.async { self.log = ok ? "Sell \(self.symbol) @ \(price) (Bitstamp)" : "Sell failed" }
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
