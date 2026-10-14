import Foundation

enum Preferences {
    private static let d = UserDefaults.standard
    static var selectedPetID: String? {
        get { d.string(forKey: "selectedPetID") }
        set { d.set(newValue, forKey: "selectedPetID") }
    }
    static func origin(for id: String) -> CGPoint? {
        guard let a = d.array(forKey: "petOrigin.\(id)") as? [Double], a.count == 2 else { return nil }
        return CGPoint(x: a[0], y: a[1])
    }
    static func setOrigin(_ origin: CGPoint, for id: String) {
        d.set([origin.x, origin.y], forKey: "petOrigin.\(id)")
    }
    static var frameRate: Double {
        let v = d.double(forKey: "frameRate")
        return v > 0 ? v : 8
    }
}
