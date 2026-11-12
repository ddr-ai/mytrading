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
    private var volumes: [Double] = []
    private let maxRisk: Double = 0.02
    private let maxDrawdown: Double = 0.10
    private var position: Double = 0
    private var entryPrice: Double = 0
    private var startBalance: Double = 100
    private var peakBalance: Double = 100
    private var consecutiveLosses = 0
    private let maxConsecutiveLosses = 3
    
    func start() {
        running = true
        startBalance = balance
        peakBalance = balance
        log = "Started (Gemini NYC) - Safety: maxRisk=2%, maxDD=10%"
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in self.tick() }
        tick()
    }
    
    func stop() { 
        running = false 
        timer?.invalidate(); timer = nil 
        log = "Stopped manually" 
    }
    
    func switchSymbol() { 
        prices = []; volumes = []; position = 0; entryPrice = 0
        consecutiveLosses = 0
        log = "Switched to \(symbol)" 
    }

    private func tick() {
        guard running else { return }
        
        // Hard safety: never below zero
        if balance <= 0 { 
            stop(); log = "🛑 SAFETY: Balance ≤ $0 — STOPPED"; return 
        }
        
        // Drawdown safety
        if balance > peakBalance { peakBalance = balance }
        let dd = (peakBalance - balance) / peakBalance
        if dd >= maxDrawdown {
            stop(); log = "🛑 SAFETY: Max drawdown \(Int(maxDrawdown*100))% hit — STOPPED"; return
        }
        
        // Consecutive loss safety
        if consecutiveLosses >= maxConsecutiveLosses {
            stop(); log = "🛑 SAFETY: \(maxConsecutiveLosses) consecutive losses — STOPPED"; return
        }
        
        // Fetch market data
        let group = DispatchGroup()
        var currentPrice: Double?
        var currentVolume: Double?
        var orderBook: [String: Any]?
        
        group.enter()
        GeminiClient.price(symbol: symbol) { p in currentPrice = p; group.leave() }
        group.enter()
        GeminiClient.trades(symbol: symbol) { trades in
            if let trades = trades {
                currentVolume = trades.compactMap { $0["amount"] as? String }.compactMap(Double.init).reduce(0, +)
            }
            group.leave()
        }
        group.enter()
        GeminiClient.orderBook(symbol: symbol) { ob in orderBook = ob; group.leave() }
        
        group.notify(queue: .main) {
            guard let price = currentPrice, let volume = currentVolume else { 
                self.log = "⚠️ Data fetch failed"; return 
            }
            self.prices.append(price)
            self.volumes.append(volume)
            if self.prices.count > 100 { self.prices.removeFirst() }
            if self.volumes.count > 100 { self.volumes.removeFirst() }
            self.analyzeAndDecide(price: price, volume: volume, orderBook: orderBook)
        }
    }

    private func analyzeAndDecide(price: Double, volume: Double, orderBook: [String: Any]?) {
        guard prices.count >= 20 else { log = "📊 Warming up (\(prices.count)/20)"; return }
        
        // Multi-timeframe EMAs
        let ema9 = prices.suffix(9).reduce(0,+) / 9.0
        let ema20 = prices.suffix(20).reduce(0,+) / 20.0
        
        // RSI (14)
        let rsi = calculateRSI(period: 14)
        
        // Volume analysis
        let avgVol = volumes.suffix(20).reduce(0,+) / 20.0
        let volRatio = volume / max(avgVol, 1)
        
        // Order book imbalance (bid/ask pressure)
        var bookImbalance = 0.0
        if let ob = orderBook,
           let bids = ob["bids"] as? [[String: String]],
           let asks = ob["asks"] as? [[String: String]] {
            let bidVol = bids.prefix(10).compactMap { Double($0[1]) }.reduce(0, +)
            let askVol = asks.prefix(10).compactMap { Double($0[1]) }.reduce(0, +)
            if bidVol + askVol > 0 { bookImbalance = (bidVol - askVol) / (bidVol + askVol) }
        }
        
        // Trend detection
        let trendUp = price > ema9 && ema9 > ema20
        let trendDown = price < ema9 && ema9 < ema20
        
        // Momentum
        let momentum = prices.count >= 5 ? (price - prices[prices.count-5]) / prices[prices.count-5] : 0
        
        // Risk-adjusted position size
        let riskAmount = min(balance * maxRisk, balance * 0.5) // cap at 50% of balance
        
        // Decision logic with confirmations
        let buySignal = trendUp && rsi < 70 && volRatio > 0.5 && bookImbalance > -0.3 && momentum > -0.005
        let sellSignal = position > 0 && (trendDown || rsi > 80 || momentum < -0.01)
        
        let signalDesc = "EMA9:\(String(format:"%.0f",ema9)) EMA20:\(String(format:"%.0f",ema20)) RSI:\(String(format:"%.0f",rsi)) Vol:\(String(format:"%.1fx",volRatio)) Book:\(String(format:"%.2f",bookImbalance)) Mom:\(String(format:"%.3f",momentum))"
        
        if buySignal && position <= 0 && riskAmount > 10 { // min $10 order
            position = riskAmount / price
            entryPrice = price
            balance -= riskAmount
            log = "🟢 BUY \(symbol) @ $\(String(format:"%.2f",price)) | Qty:\(String(format:"%.6f",position)) | \(signalDesc)"
            executeBuy(price: price, riskAmount: riskAmount)
        } else if sellSignal && position > 0 {
            let proceeds = position * price
            let tradePnl = proceeds - (position * entryPrice)
            log = "🔴 SELL \(symbol) @ $\(String(format:"%.2f",price)) | PnL:$\(String(format:"%.2f",tradePnl)) | \(signalDesc)"
            executeSell(price: price, proceeds: proceeds)
        } else {
            log = "⏸ HOLD \(symbol) @ $\(String(format:"%.2f",price)) | Pos:$\(String(format:"%.2f",position*price)) | \(signalDesc)"
        }
    }
    
    private func calculateRSI(period: Int) -> Double {
        guard prices.count > period else { return 50 }
        var gains = 0.0, losses = 0.0
        for i in (prices.count-period)..<prices.count {
            let change = prices[i] - prices[i-1]
            if change > 0 { gains += change } else { losses -= change }
        }
        let avgGain = gains / Double(period)
        let avgLoss = losses / Double(period)
        if avgLoss == 0 { return 100 }
        let rs = avgGain / avgLoss
        return 100 - (100 / (1 + rs))
    }
    
    private func executeBuy(price: Double, riskAmount: Double) {
        GeminiClient.marketOrder(symbol: symbol, side: "BUY", amount: riskAmount / price, apiKey: apiKey, secret: secret) { [weak self] ok, msg in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if ok {
                    self.log = "✅ BUY filled \(self.symbol) @ $\(String(format:"%.2f",price))"
                } else {
                    self.balance += riskAmount // refund on failure
                    self.position = 0
                    self.log = "❌ BUY failed: \(msg ?? "unknown") — refunded"
                }
            }
        }
    }
    
    private func executeSell(price: Double, proceeds: Double) {
        GeminiClient.marketOrder(symbol: symbol, side: "SELL", amount: position, apiKey: apiKey, secret: secret) { [weak self] ok, msg in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if ok {
                    let tradePnl = proceeds - (self.position * self.entryPrice)
                    self.balance += proceeds
                    self.pnl += tradePnl
                    self.position = 0
                    self.entryPrice = 0
                    if tradePnl < 0 { self.consecutiveLosses += 1 } else { self.consecutiveLosses = 0 }
                    self.log = "✅ SELL filled \(self.symbol) @ $\(String(format:"%.2f",price)) | PnL:$\(String(format:"%.2f",tradePnl))"
                } else {
                    self.log = "❌ SELL failed: \(msg ?? "unknown") — position retained"
                }
            }
        }
    }
}
