import Foundation
import CryptoKit

// Bitstamp - BitLicense, Luxembourg CSSF, available in NYC, 24/7 trading
struct BitstampClient {
    static let base = "https://www.bitstamp.net/api/v2"
    
    static func price(symbol: String, completion: @escaping (Double?) -> Void) {
        // Convert BTCUSDT -> btcusd
        let pair = symbol.lowercased().replacingOccurrences(of: "usdt", with: "usd")
        guard let url = URL(string: "\(base)/ticker/\(pair)/") else { completion(nil); return }
        URLSession.shared.dataTask(with: url) { data,_,_ in
            guard let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let p = obj["last"] as? String,
                  let price = Double(p) else { completion(nil); return }
            completion(price)
        }.resume()
    }
    
    static func marketOrder(symbol: String, side: String, amount: Double, apiKey: String, secret: String, completion: @escaping (Bool) -> Void) {
        let pair = symbol.lowercased().replacingOccurrences(of: "usdt", with: "usd")
        let ts = String(Int(Date().timeIntervalSince1970 * 1000))
        let nonce = String(Int.random(in: 100000...999999))
        
        let body = "nonce=\(nonce)&amount=\(String(format: "%.8f", amount))"
        let payload = "\(ts)\(nonce)\(apiKey)\(body)"
        
        let keyData = Data(base64Encoded: secret) ?? Data(secret.utf8)
        let key = SymmetricKey(data: keyData)
        let sig = HMAC<SHA256>.authenticationCode(for: Data(payload.utf8), using: key)
            .map { String(format: "%02x", $0) }.joined().uppercased()
        
        guard let url = URL(string: "\(base)/\(side.lowercased())/\(pair)/") else { completion(false); return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = body.data(using: .utf8)
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "X-Auth")
        req.setValue(sig, forHTTPHeaderField: "X-Signature")
        req.setValue(ts, forHTTPHeaderField: "X-Nonce")
        
        URLSession.shared.dataTask(with: req) { _,resp,_ in
            let ok = (resp as? HTTPURLResponse)?.statusCode == 200
            completion(ok)
        }.resume()
    }
}
