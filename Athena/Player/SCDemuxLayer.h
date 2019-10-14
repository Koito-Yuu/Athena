//
//  DemuxLayer.h
//  Athena
//
//  Created by Skylar on 2019/10/14.
//  Copyright © 2019 Theresa. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SCFormatContext;
@class SCPacketQueue;

@interface SCDemuxLayer : NSObject

- (instancetype)initWithContext:(SCFormatContext *)context
                          video:(SCPacketQueue *)videoPacketQueue
                          audio:(SCPacketQueue *)audioPacketQueue;

- (void)start;
- (void)resume;
- (void)pause;
- (void)close;
- (void)seekingTime:(NSTimeInterval)percentage;

@end

NS_ASSUME_NONNULL_END
