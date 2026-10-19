import Foundation

@MainActor
protocol TextDelivery: AnyObject {
    func copy(_ body: String)
}
