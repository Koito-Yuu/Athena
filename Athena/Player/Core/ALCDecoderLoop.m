//
//  SCDecoderLayer.m
//  Athena
//
//  Created by Skylar on 2019/10/14.
//  Copyright © 2019 Theresa. All rights reserved.
//

#import "ALCDecoderLoop.h"
#import "ALCFormatContext.h"
#import "SCMarker.h"
#import "SCVideoDecoder.h"
#import "SCAudioDecoder.h"
#import "SCPacket.h"
#import "SCVideoFrame.h"
#import "SCPlayerState.h"
#import "SCAudioFrame.h"
#import "SCSWResample.h"
#import "ALCAudioDescriptor.h"
#import "ALCTrack.h"
#import "ALCFrameQueue.h"
#import "ALCPacketQueue.h"
#import "ALCCodecDescriptor.h"
#import "SCDecoder.h"

@interface ALCDecoderLoop ()

@property (nonatomic, strong) ALCPacketQueue *packetQueue;
@property (nonatomic, strong) ALCFrameQueue *frameQueue;

@property (nonatomic, assign) BOOL isSeeking;
@property (nonatomic, strong) ALCFormatContext *context;
@property (nonatomic, assign) SCPlayerState controlState;

@property (nonatomic, strong) NSOperationQueue *controlQueue;

@property (nonatomic, strong) SCVideoDecoder *videoDecoder;
@property (nonatomic, strong) SCAudioDecoder *audioDecoder;

@property (nonatomic, strong) SCSWResample *resample;

@property (nonatomic, strong) NSCondition *wakeup;

@end

@implementation ALCDecoderLoop

- (void)dealloc {
    NSLog(@"decoder dealloc");
}

- (instancetype)initWithContext:(ALCFormatContext *)context packetQueue:(ALCPacketQueue *)packetQueue frameQueue:(ALCFrameQueue *)frameQueue {
    if (self = [super init]) {
        _context      = context;
        _packetQueue  = packetQueue;
        _frameQueue   = frameQueue;
        _videoDecoder = [[SCVideoDecoder alloc] init];
        _audioDecoder = [[SCAudioDecoder alloc] init];
        _controlQueue = [[NSOperationQueue alloc] init];
        _wakeup       = [[NSCondition alloc] init];
    }
    return self;
}

- (void)start {
    NSOperation *op = [[NSInvocationOperation alloc] initWithTarget:self selector:@selector(decodeFrame) object:nil];
    [self.controlQueue addOperation:op];
    self.controlState = SCPlayerStatePlaying;
}

- (void)resume {
    self.controlState = SCPlayerStatePlaying;
    [self.wakeup lock];
    [self.wakeup broadcast];
    [self.wakeup unlock];
}

- (void)pause {
    self.controlState = SCPlayerStatePaused;
}

- (void)close {
    self.controlState = SCPlayerStateClosed;
    [self.controlQueue cancelAllOperations];
}

- (void)decodeFrame {
    while (self.controlState != SCPlayerStateClosed) {
        if (self.controlState == SCPlayerStatePaused) {
            [self.wakeup lock];
            [self.wakeup wait];
            [self.wakeup unlock];
            continue;
        }
        @autoreleasepool {
            SCPacket *packet = (SCPacket *)[self.packetQueue dequeuePacket];
            if (!packet) {
                continue;
            }
            [self.frameQueue frameQueueIsFull:packet.codecDescriptor.track.type];
            id<SCDecoder> decoder = packet.codecDescriptor.track.type == SCTrackTypeVideo ? self.videoDecoder : self.audioDecoder;
            if (packet.flowDataType == SCFlowDataTypeDiscard) {
                SCMarker *frame = [[SCMarker alloc] init];
                frame.mediaType = packet.codecDescriptor.track.type == SCTrackTypeVideo ? SCMediaTypeVideo : SCMediaTypeAudio;
                [self.frameQueue flushFrameQueue:packet.codecDescriptor.track.type];
                [self.frameQueue enqueueFrames:@[frame]];
                [decoder flush];
                continue;
            }
            if (packet.core->data != NULL && packet.core->stream_index >= 0) {
                NSArray *frames = [decoder decode:packet];
                NSMutableArray *temp = [NSMutableArray array];
                for (SCFlowData *frame in frames) {
                    frame.codecDescriptor = packet.codecDescriptor;
                    [temp addObject:[self process:frame]];
                }
                [self.frameQueue enqueueFrames:temp];
            }
        }
    }
}

- (SCFlowData *)process:(SCFlowData *)frame {
    if (frame.mediaType == SCMediaTypeVideo) {
        return [self processVideo:(SCVideoFrame *)frame];
    } else if (frame.mediaType == SCMediaTypeAudio) {
        return [self processAudio:(SCAudioFrame *)frame];
    } else {
        return nil;
    }
}

- (SCVideoFrame *)processVideo:(SCVideoFrame *)videoFrame {
    videoFrame.timeStamp = videoFrame.core->best_effort_timestamp * av_q2d(videoFrame.codecDescriptor.timebase);
    videoFrame.duration = videoFrame.core->pkt_duration * av_q2d(videoFrame.codecDescriptor.timebase);
    [videoFrame fillData];
    return videoFrame;
}

- (SCAudioFrame *)processAudio:(SCAudioFrame *)audioFrame {
    if (!self.resample) {
        self.resample = [[SCSWResample alloc] init];
        self.resample.inputDescriptor = [[ALCAudioDescriptor alloc] initWithFrame:audioFrame];
        self.resample.outputDescriptor = [[ALCAudioDescriptor alloc] init];
        [self.resample open];
    }
    audioFrame.numberOfSamples = audioFrame.core->nb_samples;
    int nb_samples = [self.resample write:audioFrame.core->data nb_samples:audioFrame.numberOfSamples];
    
    SCAudioFrame *frame = [SCAudioFrame audioFrameWithDescriptor:self.resample.outputDescriptor numberOfSamples:nb_samples];
    int nb_planes = self.resample.outputDescriptor.numberOfPlanes;
    
    uint8_t *data[8] = { NULL };
    for (int i = 0; i < nb_planes; i++) {
        data[i] = frame.core->data[i];
    }
    [self.resample read:data nb_samples:nb_samples];
    [frame fillData];
    frame.timeStamp = audioFrame.core->best_effort_timestamp * av_q2d(audioFrame.codecDescriptor.timebase);
    frame.duration = audioFrame.core->pkt_duration * av_q2d(audioFrame.codecDescriptor.timebase);
    return frame;
}

@end