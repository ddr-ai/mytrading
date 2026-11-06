import Foundation
import CryptoKit

// Kraken (regulated, available in NYC)
struct KrakenClient {
    static let base = "https://api.kraken.com"
    static func price(pair: String, completion: @escaping (Double?) -> Void) {
        let p = pair.replacingOccurrences(of: "USDT", with: "USD")
        guard let url = URL(string: "\(base)/0/public/Ticker?pair=\(p)") else { completion(nil); return }
        URLSession.shared.dataTask(with: url) { data,_,_ in
            guard let data = data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = obj["result"] as? [String: Any],
                  let first = result.values.first as? [String: Any],
                  let c = first["c"] as? [String], let price = Double(c[0]) else { completion(nil); return }
            completion(price)
        }.resume()
    }
}
