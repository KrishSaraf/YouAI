import UIKit

/// Shrinks a camera image down to something worth sending over the network.
///
/// NVIDIA's hosted endpoints cap inline base64 images at roughly 180 KB, and a
/// straight iPhone photo is far bigger than that, so this steps the JPEG quality
/// down until the *encoded* payload fits rather than guessing at a quality value.
enum ImagePreparer {

    /// NVIDIA's documented inline base64 limit, with a little headroom for the
    /// surrounding JSON.
    static let inlineBase64Limit = 170_000

    struct Prepared {
        let jpeg: Data
        let base64: String
        var dataURL: String { "data:image/jpeg;base64,\(base64)" }
    }

    static func prepare(_ image: UIImage, maxDimension: CGFloat = 1024) -> Prepared? {
        let resized = downscale(image, maxDimension: maxDimension)

        for quality in stride(from: 0.8, through: 0.3, by: -0.1) {
            guard let jpeg = resized.jpegData(compressionQuality: quality) else { continue }
            let base64 = jpeg.base64EncodedString()
            if base64.count <= inlineBase64Limit {
                return Prepared(jpeg: jpeg, base64: base64)
            }
        }

        // Still too big at the lowest quality: halve the dimensions and retry once.
        guard maxDimension > 384 else { return nil }
        return prepare(image, maxDimension: maxDimension / 2)
    }

    /// A smaller JPEG for storing alongside the meal row, so the SwiftData store
    /// doesn't grow by several megabytes per meal.
    static func thumbnail(_ image: UIImage, maxDimension: CGFloat = 600) -> Data? {
        downscale(image, maxDimension: maxDimension).jpegData(compressionQuality: 0.7)
    }

    static func downscale(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image }

        let scale = maxDimension / longest
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
