//
//  ViewController.swift
//  AutoGenVideo
//
//  Created by cm0620 on 2023/3/15.
//

import UIKit
import AVFoundation
import PhotosUI

class ViewController: UIViewController {
    
    @IBAction func didClick(_ sender: Any) {
        print("\(images.count)")
        //genVideoA(selectedImages: images)
        genVideoB(selectedImages: images, handler: {
            [weak self] url in
            guard let self = self else { return }
            print(url)
            self.saveVideoToLibrary(videoURL: url)
        })
    }
    
    var videoUrl: URL?
    var images: [UIImage] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 10
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        
        // 选择导入的图片
        present(picker, animated: true, completion: nil)
    }
    
    func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        return documentsDirectory
    }
    
    func saveVideoToLibrary(videoURL: URL) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
        }) { saved, error in
            if saved {
                print("Video saved successfully.")
            } else {
                print("Error saving video: \(error?.localizedDescription ?? "Unknown error")")
            }
        }
    }
    
    func genVideoB(selectedImages: [UIImage], handler: @escaping ((URL)->Void)) {
        
        let name: String = "output_\(Date().timeIntervalSince1970).mp4"
        let outPutFileURL = getDocumentsDirectory().appendingPathComponent(name)
        
        let assetWriter = try? AVAssetWriter(url: outPutFileURL, fileType: .mov)
        let success = (assetWriter != nil)
        let fps: Int = 30
        let secondPerImage: Int = 3
        
        //视频尺寸
        let size = CGSize(width: 1920, height: 1080)

        //视频信息设置
        let outPutSettingDic = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: NSNumber(value: Float(size.width)),
            AVVideoHeightKey: NSNumber(value: Float(size.height))
        ] as [String : Any]

        if success {
            let videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: outPutSettingDic)
            let sourcePixelBufferAttributes = [
                kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32BGRA)
            ]
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoWriterInput,
                                                               sourcePixelBufferAttributes: sourcePixelBufferAttributes)
            
            if assetWriter!.canAdd(videoWriterInput) {
                assetWriter!.add(videoWriterInput)
                assetWriter!.startWriting()
                assetWriter!.startSession(atSourceTime: .zero)
            }
            
            //开一个队列
            let dispatchQueue = DispatchQueue(label: "mediaQueue")
            var index = 0
            
            videoWriterInput.requestMediaDataWhenReady(on: dispatchQueue) {
                while videoWriterInput.isReadyForMoreMediaData {
                    if (index + 1 >= selectedImages.count * fps * secondPerImage) {
                        videoWriterInput.markAsFinished()
                        assetWriter!.finishWriting {
                            DispatchQueue.main.async {
                                handler(outPutFileURL)
                            }
                        }
                        break
                    }
                    let idx = index / fps / secondPerImage
                    print("打印信息: \(idx) \(index)")
                    
                    //先将图片转换成CVPixelBufferRef
                    let image = selectedImages[idx]
                    let pixelBuffer = image.pixelBufferRef(withSize: size)
                    if let pixelBuffer = pixelBuffer {
                        let time = CMTimeMake(value: Int64(index), timescale: Int32(fps))
                        if (adaptor.append(pixelBuffer, withPresentationTime: time)) {
                            print("OK++")
                        } else {
                            print("Fail")
                        }
                    }
                    index += 1
                }
            }
        }
    }
    
    func genVideoA(selectedImages: [UIImage]) {
        
        // 创建 AVMutableComposition 对象
        let composition = AVMutableComposition()

        // 创建 AVAssetTrack 对象
        let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        
        // 计算每个图片需要显示的时间
        var lastTime = CMTimeMake(value: 0, timescale: 1)
        let imageDuration = CMTimeMake(value: 5, timescale: 1)
        let imagesCount = selectedImages.count
        let videoDuration = CMTimeMake(value: Int64(imagesCount * 5), timescale: 1)
        
        // 遍历所有选中的图片
        for (index, image) in selectedImages.enumerated() {
            
            // 将 CGImage 转换为 CMSampleBuffer
            guard let pixelBuffer = image.pixelBuffer() else { continue }
            var sampleBuffer: CMSampleBuffer?
            var formatDescription: CMVideoFormatDescription? = nil
            let status = CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &formatDescription)
            guard let desc = formatDescription, status == noErr else {
                fatalError("Failed to create CMVideoFormatDescription object")
            }
            var timingInfo = CMSampleTimingInfo()
            timingInfo.duration = imageDuration
            timingInfo.presentationTimeStamp = CMTimeMultiply(imageDuration, multiplier: Int32(index))
            timingInfo.decodeTimeStamp = CMTime.invalid
            let err = CMSampleBufferCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                         imageBuffer: pixelBuffer,
                                                         dataReady: true,
                                                         makeDataReadyCallback: nil,
                                                         refcon: nil,
                                                         formatDescription: desc,
                                                         sampleTiming: &timingInfo,
                                                         sampleBufferOut: &sampleBuffer)
            guard err == noErr, let buf = sampleBuffer else { continue }
            
            // 将每个图像添加到视频轨道
            do {
                let videoSettings: [String : Any] = [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: 640,
                    AVVideoHeightKey: 480
                ]
                let videoWriterInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: videoSettings)
                videoWriterInput.expectsMediaDataInRealTime = true
                
                let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoWriterInput, sourcePixelBufferAttributes: nil)
                
                
                let presentationTime = CMTimeAdd(lastTime, imageDuration)
                guard let imageBuffer = CMSampleBufferGetImageBuffer(buf) else {
                    fatalError("Failed to get image buffer from sample buffer")
                }
                let pixelBuffer = imageBuffer as CVPixelBuffer
                try pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime)
                lastTime = presentationTime
            } catch {
                print("Error: \(error.localizedDescription)")
            }
        }

        // 创建 AVAsset 对象
        guard let audioUrl = Bundle.main.url(forResource: "bgm", withExtension: "mp3") else { return }
        let audioAsset = AVAsset(url: audioUrl)
        let audioTrack = audioAsset.tracks(withMediaType: .audio)[0]
        let audioDuration = audioAsset.duration
        
        // 将音频添加到视频轨道
        do {
            try videoTrack?.insertTimeRange(CMTimeRangeMake(start: CMTime.zero, duration: audioDuration), of: audioTrack, at: CMTime.zero)
        } catch {
            print("Error: \(error.localizedDescription)")
        }
        
        // 创建 AVAssetExportSession 对象
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else { return }
        exportSession.outputFileType = AVFileType.mp4
        exportSession.outputURL = getDocumentsDirectory().appendingPathComponent("output.mp4")
        
        // 导出视频
        exportSession.exportAsynchronously(completionHandler: {
            DispatchQueue.main.async {
                self.videoUrl = exportSession.outputURL
                self.dismiss(animated: true, completion: {
                    // 在这里你可以播放最终生成的视频
                })
            }
        })
    }
}

extension ViewController: PHPickerViewControllerDelegate {
    
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            
        picker.dismiss(animated: true)
        
        let itemProviders = results.map(\.itemProvider)
        
        images.removeAll()
        for itemProvider in itemProviders {
            if itemProvider.canLoadObject(ofClass: UIImage.self) {
                itemProvider.loadObject(ofClass: UIImage.self) {[weak self] (image, error) in
                    guard let self = self, let image = image as? UIImage else { return }
                    self.images.append(image)
                }
            }
        }
    }
}

extension UIImage {
    
    func pixelBufferRef(withSize size: CGSize) -> CVPixelBuffer? {
        
        let options: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: NSNumber(value: true),
            kCVPixelBufferCGBitmapContextCompatibilityKey: NSNumber(value: true)
        ]
        
        var pxbuffer: CVPixelBuffer? = nil
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         Int(size.width),
                                         Int(size.height),
                                         kCVPixelFormatType_32ARGB,
                                         options as CFDictionary, &pxbuffer)

        guard status == kCVReturnSuccess, let buffer = pxbuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(buffer, .init(rawValue: 0))
        let pxdata = CVPixelBufferGetBaseAddress(buffer)
        guard let data = pxdata else {
            CVPixelBufferUnlockBaseAddress(buffer, .init(rawValue: 0))
            return nil
        }

        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: data,
                                width: Int(size.width),
                                height: Int(size.height),
                                bitsPerComponent: 8,
                                bytesPerRow: 4 * Int(size.width),
                                space: rgbColorSpace,
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)
        
        guard let ctx = context else {
            CVPixelBufferUnlockBaseAddress(buffer, .init(rawValue: 0))
            return nil
        }

        //ctx.draw(self.cgImage!, in: CGRect(x: 0, y: 0, width: self.cgImage!.width, height: self.cgImage!.height))

        let contextSize = ctx.boundingBoxOfClipPath.size
        let imageSize = CGSize(width: self.cgImage!.width, height: self.cgImage!.height)

        // 計算比例關係
        let scale = min(contextSize.width / imageSize.width, contextSize.height / imageSize.height)

        // 計算縮放後的大小
        let scaledSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)

        // 計算需要移動的位置
        let xOffset = (contextSize.width - scaledSize.width) / 2.0
        let yOffset = (contextSize.height - scaledSize.height) / 2.0

        // 繪製縮放後的圖像
        ctx.draw(self.cgImage!, in: CGRect(x: xOffset, y: yOffset, width: scaledSize.width, height: scaledSize.height))
    
        CVPixelBufferUnlockBaseAddress(buffer, .init(rawValue: 0))

        return buffer
    }
    
    func pixelBuffer() -> CVPixelBuffer? {
        let width = Int(self.size.width)
        let height = Int(self.size.height)
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue, kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue]
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32ARGB, attrs as CFDictionary, &pixelBuffer)
        guard let buffer = pixelBuffer, status == kCVReturnSuccess else {
            return nil
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer {
            CVPixelBufferUnlockBaseAddress(buffer, [])
        }

        if let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer),
                                   width: width,
                                   height: height,
                                   bitsPerComponent: 8,
                                   bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) {
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1.0, y: -1.0)

            UIGraphicsPushContext(context)
            self.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
            UIGraphicsPopContext()
            return buffer
        }

        return nil
    }
}
