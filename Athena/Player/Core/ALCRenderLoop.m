//
//  SCRenderLayer.m
//  Athena
//
//  Created by Skylar on 2019/10/14.
//  Copyright © 2019 Theresa. All rights reserved.
//

#import <MetalKit/MetalKit.h>
#import "ALCRenderLoop.h"
#import "ALCFormatContext.h"

#import "SCAudioFrame.h"
#import "SCVideoFrame.h"
#import "SCRender.h"
#import "ALCSynchronizer.h"
#import "ALCAudioManager.h"
#import "SCPlayerState.h"
#import "ALCDecoderLoop.h"
#import "ALCFrameQueue.h"

@interface ALCRenderLoop () <SCAudioManagerDelegate, MTKViewDelegate> {
    int currentFrameCopiedFrames;
    int bufferCopiedFrames;
}

@property (nonatomic, strong) ALCFrameQueue *manager;

@property (nonatomic, strong) ALCFormatContext *context;
@property (nonatomic, assign) SCPlayerState   controlState;
@property (nonatomic, strong) SCRender        *render;
@property (nonatomic, strong) MTKView         *mtkView;

@property (nonatomic, strong) SCVideoFrame *videoFrame;
@property (nonatomic, strong) SCAudioFrame *audioFrame;
@property (nonatomic, strong) ALCSynchronizer *syncor;

@end

@implementation ALCRenderLoop

- (void)dealloc {
    NSLog(@"render dealloc");
}

- (instancetype)initWithContext:(ALCFormatContext *)context frameQueue:(ALCFrameQueue *)frameQueue renderView:(MTKView *)view {
    if (self = [super init]) {
        _context = context;
        _manager = frameQueue;
        _syncor = [[ALCSynchronizer alloc] init];
        _render = [[SCRender alloc] init];
        
        self.mtkView.frame = view.bounds;
        [view insertSubview:self.mtkView atIndex:0];
        NSLayoutConstraint *c1 = [NSLayoutConstraint constraintWithItem:self.mtkView
                                                              attribute:NSLayoutAttributeTop
                                                              relatedBy:NSLayoutRelationEqual
                                                                 toItem:view
                                                              attribute:NSLayoutAttributeTop
                                                             multiplier:1.0
                                                               constant:0.0];
        NSLayoutConstraint *c2 = [NSLayoutConstraint constraintWithItem:self.mtkView
                                                              attribute:NSLayoutAttributeLeft
                                                              relatedBy:NSLayoutRelationEqual
                                                                 toItem:view
                                                              attribute:NSLayoutAttributeLeft
                                                             multiplier:1.0
                                                               constant:0.0];
        NSLayoutConstraint *c3 = [NSLayoutConstraint constraintWithItem:self.mtkView
                                                              attribute:NSLayoutAttributeBottom
                                                              relatedBy:NSLayoutRelationEqual
                                                                 toItem:view
                                                              attribute:NSLayoutAttributeBottom
                                                             multiplier:1.0
                                                               constant:0.0];
        NSLayoutConstraint *c4 = [NSLayoutConstraint constraintWithItem:self.mtkView
                                                              attribute:NSLayoutAttributeRight
                                                              relatedBy:NSLayoutRelationEqual
                                                                 toItem:view
                                                              attribute:NSLayoutAttributeRight
                                                             multiplier:1.0
                                                               constant:0.0];
        [view addConstraints:@[c1, c2, c3, c4]];
        [ALCAudioManager shared].delegate = self;
    }
    return self;
}

- (void)start {
    [[ALCAudioManager shared] play];
}

- (void)resume {
    [[ALCAudioManager shared] play];
    self.controlState = SCPlayerStatePlaying;
    self.mtkView.paused = NO;
}

- (void)pause {
    [[ALCAudioManager shared] stop];
    self.controlState = SCPlayerStatePaused;
    self.mtkView.paused = YES;
}

- (void)close {
    [[ALCAudioManager shared] stop];
    self.controlState = SCPlayerStateClosed;
}

- (void)rendering {
    if (!self.videoFrame) {
        self.videoFrame = [self.manager dequeueFrameByQueueIndex:SCTrackTypeVideo];
        if (!self.videoFrame) {
            return;
        }
    }
    if (self.videoFrame.flowDataType == SCFlowDataTypeDiscard) {
        self.videoFrame = nil;
        return;
    }
    if (![self.syncor shouldRenderVideoFrame:self.videoFrame.timeStamp duration:self.videoFrame.duration]) {
        
        return;
    }
    [self.render render:self.videoFrame drawIn:self.mtkView];
//    if ([self.delegate respondsToSelector:@selector(controlCenter:didRender:duration:)] && !self.isSeeking) {
//        [self.delegate controlCenter:self didRender:self.videoFrame.position duration:self.context.duration];
//    }
    self.videoFrame = nil;
}

- (void)drawInMTKView:(nonnull MTKView *)view {
    [self rendering];
}

- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size {}

#pragma mark - audio delegate

- (void)fetchoutputData:(AudioBufferList *)data numberOfFrames:(UInt32)numberOfFrames {
    bufferCopiedFrames = 0;
    UInt32 bufferLeftFrames = numberOfFrames;
    while (YES) {
       if (bufferLeftFrames <= 0) {
           break;
       }
       if (!self.audioFrame) {
           SCAudioFrame *frame = (SCAudioFrame *)[self.manager dequeueFrameByQueueIndex:SCTrackTypeAudio];
           if (!frame) {
               break;
           }
           self.audioFrame = frame;
       }
       if (!self.audioFrame || self.audioFrame.flowDataType == SCFlowDataTypeDiscard) {
           self.audioFrame = nil;
           break;
       }
       [self.syncor updateAudioClock:self.audioFrame.timeStamp];

       UInt32 currentFrameLeftFrames = self.audioFrame.numberOfSamples - currentFrameCopiedFrames;
       UInt32 framesToCopy           = MIN(bufferLeftFrames, currentFrameLeftFrames);
       UInt32 sizeToCopy             = framesToCopy * (UInt32)sizeof(float);
       UInt32 bufferOffset           = bufferCopiedFrames * (UInt32)sizeof(float);
       UInt32 currentFrameOffset     = currentFrameCopiedFrames * (UInt32)sizeof(float);
       for (int i = 0; i < data->mNumberBuffers; i++) { //wtf
           memcpy(data->mBuffers[i].mData + bufferOffset, self.audioFrame.data[i] + currentFrameOffset, sizeToCopy);
       }

       bufferCopiedFrames += framesToCopy;
       currentFrameCopiedFrames += framesToCopy;

       if (self.audioFrame.numberOfSamples <= currentFrameCopiedFrames) {
           self.audioFrame = nil;
           currentFrameCopiedFrames = 0;
       }
       bufferLeftFrames -= framesToCopy;
    }
    UInt32 framesCopied = numberOfFrames - bufferLeftFrames;
    UInt32 sizeCopied = framesCopied * (UInt32)sizeof(float);
    for (int i = 0; i < data->mNumberBuffers; i++) {
       UInt32 sizeLeft = data->mBuffers[i].mDataByteSize - sizeCopied;
       if (sizeLeft > 0) {
           memset(data->mBuffers[i].mData + sizeCopied, 0, sizeLeft);
       }
    }
}

- (MTKView *)mtkView {
    if (!_mtkView) {
        _mtkView                         = [[MTKView alloc] initWithFrame:CGRectZero];
        _mtkView.device                  = self.render.device;
        _mtkView.depthStencilPixelFormat = MTLPixelFormatInvalid;
        _mtkView.framebufferOnly         = false;
        _mtkView.colorPixelFormat        = MTLPixelFormatBGRA8Unorm;
        _mtkView.delegate                = self;
        _mtkView.translatesAutoresizingMaskIntoConstraints = NO;
    }
    return _mtkView;
}



@end