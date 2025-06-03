import SwiftUI

extension UIImage {
    func resized(toMaxLength maxLength: CGFloat) -> UIImage {
        let originalWidth = size.width
        let originalHeight = size.height
        let maxOriginal = Swift.max(originalWidth, originalHeight)
        let scale = maxLength / maxOriginal
        let newSize = CGSize(width: originalWidth * scale, height: originalHeight * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in self.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
