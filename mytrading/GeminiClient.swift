import Foundation
import CryptoKit

// Gemini - NYDFS BitLicense, NYC-based, 24/7 trading, low minimums
struct GeminiClient {
    static let base = "https://api.gemini.com"
    
    static func price(symbol: String, completion: @escaping (Double?) -> Void) {
        // Convert BTCUSDT -> btcusd
        let pair = symbol.lowercased().replacingOccurrences(of: "usdt", with: "usd")
        guard let url = URL(string: "\(base)/v1/pubticker/\(pair)") else { completion(nil); return }
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
        let nonce = String(Int(Date().timeIntervalSince1970 * 1000000))
        
        let payload: [String: Any] = [
            "request": "/v1/order/new",
            "nonce": nonce,
            "symbol": pair,
            "amount": String(format: "%.8f", amount),
            "price": "1", // market order uses price=1
            "side": side.lowercased(),
            "type": "exchange market",
            "options": ["immediate-or-cancel"]
        ]
        
        guard let payloadData = try? JSONSerialization.data(withJSONObject: payload),
              let payloadB64 = payloadData.base64EncodedString().data(using: .utf8) else { completion(false); return }
        
        let keyData = Data(base64Encoded: secret) ?? Data(secret.utf8)
        let key = SymmetricKey(data: keyData)
        let sig = HMAC<SHA384>.authenticationCode(for: payloadB64, using: key)
            .map { String(format: "%02x", $0) }.joined()
        
        guard let url = URL(string: "\(base)/v1/order/new") else { completion(false); return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        req.setValue("0", forHTTPHeaderField: "Content-Length")
        req.setValue(apiKey, forHTTPHeaderField: "X-GEMINI-APIKEY")
        req.setValue(payloadB64.base64EncodedString(), forHTTPHeaderField: "X-GEMINI-PAYLOAD")
        req.setValue(sig, forHTTPHeaderField: "X-GEMINI-SIGNATURE")
        
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            let ok = (resp as? HTTPURLResponse)?.statusCode == 200
            if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("Gemini response: \(json)")
            }
            completion(ok)
        }.resume()
    }
}
