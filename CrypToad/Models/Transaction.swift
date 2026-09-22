import Foundation

enum TransactionType {
    case purchase, dca, deposit, p2pSent
}

struct Transaction: Identifiable {
    let id: Int
    let type: TransactionType
    let merchant: String?
    let recipient: String?
    let amount: Double
    let roundUp: Double
    let date: String
    let crypto: String
}
