import Foundation
import CryptoKit

// Coinbase Advanced Trade API - regulated, BitLicense, available in NYC
struct CoinbaseClient {
    static let base = "https://api.coinbase.com/api/v3/brokerage"
    
    static func price(productId: String, completion: @escaping (Double?) -> Void) {
        // Convert BTCUSDT -> BTC-USD
        let pair = productId.replacingOccurrences(of: "USDT", with: "-USD")
            .replacingOccurrences(of: "BTC", with: "BTC")
            .replacingOccurrences(of: "ETH", with: "ETH")
            .replacingOccurrences(of: "SOL", with: "SOL")
        guard let url = URL(string: "\(base)/products/\(pair)/ticker") else { completion(nil); return }
        URLSession.shared.dataTask(with: url) { data,_,_ in
            guard let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let p = obj["price"] as? String,
                  let price = Double(p) else { completion(nil); return }
            completion(price)
        }.resume()
    }
    
    static func marketOrder(productId: String, side: String, quoteSize: Double, apiKey: String, secret: String, completion: @escaping (Bool) -> Void) {
        let pair = productId.replacingOccurrences(of: "USDT", with: "-USD")
        let ts = String(Int(Date().timeIntervalSince1970))
        let body = ["product_id": pair, "side": side.lowercased(), "order_configuration": ["market_market_ioc": ["quote_size": String(format: "%.2f", quoteSize)]]]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { completion(false); return }
        
        let method = "POST"
        let path = "/api/v3/brokerage/orders"
        let payload = ts + method + path + String(data: bodyData, encoding: .utf8)!
        
        let keyData = Data(base64Encoded: secret) ?? Data(secret.utf8)
        let key = SymmetricKey(data: keyData)
        let sig = HMAC<SHA256>.authenticationCode(for: Data(payload.utf8), using: key)
            .map { String(format: "%02x", $0) }.joined()
        
        guard let url = URL(string: "\(base)/orders") else { completion(false); return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = bodyData
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "CB-ACCESS-KEY")
        req.setValue(sig, forHTTPHeaderField: "CB-ACCESS-SIGN")
        req.setValue(ts, forHTTPHeaderField: "CB-ACCESS-TIMESTAMP")
        req.setValue("v3", forHTTPHeaderField: "CB-VERSION")
        
        URLSession.shared.dataTask(with: req) { _,resp,_ in
            let ok = (resp as? HTTPURLResponse)?.statusCode == 200 || (resp as? HTTPURLResponse)?.statusCode == 201
            completion(ok)
        }.resume()
    }
}
