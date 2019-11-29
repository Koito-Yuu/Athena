//
//  ALCFrameQueue.h
//  Athena
//
//  Created by skylar on 2019/11/29.
//  Copyright © 2019 Theresa. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ALCTrack.h"
#import "SCFlowData.h"

@interface ALCFrameQueue : NSObject

- (void)flushFrameQueue:(SCTrackType)type;
- (void)frameQueueIsFull:(SCTrackType)type;
- (void)enqueueFrames:(NSArray<SCFlowData *> *)frames;
- (SCFlowData *)dequeueFrameByQueueIndex:(SCTrackType)type;
- (void)destory;

@end