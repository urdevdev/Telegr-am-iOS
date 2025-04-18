// MARK: Swiftgram
import SGSimpleSettings

import Foundation
import UIKit
import AsyncDisplayKit
import Display
import TelegramCore
import Postbox
import SwiftSignalKit
import TelegramPresentationData
import MediaResources
import LegacyComponents
import AccountContext
import LegacyUI
import ImageCompression
import LocalMediaResources
import AppBundle
import LegacyMediaPickerUI
import ChatPresentationInterfaceState
import ChatSendButtonRadialStatusNode

public final class InstantVideoController: LegacyController, StandalonePresentableController {
    private var captureController: TGVideoMessageCaptureController?
    
    public var onDismiss: ((Bool) -> Void)?
    public var onStop: (() -> Void)?
    public var didStop: (() -> Void)?
    
    private let micLevelValue = ValuePromise<Float>(0.0)
    private let durationValue = ValuePromise<TimeInterval>(0.0)
    public let audioStatus: InstantVideoControllerRecordingStatus

    private var completed = false
    private var dismissed = false
    
    override public init(presentation: LegacyControllerPresentation, theme: PresentationTheme?, strings: PresentationStrings? = nil, initialLayout: ContainerViewLayout? = nil) {
        self.audioStatus = InstantVideoControllerRecordingStatus(micLevel: self.micLevelValue.get(), duration: self.durationValue.get())
        
        super.init(presentation: presentation, theme: theme, initialLayout: initialLayout)
        
        self.hasSparseContainerView = true
        self.lockOrientation = true
    }
    
    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func bindCaptureController(_ captureController: TGVideoMessageCaptureController?) {
        self.captureController = captureController
        if let captureController = captureController {
            captureController.view.disablesInteractiveKeyboardGestureRecognizer = true
            captureController.view.disablesInteractiveTransitionGestureRecognizer = true

            captureController.micLevel = { [weak self] (level: CGFloat) -> Void in
                self?.micLevelValue.set(Float(level))
            }
            captureController.onDuration = { [weak self] duration in
                self?.durationValue.set(duration)
            }
            captureController.onDismiss = { [weak self] _, isCancelled in
                guard let self = self else { return }
                if !self.dismissed {
                    self.dismissed = true
                    self.onDismiss?(isCancelled)
                }
            }
            captureController.didStop = { [weak self] in
                guard let self else { return }
                self.didStop?()
            }
            captureController.onStop = { [weak self] in
                self?.onStop?()
            }
        }
    }
    
    public func dismissVideo() {
        if let captureController = self.captureController, !self.dismissed {
            self.dismissed = true
            captureController.dismiss(true)
        }
    }

    public func extractVideoSnapshot() -> UIView? {
        self.captureController?.extractVideoContent()
    }

    public func hideVideoSnapshot() {
        self.captureController?.hideVideoContent()
    }
    
    public func completeVideo() {
        if let captureController = self.captureController, !self.completed {
            self.completed = true
            captureController.complete()
        }
    }

    public func dismissAnimated() {
        if let captureController = self.captureController, !self.dismissed {
            self.dismissed = true
            captureController.dismiss(false)
        }
    }
    
    public func stopVideo() -> Bool {
        if let captureController = self.captureController {
            return captureController.stop()
        }
        return false
    }
    
    public func lockVideo() {
        if let captureController = self.captureController {
            return captureController.setLocked()
        }
    }
    
    public func updateRecordButtonInteraction(_ value: CGFloat) {
        if let captureController = self.captureController {
            captureController.buttonInteractionUpdate(CGPoint(x: value, y: 0.0))
        }
    }
    
    public func send() {
        if let captureController = self.captureController {
            captureController.send()
        }
    }
}

public func legacyInputMicPalette(from theme: PresentationTheme) -> TGModernConversationInputMicPallete {
    let inputPanelTheme = theme.chat.inputPanel
    return TGModernConversationInputMicPallete(dark: theme.overallDarkAppearance, buttonColor: inputPanelTheme.actionControlFillColor, iconColor: inputPanelTheme.actionControlForegroundColor, backgroundColor: theme.rootController.navigationBar.opaqueBackgroundColor, borderColor: inputPanelTheme.panelSeparatorColor, lock: inputPanelTheme.panelControlAccentColor, textColor: inputPanelTheme.primaryTextColor, secondaryTextColor: inputPanelTheme.secondaryTextColor, recording: inputPanelTheme.mediaRecordingDotColor)
}

public func legacyInstantVideoController(theme: PresentationTheme, forStory: Bool, panelFrame: CGRect, context: AccountContext, peerId: PeerId, slowmodeState: ChatSlowmodeState?, hasSchedule: Bool, send: @escaping (InstantVideoController, EnqueueMessage?) -> Void, displaySlowmodeTooltip: @escaping (UIView, CGRect) -> Void, presentSchedulePicker: @escaping (@escaping (Int32) -> Void) -> Void) -> InstantVideoController {
    let isSecretChat = peerId.namespace == Namespaces.Peer.SecretChat
    
    let legacyController = InstantVideoController(presentation: .custom, theme: theme)
    legacyController.supportedOrientations = ViewControllerSupportedOrientations(regularSize: .all, compactSize: .all)
    legacyController.lockOrientation = true
    legacyController.statusBar.statusBarStyle = .Hide
    let baseController = TGViewController(context: legacyController.context)!
    baseController.view.isUserInteractionEnabled = false
    legacyController.bind(controller: baseController)
    legacyController.presentationCompleted = { [weak legacyController, weak baseController] in
        if let legacyController = legacyController, let baseController = baseController {
            legacyController.view.disablesInteractiveTransitionGestureRecognizer = true
            var uploadInterface: LegacyLiveUploadInterface?
            if peerId.namespace != Namespaces.Peer.SecretChat {
                uploadInterface = LegacyLiveUploadInterface(context: context)
            }
            
            var slowmodeValidUntil: Int32 = 0
            if let slowmodeState = slowmodeState, case let .timestamp(timestamp) = slowmodeState.variant {
                slowmodeValidUntil = timestamp
            }
            
            let controller = TGVideoMessageCaptureController(context: legacyController.context, forStory: forStory, assets: TGVideoMessageCaptureControllerAssets(send: PresentationResourcesChat.chatInputPanelSendButtonImage(theme)!, slideToCancel: PresentationResourcesChat.chatInputPanelMediaRecordingCancelArrowImage(theme)!, actionDelete: generateTintedImage(image: UIImage(bundleImageName: "Chat/Input/Accessory Panels/MessageSelectionTrash"), color: theme.chat.inputPanel.panelControlAccentColor))!, transitionInView: {
                return nil
            }, parentController: baseController, controlsFrame: panelFrame, isAlreadyLocked: {
                return false
            }, liveUploadInterface: uploadInterface, pallete: legacyInputMicPalette(from: theme), slowmodeTimestamp: slowmodeValidUntil, slowmodeView: {
                let node = ChatSendButtonRadialStatusView(color: theme.chat.inputPanel.panelControlAccentColor)
                node.slowmodeState = slowmodeState
                return node
            }, canSendSilently: !isSecretChat, canSchedule: hasSchedule, reminder: peerId == context.account.peerId, startWithRearCam: SGSimpleSettings.shared.startTelescopeWithRearCam)!
            controller.presentScheduleController = { done in
                presentSchedulePicker { time in
                    done?(time)
                }
            }
            controller.finishedWithVideo = { [weak legacyController] videoUrl, previewImage, _, duration, dimensions, liveUploadData, adjustments, isSilent, scheduleTimestamp in
                guard let legacyController = legacyController else {
                    return
                }

                guard let videoUrl = videoUrl else {
                    send(legacyController, nil)
                    return
                }
                
                var finalDimensions: CGSize = dimensions
                var finalDuration: Double = duration
                
                var previewRepresentations: [TelegramMediaImageRepresentation] = []
                if let previewImage = previewImage {
                    let resource = LocalFileMediaResource(fileId: Int64.random(in: Int64.min ... Int64.max))
                    let thumbnailSize = finalDimensions.aspectFitted(CGSize(width: 320.0, height: 320.0))
                    let thumbnailImage = TGScaleImageToPixelSize(previewImage, thumbnailSize)!
                    if let thumbnailData = thumbnailImage.jpegData(compressionQuality: 0.4) {
                        context.account.postbox.mediaBox.storeResourceData(resource.id, data: thumbnailData)
                        previewRepresentations.append(TelegramMediaImageRepresentation(dimensions: PixelDimensions(thumbnailSize), resource: resource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false))
                    }
                }
                
                finalDimensions = TGMediaVideoConverter.dimensions(for: finalDimensions, adjustments: adjustments, preset: TGMediaVideoConversionPresetVideoMessage)
                
                var resourceAdjustments: VideoMediaResourceAdjustments?
                if let adjustments = adjustments {
                    if adjustments.trimApplied() {
                        finalDuration = adjustments.trimEndValue - adjustments.trimStartValue
                    }
                    
                    if let dict = adjustments.dictionary(), let data = try? NSKeyedArchiver.archivedData(withRootObject: dict, requiringSecureCoding: false) {
                        let adjustmentsData = MemoryBuffer(data: data)
                        let digest = MemoryBuffer(data: adjustmentsData.md5Digest())
                        resourceAdjustments = VideoMediaResourceAdjustments(data: adjustmentsData, digest: digest, isStory: false)
                    }
                }
                
                if finalDuration.isZero || finalDuration.isNaN {
                    return
                }
                
                let resource: TelegramMediaResource
                if let liveUploadData = liveUploadData as? LegacyLiveUploadInterfaceResult, resourceAdjustments == nil, let data = try? Data(contentsOf: videoUrl) {
                    resource = LocalFileMediaResource(fileId: liveUploadData.id)
                    context.account.postbox.mediaBox.storeResourceData(resource.id, data: data, synchronous: true)
                } else {
                    resource = LocalFileVideoMediaResource(randomId: Int64.random(in: Int64.min ... Int64.max), path: videoUrl.path, adjustments: resourceAdjustments)
                }
                
                if let previewImage = previewImage {
                    let tempFile = TempBox.shared.tempFile(fileName: "file")
                    defer {
                        TempBox.shared.dispose(tempFile)
                    }
                    if let data = compressImageToJPEG(previewImage, quality: 0.7, tempFilePath: tempFile.path) {
                    context.account.postbox.mediaBox.storeCachedResourceRepresentation(resource, representation: CachedVideoFirstFrameRepresentation(), data: data)
                    }
                }
                
                let media = TelegramMediaFile(fileId: MediaId(namespace: Namespaces.Media.LocalFile, id: Int64.random(in: Int64.min ... Int64.max)), partialReference: nil, resource: resource, previewRepresentations: previewRepresentations, videoThumbnails: [], immediateThumbnailData: nil, mimeType: "video/mp4", size: nil, attributes: [.FileName(fileName: "video.mp4"), .Video(duration: finalDuration, size: PixelDimensions(finalDimensions), flags: [.instantRoundVideo], preloadSize: nil, coverTime: nil, videoCodec: nil)], alternativeRepresentations: [])
                var message: EnqueueMessage = .message(text: "", attributes: [], inlineStickers: [:], mediaReference: .standalone(media: media), threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
                
                let scheduleTime: Int32? = scheduleTimestamp > 0 ? scheduleTimestamp : nil
                
                message = message.withUpdatedAttributes { attributes in
                    var attributes = attributes
                    for i in (0 ..< attributes.count).reversed() {
                        if attributes[i] is NotificationInfoMessageAttribute {
                            attributes.remove(at: i)
                        } else if let _ = scheduleTime, attributes[i] is OutgoingScheduleInfoMessageAttribute {
                            attributes.remove(at: i)
                        }
                    }
                    if isSilent {
                        attributes.append(NotificationInfoMessageAttribute(flags: .muted))
                    }
                    if let scheduleTime = scheduleTime {
                        attributes.append(OutgoingScheduleInfoMessageAttribute(scheduleTime: scheduleTime))
                    }
                    return attributes
                }
                
                send(legacyController, message)
            }
            controller.didDismiss = { [weak legacyController] in
                if let legacyController = legacyController {
                    legacyController.dismiss()
                }
            }
            controller.displaySlowmodeTooltip = { [weak legacyController, weak controller] in
                if let legacyController = legacyController, let controller = controller {
                    let rect = controller.frameForSendButton()
                    displaySlowmodeTooltip(legacyController.displayNode.view, rect)
                }
            }
            legacyController.bindCaptureController(controller)
            
            let presentationDisposable = context.sharedContext.presentationData.start(next: { [weak controller] presentationData in
                if let controller = controller {
                    controller.pallete = legacyInputMicPalette(from: presentationData.theme)
                }
            })
            legacyController.disposables.add(presentationDisposable)
        }
    }
    return legacyController
}
