import Foundation
import CryptoKit

struct GeminiClient {
    static let base = "https://api.gemini.com"
    static let wsBase = "wss://api.gemini.com/v1/marketdata"
    
    // REST: Price ticker
    static func price(symbol: String, completion: @escaping (Double?) -> Void) {
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
    
    // REST: Order book for volume/spread analysis
    static func orderBook(symbol: String, completion: @escaping ([String: Any]?) -> Void) {
        let pair = symbol.lowercased().replacingOccurrences(of: "usdt", with: "usd")
        guard let url = URL(string: "\(base)/v1/book/\(pair)?limit_bids=50&limit_asks=50") else { completion(nil); return }
        URLSession.shared.dataTask(with: url) { data,_,_ in
            guard let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { completion(nil); return }
            completion(obj)
        }.resume()
    }
    
    // REST: Recent trades for volume analysis
    static func trades(symbol: String, completion: @escaping ([[String: Any]]?) -> Void) {
        let pair = symbol.lowercased().replacingOccurrences(of: "usdt", with: "usd")
        guard let url = URL(string: "\(base)/v1/trades/\(pair)?limit_trades=100") else { completion(nil); return }
        URLSession.shared.dataTask(with: url) { data,_,_ in
            guard let data = data,
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { completion(nil); return }
            completion(arr)
        }.resume()
    }
    
    // REST: Account balance
    static func balances(apiKey: String, secret: String, completion: @escaping ([String: Double]?) -> Void) {
        let nonce = String(Int(Date().timeIntervalSince1970 * 1000000))
        let payload: [String: Any] = ["request": "/v1/balances", "nonce": nonce]
        guard let payloadData = try? JSONSerialization.data(withJSONObject: payload) else { completion(nil); return }
        let payloadB64 = payloadData.base64EncodedString()
        
        let keyData = Data(base64Encoded: secret) ?? Data(secret.utf8)
        let key = SymmetricKey(data: keyData)
        let sig = HMAC<SHA384>.authenticationCode(for: Data(payloadB64.utf8), using: key)
            .map { String(format: "%02x", $0) }.joined()
        
        guard let url = URL(string: "\(base)/v1/balances") else { completion(nil); return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        req.setValue("0", forHTTPHeaderField: "Content-Length")
        req.setValue(apiKey, forHTTPHeaderField: "X-GEMINI-APIKEY")
        req.setValue(payloadB64, forHTTPHeaderField: "X-GEMINI-PAYLOAD")
        req.setValue(sig, forHTTPHeaderField: "X-GEMINI-SIGNATURE")
        
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            guard (resp as? HTTPURLResponse)?.statusCode == 200,
                  let data = data,
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { completion(nil); return }
            var result: [String: Double] = [:]
            for item in arr {
                if let curr = item["currency"] as? String,
                   let amt = item["available"] as? String,
                   let val = Double(amt) {
                    result[curr.uppercased()] = val
                }
            }
            completion(result)
        }.resume()
    }
    
    // REST: Place market order
    static func marketOrder(symbol: String, side: String, amount: Double, apiKey: String, secret: String, completion: @escaping (Bool, String?) -> Void) {
        let pair = symbol.lowercased().replacingOccurrences(of: "usdt", with: "usd")
        let nonce = String(Int(Date().timeIntervalSince1970 * 1000000))
        
        let payload: [String: Any] = [
            "request": "/v1/order/new",
            "nonce": nonce,
            "symbol": pair,
            "amount": String(format: "%.8f", amount),
            "price": "1",
            "side": side.lowercased(),
            "type": "exchange market",
            "options": ["immediate-or-cancel"]
        ]
        
        guard let payloadData = try? JSONSerialization.data(withJSONObject: payload) else { completion(false, "payload"); return }
        let payloadB64 = payloadData.base64EncodedString()
        
        let keyData = Data(base64Encoded: secret) ?? Data(secret.utf8)
        let key = SymmetricKey(data: keyData)
        let sig = HMAC<SHA384>.authenticationCode(for: Data(payloadB64.utf8), using: key)
            .map { String(format: "%02x", $0) }.joined()
        
        guard let url = URL(string: "\(base)/v1/order/new") else { completion(false, "url"); return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        req.setValue("0", forHTTPHeaderField: "Content-Length")
        req.setValue(apiKey, forHTTPHeaderField: "X-GEMINI-APIKEY")
        req.setValue(payloadB64, forHTTPHeaderField: "X-GEMINI-PAYLOAD")
        req.setValue(sig, forHTTPHeaderField: "X-GEMINI-SIGNATURE")
        
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            let ok = (resp as? HTTPURLResponse)?.statusCode == 200
            var msg: String? = nil
            if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                msg = json["result"] as? String ?? json["reason"] as? String
                print("Gemini order response: \(json)")
            }
            completion(ok, msg)
        }.resume()
    }
}
