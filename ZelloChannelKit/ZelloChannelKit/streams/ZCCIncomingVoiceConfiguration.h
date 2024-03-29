//
//  ZCCIncomingVoiceConfiguration.h
//  ZelloChannelKit
//
//  Created by Greg Cooksey on 3/5/18.
//  Copyright © 2018 Zello. All rights reserved.
//

#import <CoreAudio/CoreAudioTypes.h>
#import <Foundation/Foundation.h>

@class ZCCIncomingVoiceStream;

NS_ASSUME_NONNULL_BEGIN

/**
 * Implement <code>ZCCVoiceReceiver</code> to provide custom handling for incoming voice data.
 *
 * Your voice receiver will receive a <code>prepareWithAudioDescription:stream:</code> message when the incoming
 * stream has finished opening. Then it will receive <code>receiveAudio:stream:</code> messages repeatedly as new
 * audio comes in from the channels server. When the stream is closing, it will receive a
 * <code>stopReceivingAudio:</code> message.
 *
 * @warning All <code>ZCCVoiceReceiver</code> methods are called on an arbitrary dispatch queue.
 */
@protocol ZCCVoiceReceiver <NSObject>

/**
 * @abstract Called when an incoming stream opens
 *
 * @discussion When an incoming stream finishes opening, you will receive a <code>prepareWithAudioDescription:stream:</code>
 * message. Use the <code>description</code> to prepare your audio handling code.
 *
 * @param description Describes the format of the data in the buffers that you will receive in
 * <code>receiveAudio:stream:</code> calls. Save this object so you know how to process the audio data.
 *
 * @param stream the stream that has just opened
 */
- (void)prepareWithAudioDescription:(AudioStreamBasicDescription)description stream:(ZCCIncomingVoiceStream *)stream;

/**
 * @abstract Your voice receiver will receive this message periodically as new data comes in from the channels
 * server.
 *
 * @param audioData a buffer of audio data matching the format in the <code>AudioStreamBasicDescription</code>
 * sent in <code>prepareWithAudioDescription:stream:</code>
 *
 * @param stream the stream that the data is coming from
 */
- (void)receiveAudio:(NSData *)audioData stream:(ZCCIncomingVoiceStream *)stream;

/**
 * @abstract Called when the incoming stream has ended.
 *
 * @discussion After this method is called, no further methods will be called on your voice receiver.
 *
 * @param stream the stream that is closing
 */
- (void)stopReceivingAudio:(ZCCIncomingVoiceStream *)stream;
@end

/**
 * Describes an incoming voice stream. The stream has not yet opened, but you can use this information
 * to determine whether to provide a custom voice receiver or let the Zello channels SDK play the
 * voice through the device speaker by default.
 */
@interface ZCCIncomingVoiceStreamInfo : NSObject

/**
 * @abstract The name of the channel that the stream is originating from
 */
@property (nonatomic, copy, readonly) NSString *channel;

/**
 * @abstract The username of the speaker
 */
@property (nonatomic, copy, readonly) NSString *sender;

@end

/**
 * Return a <code>ZCCIncomingVoiceConfiguration</code> object from <code>-[ZCCSessionDelegate
 * session:incomingVoiceStreamWillStart:]</code> to provide custom handling of the incoming audio data.
 */
@interface ZCCIncomingVoiceConfiguration : NSObject <NSCopying>

/**
 * Whether the incoming voice stream should be played through the speaker as well as sent to the
 * custom voice receiver object.
 */
@property (nonatomic) BOOL playThroughSpeaker;

/**
 * Custom voice receiver object. Its methods will be called when new voice data arrives from the
 * Zello Channels system.
 *
 * The Zello Channels SDK holds a strong reference to this object until the associated incoming
 * voice stream closes and <code>stop</code> is called on the receiver object.
 */
@property (nonatomic, strong) id<ZCCVoiceReceiver> receiver;

@end

NS_ASSUME_NONNULL_END
