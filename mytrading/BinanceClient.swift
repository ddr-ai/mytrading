import Foundation

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
}
