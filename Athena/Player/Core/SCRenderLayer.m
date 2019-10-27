//
//  SCRenderLayer.m
//  Athena
//
//  Created by Skylar on 2019/10/14.
//  Copyright © 2019 Theresa. All rights reserved.
//

#import <MetalKit/MetalKit.h>
#import "SCRenderLayer.h"
#import "SCDemuxLayer.h"
#import "SCFormatContext.h"
#import "SCControl.h"
#import "SCFrameQueue.h"
#import "SCAudioFrame.h"
#import "SCVideoFrame.h"
#import "SCRender.h"
#import "SCSynchronizer.h"
#import "SCAudioManager.h"
#import "SCPlayerState.h"
#import "SCDecoderLayer.h"

@interface SCRenderLayer () <SCAudioManagerDelegate, MTKViewDelegate, DecodeToQueueProtocol>

@property (nonatomic, strong) SCFrameQueue *videoFrameQueue;
@property (nonatomic, strong) SCFrameQueue *audioFrameQueue;

@property (nonatomic, strong) SCFormatContext *context;
@property (nonatomic, assign) SCPlayerState   controlState;
@property (nonatomic, strong) SCRender        *render;
@property (nonatomic, strong) MTKView         *mtkView;

@property (nonatomic, strong) SCVideoFrame *videoFrame;
@property (nonatomic, strong) SCAudioFrame *audioFrame;
@property (nonatomic, strong) SCSynchronizer *syncor;

@end

@implementation SCRenderLayer

- (instancetype)initWithContext:(SCFormatContext *)context decoderLayer:(SCDecoderLayer *)decoderLayer renderView:(MTKView *)view {
    if (self = [super init]) {
        _context = context;
        _videoFrameQueue  = [[SCFrameQueue alloc] init];
        _audioFrameQueue  = [[SCFrameQueue alloc] init];

        _render                          = [[SCRender alloc] init];
        _mtkView                         = view;
        _mtkView.device                  = _render.device;
        _mtkView.depthStencilPixelFormat = MTLPixelFormatInvalid;
        _mtkView.framebufferOnly         = false;
        _mtkView.colorPixelFormat        = MTLPixelFormatBGRA8Unorm;
        _mtkView.delegate                = self;
        
        [SCAudioManager shared].delegate = self;
        
        decoderLayer.delegate = self;
        _syncor = [[SCSynchronizer alloc] init];
    }
    return self;
}

- (void)start {
    [[SCAudioManager shared] play];
}

- (void)resume {
    [[SCAudioManager shared] play];
    self.controlState = SCPlayerStatePlaying;
    self.mtkView.paused = NO;
}

- (void)pause {
    [[SCAudioManager shared] stop];
    self.controlState = SCPlayerStatePaused;
    self.mtkView.paused = YES;
}

- (void)close {
    [[SCAudioManager shared] stop];
    self.controlState = SCPlayerStateClosed;
}

- (void)rendering {
    if (!self.videoFrame) {
        self.videoFrame = [self.videoFrameQueue dequeueFrame];
        if (!self.videoFrame || self.videoFrame.type == SCFrameTypeDiscard) {
            self.videoFrame = nil;
            return;
        }
    }
    if (![self.syncor shouldRenderVideoFrame:self.videoFrame.position duration:self.videoFrame.duration]) {
        return;
    }
    [self.render render:(id<SCRenderDataInterface>)self.videoFrame drawIn:self.mtkView];
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

- (void)fetchoutputData:(SInt16 *)outputData numberOfFrames:(UInt32)numberOfFrames numberOfChannels:(UInt32)numberOfChannels {
    @autoreleasepool {
        while (numberOfFrames > 0) {
            if (!self.audioFrame) {
                self.audioFrame = (SCAudioFrame *)[self.audioFrameQueue dequeueFrame];
            }
            if (!self.audioFrame || self.audioFrame.type == SCFrameTypeDiscard) {
                memset(outputData, 0, numberOfFrames * numberOfChannels * sizeof(SInt16));
                self.audioFrame = nil;
                break;
            }
            [self.syncor updateAudioClock:self.audioFrame.position];
            
            const Byte * bytes = (Byte *)self.audioFrame.sampleData.bytes + self.audioFrame->output_offset;
            const NSUInteger bytesLeft = self.audioFrame.sampleData.length - self.audioFrame->output_offset;
            const NSUInteger frameSizeOf = numberOfChannels * sizeof(SInt16);
            const NSUInteger bytesToCopy = MIN(numberOfFrames * frameSizeOf, bytesLeft);
            const NSUInteger framesToCopy = bytesToCopy / frameSizeOf;
            
            memcpy(outputData, bytes, bytesToCopy);
            numberOfFrames -= framesToCopy;
            outputData += framesToCopy * numberOfChannels;
            
            if (bytesToCopy < bytesLeft) {
                self.audioFrame->output_offset += bytesToCopy;
            } else {
                self.audioFrame = nil;
            }
        }
    }
}



- (void)audioFrameQueueFlush {
    [self.audioFrameQueue flush];
}

- (BOOL)audioFrameQueueIsFull {
    return self.audioFrameQueue.count > 5;
}

- (void)enqueueAudioFrames:(nonnull NSArray<SCFrame *> *)frames {
    [self.audioFrameQueue enqueueFramesAndSort:frames];
}

- (void)enqueueVideoFrames:(nonnull NSArray<SCFrame *> *)frames {
    [self.videoFrameQueue enqueueFramesAndSort:frames];
}

- (void)videoFrameQueueFlush {
    [self.videoFrameQueue flush];
}

- (BOOL)videoFrameQueueIsFull {
    return self.videoFrameQueue.count > 5;
}

@end
