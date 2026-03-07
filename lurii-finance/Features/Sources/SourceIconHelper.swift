import AppKit

extension String {
    /// Returns the asset name for a source icon, or nil if no icon exists in the asset catalog
    func sourceIconName() -> String? {
        let key = self.lowercased()
        return NSImage(named: key) != nil ? key : nil
    }
}
