import Foundation
import Combine

class TradingBot: ObservableObject {
    @Published var running = false
    @Published var balance: Double = 0
    @Published var pnl: Double = 0
    @Published var log = ""
    @Published var symbol = "BTCUSDT"
    let symbols = ["BTCUSDT","ETHUSDT","SOLUSDT"]
    private var timer: Timer?
    private let minBalance: Double = 0
    private let maxRisk: Double = 0.02
    private var startBalance: Double = 0

    func start() {
        running = true
        log = "Started"
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in self.tick() }
        tick()
    }
    func stop() { running = false; timer?.invalidate(); timer = nil; log = "Stopped" }
    func switchSymbol() { log = "Switched to \(symbol)" }

    private func tick() {
        guard running else { return }
        // Safety: never below $0
        if balance < minBalance { stop(); log = "Safety stop: balance <= 0"; return }
        // Placeholder trade decision logic using market data would go here
        log = "Tick \(symbol) balance \(String(format:"%.2f",balance))"
    }
}
