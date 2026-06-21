import SwiftUI

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif

extension Image {
    /// Build a SwiftUI `Image` from raw image data on any Apple platform.
    init?(platformData data: Data) {
        #if canImport(UIKit)
        guard let img = UIImage(data: data) else { return nil }
        self = Image(uiImage: img)
        #elseif canImport(AppKit)
        guard let img = NSImage(data: data) else { return nil }
        self = Image(nsImage: img)
        #else
        return nil
        #endif
    }
}
