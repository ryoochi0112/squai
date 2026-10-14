import Foundation

enum Preferences {
    private static let d = UserDefaults.standard
    static var selectedPetID: String? {
        get { d.string(forKey: "selectedPetID") }
        set { d.set(newValue, forKey: "selectedPetID") }
    }
    static var petOrigin: CGPoint? {
        get {
            guard let a = d.array(forKey: "petOrigin") as? [Double], a.count == 2 else { return nil }
            return CGPoint(x: a[0], y: a[1])
        }
        set { d.set(newValue.map { [$0.x, $0.y] }, forKey: "petOrigin") }
    }
    static var frameRate: Double {
        let v = d.double(forKey: "frameRate")
        return v > 0 ? v : 8
    }
}
