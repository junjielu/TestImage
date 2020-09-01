//
//  ViewController.swift
//  TestImage
//
//  Created by 陆俊杰 on 2020/8/28.
//

import UIKit
import Foundation
import MobileCoreServices

private let maximumImagePixelLimit: CGFloat = 15000000

enum CompressOption {
    case sizeLimitInKb(Int)
    case compressQuality(Double)
}

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.frame = self.view.bounds
        self.view.addSubview(imageView)
        if let path = Bundle.main.path(forResource: "test", ofType: "heic"), let data = NSData(contentsOfFile: path) as Data? {
//            let downsizedImageData = getDownsizedImageData(fromCompressedImageData: data, shortEdgeInPixel: 1500)
            let downsizedImageData = getEncodedImageData(fromCompressedImageData: data, shortEdgeInPixel: 1500)
            let image = UIImage(data: downsizedImageData)
            imageView.image = image
        }
    }
    
    func getEncodedImageData(fromCompressedImageData data: Data, shortEdgeInPixel: CGFloat) -> Data {
        guard let imageSource = getImageSource(from: data) else {
            return data
        }
        
        guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any],
            let width = properties[kCGImagePropertyPixelWidth as String] as? CGFloat,
            let height = properties[kCGImagePropertyPixelHeight as String] as? CGFloat else {
            return data
        }
        
        let originalPixelSize = CGSize(width: width, height: height)
        
        var scaledPixelSize = UIImage.calculatePixelSize(originalPixelSize: originalPixelSize, shortEdge: shortEdgeInPixel, longEdge: nil)
        if scaledPixelSize.width * scaledPixelSize.height > maximumImagePixelLimit {
            let scale = sqrt(scaledPixelSize.width * scaledPixelSize.height / maximumImagePixelLimit)
            scaledPixelSize = CGSize(width: floor(scaledPixelSize.width / scale), height: floor(scaledPixelSize.height / scale))
        }
        
        let destOptions: [String: Any] = [
            kCGImageDestinationEmbedThumbnail as String: true,
            kCGImageMetadataShouldExcludeGPS as String: true,
            kCGImageDestinationLossyCompressionQuality as String: 0.75,
            kCGImageDestinationImageMaxPixelSize as String: max(scaledPixelSize.width, scaledPixelSize.height)
        ]
        let compressType = "public.heic" as CFString
        let metaData = CGImageSourceCopyMetadataAtIndex(imageSource, 0, nil)
        guard let encodedData = encode(imageSource: imageSource, to: compressType, with: metaData, destOptions: destOptions) else {
            return data
        }
        
        return encodedData
    }
    
    func getImageSource(from imageData: Data) -> CGImageSource? {
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
        ]
        return CGImageSourceCreateWithData(imageData as CFData, sourceOptions as CFDictionary)
    }
    
    func encode(imageSource: CGImageSource, to compressType: CFString, with metaData: CGImageMetadata?, destOptions: [String: Any]) -> Data? {
        // encode to data buffer
        let newImageData = NSMutableData()
        if let cgImageDestination = CGImageDestinationCreateWithData(newImageData, compressType, 1, nil) {
            CGImageDestinationAddImageFromSource(cgImageDestination, imageSource, 0, destOptions as CFDictionary)
            CGImageDestinationFinalize(cgImageDestination)
            
            return newImageData as Data
        } else {
            // sometimes encode would fail(heic is not supported before iPhone 7)
            // fallback to jpeg instead
            if compressType != kUTTypeJPEG {
                return self.encode(imageSource: imageSource, to: kUTTypeJPEG, with: metaData, destOptions: destOptions)
            } else {
                return nil
            }
        }
    }

    func getDownsizedImageData(fromCompressedImageData data: Data,
                               shortEdgeInPixel: CGFloat? = nil,
                               longEdgeInPixel: CGFloat? = nil,
                               totalPixelLimit: CGFloat = maximumImagePixelLimit,
                               compressQuality: Double = 0.75) -> Data {
        // 1. get resized cgImage, do not decode.
        guard let (cgImage, imageSource) = getCGImageAndSource(fromCompressedImageData: data,
                                                               shortEdgeInPixel: shortEdgeInPixel,
                                                               longEdgeInPixel: longEdgeInPixel,
                                                               totalPixelLimit: totalPixelLimit,
                                                               transformImage: false),
              let imageSourceType = CGImageSourceGetType(imageSource) else {
                return data
        }
        
        let metaData = CGImageSourceCopyMetadataAtIndex(imageSource, 0, nil)
        
        let image: CGImage = cgImage
        
        // 2. encode the image with quality and original metadata
        let encodedData = self.encodeCGImage(image, compressQuality: compressQuality, imageSourceType: imageSourceType, metaData: metaData)
        
        if let encodedData = encodedData {
            let properties = getImageDataProperties(encodedData)
            print(properties)
            return encodedData
        } else {
            return data
        }
    }
    
    func getImageDataProperties(_ data: Data) -> [String: Any] {
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
            return [:]
        }
        
        return CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any] ?? [:]
    }
    
    func getCGImageAndSource(fromCompressedImageData data: Data,
                             shortEdgeInPixel: CGFloat? = nil,
                             longEdgeInPixel: CGFloat? = nil,
                             totalPixelLimit: CGFloat,
                             transformImage: Bool = false,
                             decodeImage: Bool = false) -> (CGImage, CGImageSource)? {
        // see WWDC18 session 219
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
        ]
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            return nil
        }
        
        guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any],
            let width = properties[kCGImagePropertyPixelWidth as String] as? CGFloat,
            let height = properties[kCGImagePropertyPixelHeight as String] as? CGFloat else {
            return nil
        }
        
        let originalPixelSize = CGSize(width: width, height: height)
        
        var scaledPixelSize = UIImage.calculatePixelSize(originalPixelSize: originalPixelSize, shortEdge: shortEdgeInPixel, longEdge: longEdgeInPixel)
        if scaledPixelSize.width * scaledPixelSize.height > totalPixelLimit {
            let scale = sqrt(scaledPixelSize.width * scaledPixelSize.height / totalPixelLimit)
            scaledPixelSize = CGSize(width: floor(scaledPixelSize.width / scale), height: floor(scaledPixelSize.height / scale))
        }
        
        // see WWDC18 session 219
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: max(scaledPixelSize.width, scaledPixelSize.height),
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: transformImage,
            kCGImageSourceShouldCacheImmediately: decodeImage,
        ]
        
        guard let resultCGImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            return nil
        }
        
        return (resultCGImage, imageSource)
    }
    
    func encodeCGImage(_ image: CGImage,
                       compressQuality: Double,
                       imageSourceType: CFString,
                       metaData: CGImageMetadata?) -> Data? {
        var destOptions: [String: Any] = [kCGImageDestinationEmbedThumbnail as String: true]
        
        if metaData != nil {
            destOptions[kCGImageMetadataShouldExcludeGPS as String] = true
        }
        
        var compressType: CFString
        let heifType = "public.heic" as CFString
        switch imageSourceType {
        case kUTTypeGIF:
            return encode(image: image, to: kUTTypeGIF, with: metaData, destOptions: destOptions)
        case kUTTypePNG, kUTTypeJPEG:
            // use original image type for png/jpeg/gif
            compressType = imageSourceType
        case heifType:
            compressType = imageSourceType
        default:
            // for other image types, qiniu might not support them(Sean said). Just use jpeg.
            compressType = kUTTypeJPEG
        }
        
        destOptions[kCGImageDestinationLossyCompressionQuality as String] = compressQuality
        return encode(image: image, to: compressType, with: metaData, destOptions: destOptions)
    }
    
    func encode(image: CGImage, to compressType: CFString, with metaData: CGImageMetadata?, destOptions: [String: Any]) -> Data? {
        // encode to data buffer
        let newImageData = NSMutableData()
        if let cgImageDestination = CGImageDestinationCreateWithData(newImageData, compressType, 1, nil) {
            
            CGImageDestinationAddImageAndMetadata(cgImageDestination, image, metaData, destOptions as CFDictionary)
            CGImageDestinationFinalize(cgImageDestination)
            
            return newImageData as Data
        } else {
            // sometimes encode would fail(heic is not supported before iPhone 7)
            // fallback to jpeg instead
            if compressType != kUTTypeJPEG {
                return self.encode(image: image, to: kUTTypeJPEG, with: metaData, destOptions: destOptions)
            } else {
                return nil
            }
        }
    }
}

extension UIImage {
    public static func calculatePixelSize(originalPixelSize: CGSize, shortEdge: CGFloat? = nil, longEdge: CGFloat? = nil) -> CGSize {
        guard shortEdge != nil || longEdge != nil else {
            return originalPixelSize
        }
        
        // validate params
        if let shortEdge = shortEdge, shortEdge <= 0 {
            return originalPixelSize
        }
        
        if let longEdge = longEdge, longEdge <= 0 {
            return originalPixelSize
        }
        
        func getLongEdge(size: CGSize) -> CGFloat {
            return max(size.width, size.height)
        }
        
        func getShortEdge(size: CGSize) -> CGFloat {
            return min(size.width, size.height)
        }
        
        var scaledPixelSize = originalPixelSize
        
        // 1. check if shortEdge is satisfied
        if let toShortEdge = shortEdge {
            if toShortEdge < getShortEdge(size: scaledPixelSize) {
                let scaleDownFactor = toShortEdge / getShortEdge(size: scaledPixelSize)
                scaledPixelSize = scaledPixelSize.applying(CGAffineTransform(scaleX: scaleDownFactor, y: scaleDownFactor))
            }
        }
        
        // 2. check if longEdge is satisfied(after satisfying shortEdge)
        if let toLongEdge = longEdge {
            if toLongEdge < getLongEdge(size: scaledPixelSize) {
                let scaleDownFactor = toLongEdge / getLongEdge(size: scaledPixelSize)
                scaledPixelSize = scaledPixelSize.applying(CGAffineTransform(scaleX: scaleDownFactor, y: scaleDownFactor))
            }
        }
        return scaledPixelSize
    }
    
    /// Scale the image by constraining max short/long edge length in pixel.
    /// - parameter shortEdgeInPixel: Maximum short edge length. nil for unconstrained.
    /// - parameter longEdgeInPixel: Maximum long edge length. nil for unconstrained.
    /// - parameter opaque: If image has alpha channel, set to false. Setting this to false for images without alpha may result in an image with a pink hue.
    /// - returns: Scaled image
    public func limit(shortEdgeInPixel: CGFloat? = nil,
                      longEdgeInPixel: CGFloat? = nil,
                      opaque: Bool = true,
                      resultImageScale: CGFloat? = nil) -> UIImage {
        let originalPixelSize = self.size.applying(CGAffineTransform(scaleX: self.scale, y: self.scale))
        
        let scaledPixelSize = UIImage.calculatePixelSize(originalPixelSize: originalPixelSize, shortEdge: shortEdgeInPixel, longEdge: longEdgeInPixel)
        
        // only return if:
        // 1. pixel size doesn't change after satisfying constraints
        // 2. image scale equals result scale
        if originalPixelSize == scaledPixelSize && (resultImageScale == nil || resultImageScale == self.scale) {
            return self
        }
        
        // draw in scaled canvas
        // current scale is 1, need to render in original image scale(or specified scale), so finally we can get the result image with the desired scale
        // The image scale may be different with the device scale
        let resultImageScale = resultImageScale ?? self.scale
        let factor = 1 / resultImageScale
        let canvasSize = scaledPixelSize.applying(CGAffineTransform(scaleX: factor, y: factor))
        
        UIGraphicsBeginImageContextWithOptions(canvasSize, opaque, resultImageScale)
        self.draw(in: CGRect(x: 0, y: 0, width: canvasSize.width, height: canvasSize.height))
        let resultImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return resultImage!
    }
    
    public func scale(toSizeInScreenScale: CGSize) -> UIImage {
        let factor = UIScreen.main.scale / self.scale
        let toSizeInSelfScale = CGSize(width: toSizeInScreenScale.width * factor,
                                       height: toSizeInScreenScale.height * factor)
        if toSizeInSelfScale == self.size {
            return self
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        return UIGraphicsImageRenderer(size: toSizeInScreenScale, format: format).image { _ in
            self.draw(in: CGRect(origin: CGPoint.zero, size: toSizeInScreenScale))
        }
//        UIGraphicsBeginImageContextWithOptions(toSizeInSelfScale, true, self.scale)
//        self.draw(in: CGRect(x: 0, y: 0, width: toSizeInSelfScale.width, height: toSizeInSelfScale.height))
//        let resultImage = UIGraphicsGetImageFromCurrentImageContext()
//        UIGraphicsEndImageContext()
//        return resultImage!
    }
    
    /**
     Scale the image by constraining max short/long edge length in point. A wrapper function for limit(shortEdgeInPixel: CGFloat?, longEdgeInPixel: CGFloat?, opaque: Bool)
     */
    public func limitUsingPointOfCurrentDevice(shortEdgeInPoint: CGFloat? = nil, longEdgeInPoint: CGFloat? = nil, opaque: Bool = true) -> UIImage {
        
        let deviceScale = UIScreen.main.scale
        var shortPixel: CGFloat?
        if let short = shortEdgeInPoint {
            shortPixel = short * deviceScale
        }
        var longPixel: CGFloat?
        if let long = longEdgeInPoint {
            longPixel = long * deviceScale
        }
        return limit(shortEdgeInPixel: shortPixel, longEdgeInPixel: longPixel, opaque: opaque, resultImageScale: deviceScale)
    }
}

