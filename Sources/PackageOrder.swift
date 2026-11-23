import Foundation

struct PackageOrder {
    let ids: [String]

    init(_ packages: [TweakPackage], moving id: String, to target: String, after: Bool) throws {
        let original = packages.map(\.id)
        guard let moved = packages.first(where: { $0.id == id }), original.contains(target), target != id else {
            ids = original
            return
        }
        var desired = packages.filter { $0.id != id }
        let index = desired.firstIndex { $0.id == target }! + (after ? 1 : 0)
        desired.insert(moved, at:index)
        ids = desired.map(\.id)
        if ids == original { return }
        let positions = Dictionary(uniqueKeysWithValues:ids.enumerated().map { ($1,$0) })
        for (index,p) in desired.enumerated() {
            for dependency in (p.fields["packageDependencies"] as? Fields ?? [:]).keys {
                if let position = positions[dependency], position >= index {
                    throw PackpierError.message(PPText.format("%@ 依赖 %@，必须排在它后面。",p.title,dependency))
                }
            }
        }
    }
}
