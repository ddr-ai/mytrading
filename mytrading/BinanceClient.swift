import Foundation
import CryptoKit

struct BinanceClient {
    static let base = "https://api.binance.com"
    static func price(symbol: String, completion: @escaping (Double?) -> Void) {
        guard let url = URL(string: "\(base)/api/v3/ticker/price?symbol=\(symbol)") else { completion(nil); return }
        URLSession.shared.dataTask(with: url) { data,_,_ in
            guard let data = data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let p = obj["price"] as? String, let price = Double(p) else { completion(nil); return }
            completion(price)
        }.resume()
    }

    static func marketOrder(symbol: String, side: String, quoteQty: Double, apiKey: String, secret: String, completion: @escaping (Bool) -> Void) {
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        let query = "symbol=\(symbol)&side=\(side)&type=MARKET&quoteOrderQty=\(quoteQty)&timestamp=\(ts)"
        let key = SymmetricKey(data: Data(secret.utf8))
        let sig = HMAC<SHA256>.authenticationCode(for: Data(query.utf8), using: key).map { String(format: "%02x", $0) }.joined()
        let full = "\(base)/api/v3/order?\(query)&signature=\(sig)"
        guard let url = URL(string: full) else { completion(false); return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "X-MBX-APIKEY")
        URLSession.shared.dataTask(with: req) { data,resp,_ in
            let ok = (resp as? HTTPURLResponse)?.statusCode == 200
            completion(ok)
        }.resume()
    }
}
