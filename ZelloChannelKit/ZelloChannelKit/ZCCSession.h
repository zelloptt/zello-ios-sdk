//
//  ZCCSession.h
//  sdk
//
//  Created by Jim Pickering on 12/4/17.
//  Copyright © 2018-2024 Zello. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "ZCCStreamState.h"
#import "ZCCTypes.h"

NS_ASSUME_NONNULL_BEGIN

@class ZCCImageInfo;
@class ZCCIncomingVoiceConfiguration;
@class ZCCIncomingVoiceStream;
@class ZCCIncomingVoiceStreamInfo;
@class ZCCLocationInfo;
@class ZCCOutgoingVoiceConfiguration;
@class ZCCOutgoingVoiceStream;

/**
 * Callback for receiving the location that the Zello channels client is sending to the channel
 *
 * @param location if non-nil, this location is being sent to the channel. If nil, no location will
 *                 be sent to the channel and the error parameter contains information about what
 *                 went wrong
 * @param error if the user's location could not be found, contains information about what went wrong
 */
typedef void (^ZCCSentLocationContinuation)(ZCCLocationInfo * _Nullable location, NSError * _Nullable error);

/**
 * Describes the state of the Zello channels client's connection to the Zello channels server.
 */
typedef NS_ENUM(NSInteger, ZCCSessionState) {
  /// The session has encountered an error and is not connected to the server
  ZCCSessionStateError,

  /// The session is not connected to the server
  ZCCSessionStateDisconnected,

  /// The session is in the process of connecting to the server or channel
  ZCCSessionStateConnecting,

  /// The session has successfully connected to the server and channel
  ZCCSessionStateConnected
};

/// Describes why the session disconnected and is attempting to reconnect
typedef NS_ENUM(NSInteger, ZCCReconnectReason) {
  /// The network has changed
  ZCCReconnectReasonNetworkChange,

  /// Session was disconnected for another reason
  ZCCReconnectReasonUnknown
};

@protocol ZCCSessionDelegate;
@class ZCCVoiceStream;

/**
 * @abstract Connection to the Zello Channels server
 *
 * @discussion <code>ZCCSession</code> represents the connection to the Zello Channels server. Each
 * session you create connects to a single server and channel specified when the session is created.
 * If you are connecting as a specific user, you must also specify the username and password when
 * you create the session.
 */
@interface ZCCSession : NSObject

/**
 * @abstract The session's delegate receives callbacks when events occur in the session
 *
 * @discussion Delegate methods are called during connection and when messages are received from
 * the channel. The session is ready for use after <code>sessionDidConnect:</code> is called.
 */
@property (atomic, weak, nullable) id<ZCCSessionDelegate> delegate;

/**
 * @abstract The username the session uses to authenticate to the Zello server
 *
 * @discussion If not set in the initializer, will be the empty string
 */
@property (nonatomic, copy, readonly) NSString *username;

/**
 * @abstract The password the session uses to authenticate to the Zello server
 *
 * @discussion If not set in the initializer, will be the empty string
 */
@property (nonatomic, copy, readonly) NSString *password;

/**
 * @abstract The name of the channel to connect to
 */
@property (nonatomic, copy, readonly) NSString *channel;

/**
 * @abstract The URL of the server to connect to
 *
 * @discussion See <code>https://github.com/zelloptt/zello-channel-api/blob/master/API.md</code>
 * for valid Zello channels SDK URL patterns.
 */
@property (nonatomic, readonly) NSURL *address;

/**
 * @abstract The current state of the session object
 */
@property (atomic, readonly) ZCCSessionState state;

/**
 * @abstract The channel's online status
 */
@property (nonatomic, readonly) ZCCChannelStatus channelStatus;

/**
 * @abstract The number of users that are connected to the channel
 */
@property (nonatomic, readonly) NSInteger channelUsersOnline;

/**
 * @abstract Features supported by the currently connected channel
 *
 * @discussion If a message is sent that the server does not support in this channel, an error will
 * be returned through a delegate callback.
 */
@property (nonatomic, readonly) ZCCChannelFeatures channelFeatures;

/**
 * @abstract Collection of active streams
 */
@property (atomic, readonly, nonnull) NSArray <ZCCVoiceStream *> *activeStreams;

/**
 * @abstract How long to wait for a response from the Zello Channels server after sending a message
 *
 * @discussion Requests to the Zello Channels server will fail with a timed out error if <code>requestTimeout</code>
 * elapses without a response from the server. Defaults to 30 seconds.
 */
@property (atomic) NSTimeInterval requestTimeout;

/**
 * @abstract Unavailable default initializer; use a more specific one
 *
 * @discussion Use <code>initWithURL:channel:callbackQueue:</code> or <code>initWithURL:username:password:channel:callbackQueue:</code>
 * instead.
 */
- (instancetype)init NS_UNAVAILABLE;

/**
 * @abstract Initializes a connection session to the Zello channels server.
 *
 * @param url the address of the server to connect to
 *
 * @param token JWT value to authenticate your app to the Zello channels server.
 * See <code>https://github.com/zelloptt/zello-channel-api/blob/master/AUTH.md</code>
 * The token is required when connecting to consumer Zello, and optional when connecting to a Zello Work network.
 *
 * @param username the username of the account that is connecting. If <code>nil</code> or the empty
 * string, the session will attempt to connect anonymously.
 *
 * @param password the account's password
 *
 * @param channel the name of the channel to connect to
 *
 * @param queue the queue that <code>ZCCSessionDelegate</code> callbacks are called on. If <code>nil</code>,
 * the delegate callbacks will be called on the main queue.
 */
- (instancetype)initWithURL:(NSURL *)url authToken:(nullable NSString *)token username:(nullable NSString *)username password:(nullable NSString *)password channel:(NSString *)channel callbackQueue:(nullable dispatch_queue_t)queue NS_DESIGNATED_INITIALIZER;

/**
 * @abstract Initializes an anonymous connection session to the Zello channels server.
 *
 * @param url the address of the server to connect to
 *
 * @param token JWT value to authenticate your app to the Zello channels server.
 * See <code>https://github.com/zelloptt/zello-channel-api/blob/master/AUTH.md</code>
 *
 * @param channel the name of the channel to connect to
 *
 * @param queue the queue that <code>ZCCSessionDelegate</code> callbacks are called on. If <code>nil</code>,
 * the delegate callbacks will be called on the main queue.
 */
- (instancetype)initWithURL:(NSURL *)url authToken:(nullable NSString *)token channel:(NSString *)channel callbackQueue:(nullable dispatch_queue_t)queue;

/**
 * @abstract Asynchronously disconnect from the server.
 */
- (void)disconnect;

/**
 * @abstract Asynchronously connect to the server.
 */
- (void)connect;

/**
 * @abstract Sends an image message to the channel
 *
 * @discussion The Zello channels client will resize images that are larger than 1,280x1,280 to have a
 *             maximum height or width of 1,280 pixels. A 90x90 thumbnail will also be generated
 *             and sent before the full-sized image data is sent.
 *
 *             If an error is encountered while sending the image, the <code>ZCCSessionDelegate</code>
 *             method <code>session:didEncounterError:</code> will be called with an error describing
 *             what went wrong.
 *
 * @param image the image to send
 *
 * @return <code>YES</code> if the image metadata was sent successfully. <code>NO</code> if an error
 *         was encountered before the image metadata could be sent.
 */
- (BOOL)sendImage:(UIImage *)image;

/**
 * @abstract Sends an image message to a specific user in the channel
 *
 * @discussion The Zello channels client will resize images that are larger than 1,280x1,280 to have a
 *             maximum height or width of 1,280 pixels. A 90x90 thumbnail will also be generated
 *             and sent before the full-sized image data is sent.
 *
 *             If an error is encountered while sending the image, the <code>ZCCSessionDelegate</code>
 *             method <code>session:didEncounterError:</code> will be called with an error describing
 *             what went wrong.
 *
 * @param image the image to send
 *
 * @param username The user to send the image message to. Other users on the channel will not receive
 *                 the image.
 *
 * @return <code>YES</code> if the image metadata was sent successfully. <code>NO</code> if an error
 *         was encountered before the image metadata could be sent.
 */
- (BOOL)sendImage:(UIImage *)image toUser:(NSString *)username NS_SWIFT_NAME(sendImage(_:to:));

/**
 * @abstract Sends the user's current location to the channel
 *
 * @discussion When the user's location is found, <code>continuation</code> is also called with the
 * location so you can update your app to reflect the location they are reporting to the channel.
 *
 * @param continuation this block is called after the current location is found and reverse geocoding
 *                     is performed. If the location was found, it reports the location as well as
 *                     a reverse geocoded description if available. If an error was encountered
 *                     aquiring the location, it reports the error.
 */
- (BOOL)sendLocationWithContinuation:(nullable ZCCSentLocationContinuation)continuation NS_SWIFT_NAME(sendLocation(continuation:));

/**
 * @abstract Sends the user's current location to a specific user in the channel
 *
 * @discussion When the user's location is found, <code>continuation</code> is also called with the
 * location so you can update your app to reflect the location they are reporting to the channel.
 *
 * @param username The user to send the location to. Other users in the channel will not receive
 *                 the location.
 *
 * @param continuation This block is called after the current location is found and reverse geocoding
 *                     is performed. If the location was found, it reports the location as well as
 *                     a reverse geocoded description if available. If an error was encountered
 *                     aquiring the location, it reports the error.
 */
- (BOOL)sendLocationToUser:(NSString *)username continuation:(nullable ZCCSentLocationContinuation)continuation NS_SWIFT_NAME(sendLocation(to:continuation:));

/**
 * @abstract Sends a text message to the channel
 *
 * @param text the message to send
 */
- (void)sendText:(NSString *)text;

/**
 * @abstract Sends a text message to a specific user in the channel
 *
 * @param text the message to send
 *
 * @param username the username for the user to send the message to. Other users in the channel
 *                 won't receive the message.
 */
- (void)sendText:(NSString *)text toUser:(NSString *)username NS_SWIFT_NAME(sendText(_:to:));

/**
 * @abstract Creates and starts a voice stream to the server.
 *
 * @discussion The stream is created synchronously but started asynchronously, so it won't actually begin
 * transmitting until a <code>session:outgoingVoiceDidChangeState:</code> message is sent to the delegate.
 *
 * @return the stream that will be handling the voice message. If microphone permission has not been
 * granted to the app, returns nil.
 */
- (nullable ZCCOutgoingVoiceStream *)startVoiceMessage;

/**
 * @abstract Creates and starts a voice stream to a specific user in the channel.
 *
 * @discussion The stream is created synchronously but started asynchronously, so it won't actually begin
 * transmitting until a <code>session:outgoingVoiceDidChangeState:</code> message is sent to the delegate.
 *
 * @param username the username for the user to send the message to. Other users in the channel
 *                 won't receive the message.
 *
 * @return the stream that will be handling the voice message. If microphone permission has not been
 *         granted to the app, returns nil.
 */
- (nullable ZCCOutgoingVoiceStream *)startVoiceMessageToUser:(nonnull NSString *)username NS_SWIFT_NAME(startVoiceMessage(to:));

/**
 * @abstract Sends a message with a custom voice source
 *
 * @discussion Creates and starts a voice stream to the server using a custom voice source instead of the device
 * microphone. The Zello Channels SDK maintains a strong reference to the provided <code>ZCCVoiceSource</code>
 * object until the outgoing stream closes.
 *
 * @param sourceConfiguration specifies the voice source object for the message
 *
 * @return the stream that will be handling the voice message
 *
 * @exception NSInvalidArgumentException if <code>sourceConfiguration</code> specifies an unsupported
 * sample rate. Check <code>ZCCOutgoingVoiceConfiguration.supportedSampleRates</code> for supported
 * sample rates.
 */
- (ZCCOutgoingVoiceStream *)startVoiceMessageWithSource:(ZCCOutgoingVoiceConfiguration *)sourceConfiguration;

/**
 * @abstract Sends a message to a specific user in the channel with a custom voice source
 *
 * @discussion Creates and starts a voice stream to the server using a custom voice source instead
 * of the device microphone. The Zello Channels SDK maintains a strong reference to the provided
 * <code>ZCCVoiceSource</code> object until the outgoing stream closes.
 *
 * Only the user specified will receive the message.
 *
 * @param username the username for the user to send the message to. Other users in the channel won't
 *                 receive the message.
 *
 * @param sourceConfiguration specifies the voice source object for the message
 *
 * @return the stream that will be handling the voice message
 *
 * @exception NSInvalidArgumentException if <code>sourceConfiguration</code> specifies an unsupported sample rate. Check
 * <code>ZCCOutgoingVoiceConfiguration.supportedSampleRates</code> for supported sample rates.
 */
- (ZCCOutgoingVoiceStream *)startVoiceMessageToUser:(NSString *)username source:(ZCCOutgoingVoiceConfiguration *)sourceConfiguration NS_SWIFT_NAME(startVoiceMessage(to:source:));

@end

/**
 * When events occur in the Zello session, they are reported to the delegate.
 */
@protocol ZCCSessionDelegate <NSObject>

@optional
/**
 * @abstract Called when the session starts connecting
 *
 * @discussion Called after the session has begun connecting, before a connection to the server has been
 * established.
 *
 * @param session the session that is connecting
 */
- (void)sessionDidStartConnecting:(ZCCSession *)session;

@optional
/**
 * @abstract Called if an error is encountered before the session has connected to the channel
 *
 * @discussion This method is called when the session fails to connect to the Zello channel. <code>error</code>
 * describes the reason for the failure to connect.
 *
 * @param session the session that failed to connect
 *
 * @param error object describing why the session failed to connect. Most errors will be in the
 * <code>ZCCErrorDomain</code> error domain, and the error's <code>code</code> property will be
 * a <code>ZCCErrorCode</code> value.
 */
- (void)session:(ZCCSession *)session didFailToConnectWithError:(NSError *)error;

@optional
/**
 * @abstract Called when the session finishes connecting to the server and channel
 *
 * @discussion After <code>sessionDidConnect:</code> is called, the connection to the server is
 * fully established. You can now call <code>startVoiceMessage</code> to start speaking to the
 * channel, and will receive incoming voice messages when other users speak to the channel.
 *
 * <code>sessionDidConnect:</code> *is* called after an automatic reconnect, so be aware that your
 * delegate may see <code>sessionDidConnect:</code> called multiple times without <code><sessionDidDisconnect:></code>
 * being called. See <code><session:willReconnectForReason:></code> for more about automatic reconnection.
 *
 * @param session the session that has just connected
 */
- (void)sessionDidConnect:(ZCCSession *)session;

@optional
/**
 * @abstract Called when the session finishes disconnecting from the server
 *
 * @discussion If the session is disconnected due to a network change or other unexpected event,
 * this method is *not* called, and <code><session:willReconnectForReason:></code> is called instead.
 * In that case, the session automatically attempts to reconnect. You can prevent automatic reconnect
 * attempts by implementing <code>session:willReconnectForReason:</code> and returning <code>NO</code>.
 *
 * @param session the session that has disconnected
 */
- (void)sessionDidDisconnect:(ZCCSession *)session;

@optional
/**
 * @abstract Called when the session has become unexpectedly disconnected.
 *
 * @discussion When the session becomes unexpectedly disconnected from a network change or other
 * event, it will automatically attempt to reconnect with a randomized backoff delay. You can prevent
 * the session from reconnecting by implementing this method and returning <code>NO</code>.
 *
 * @param session the session that has disconnected
 *
 * @param reason The reason the session was disconnected
 *
 * @return <code>YES</code> to allow the reconnect attempt to continue, <code>NO</code> to prevent
 *         the session from attempting to reconnect.
 */
- (BOOL)session:(ZCCSession *)session willReconnectForReason:(ZCCReconnectReason)reason;

@optional
/**
 * @abstract called when the client receives a channel status update message from the server
 *
 * @discussion This method is called once shortly after the session connects to the channel, and
 *             again whenever another user connects to or disconnects from the channel. The delegate
 *             can read channel information from the session's properties.
 *
 * @param session the session that has new information about its channel
 */
- (void)sessionDidUpdateChannelStatus:(ZCCSession *)session;

@optional
/**
 * @abstract Called if an outgoing stream closes with an error
 *
 * @param session the session containing the stream
 *
 * @param stream the stream that has just closed
 *
 * @param error object describing the error that occurred
 */
- (void)session:(ZCCSession *)session outgoingVoice:(ZCCOutgoingVoiceStream *)stream didEncounterError:(NSError *)error;

@optional
/**
 * @abstract Called whenever the state of the outgoing stream changes
 *
 * @discussion The stream's new state is available as <code>stream.state</code>
 *
 * @param session the session containing the stream
 *
 * @param stream the stream whose state has changed. Its <code>state</code> property reflects the
 * new state of the stream.
 */
- (void)session:(ZCCSession *)session outgoingVoiceDidChangeState:(ZCCOutgoingVoiceStream *)stream;

@optional
/**
 * @abstract Called periodically while transmitting audio to report the progress of the stream
 *
 * @discussion This callback is called frequently, so avoid doing heavy processing work in response
 * to it. The <code>position</code> reported is in media time from the beginning of the stream, not
 * wall time.
 *
 * @param session the session containing the stream that is reporting progress
 *
 * @param stream the stream that is reporting its progress
 *
 * @param position time in seconds of voice since the stream started. This may not match wall time,
 * especially if the stream has a custom voice source that is providing voice data from a file or
 * another source that does not run in real-time.
 */
- (void)session:(ZCCSession *)session outgoingVoice:(ZCCOutgoingVoiceStream *)stream didUpdateProgress:(NSTimeInterval)position;

@optional
/**
 * @abstract Implement this method to perform custom handling of incoming voice data
 *
 * @discussion If this method is implemented by your session delegate, you can override the Zello
 * Channels SDK's default processing of incoming voice streams. This method will be called when
 * another user begins speaking on the channel. The <code>streamInfo</code> object describes the
 * channel and the user who has begun speaking. Your implementation can return <code>nil</code> to
 * tell the Zello Channels SDK to play the incoming stream through the device speaker. If you want
 * to perform different handling of the audio, you can return a <code><ZCCIncomingVoiceConfiguration></code>
 * object instead, with a reference to a custom <code><ZCCVoiceReceiver></code>.
 *
 * If this method is not implemented or returns <code>nil</code>, the Zello Channels SDK will perform
 * its default incoming voice handling and play the audio through the current output audio route.
 *
 * @param session the session that is about to open a new incoming voice stream
 *
 * @param streamInfo an object describing the voice source. You can use this information to determine
 * whether to override the default audio handling.
 *
 * @return a configuration object specifying a custom voice receiver to handle incoming voice data.
 * If you return nil instead of a configuration object, the stream will play through the current
 * audio output route as normal.
 */
- (nullable ZCCIncomingVoiceConfiguration *)session:(ZCCSession *)session incomingVoiceWillStart:(ZCCIncomingVoiceStreamInfo *)streamInfo;

@optional
/**
 * @abstract Called when an incoming stream starts
 *
 * @discussion When another user begins speaking in the channel, this method is called to provide
 * your app with the new incoming voice stream.
 *
 * @param session the session containing the new stream
 *
 * @param stream the new stream
 */
- (void)session:(ZCCSession *)session incomingVoiceDidStart:(ZCCIncomingVoiceStream *)stream;

@optional
/**
 * @abstract Called when an incoming stream stops
 *
 * @discussion This method is called when a user that was speaking on the channel stops speaking,
 * and the stream containing their voice data closes.
 *
 * @param session the session containing the stream that just stopped
 *
 * @param stream the stream that just stopped
 */
- (void)session:(ZCCSession *)session incomingVoiceDidStop:(ZCCIncomingVoiceStream *)stream;

@optional
/**
 * @abstract Called periodically while receiving audio
 *
 * @discussion This callback is called frequently, so avoid doing heavy processing work in response
 * to it. The <code>position</code> reported is in media time from the beginning of the stream, not
 * wall time.
 *
 * @param session the session containing the stream that is reporting progress
 *
 * @param stream the stream that is reporting its progress
 *
 * @param position time in seconds of voice since the stream started. This may not match wall time,
 * especially if the stream has a custom voice receiver that is not passing audio through to the
 * device speaker.
 */
- (void)session:(ZCCSession *)session incomingVoice:(ZCCIncomingVoiceStream *)stream didUpdateProgress:(NSTimeInterval)position;

@optional
/**
 * @abstract Called when an image message is received
 *
 * @discussion This method will probably be called twice for each image message that is received:
 *             once with only the thumbnail present in the image info object, and once with both
 *             the thumbnail and the full-sized image present. <code>image.imageId</code> will be
 *             the same for all calls related to the same image message from a sender.
 *
 * @param session the session that received an image message
 *
 * @param image a container object with information about the sender, message id, and the image
 *        itself
 */
- (void)session:(ZCCSession *)session didReceiveImage:(ZCCImageInfo *)image;

@optional
/**
 * @abstract Called when a location message is received
 *
 * @param session the session that received a location message
 *
 * @param location an object describing the sender's location
 *
 * @param sender the username of the sender
 */
- (void)session:(ZCCSession *)session didReceiveLocation:(ZCCLocationInfo *)location from:(NSString *)sender;

@optional
/**
 * @abstract Called when a text message is received
 *
 * @param session the session that received a text message
 *
 * @param message the message that was received
 *
 * @param sender the username of the user that sent the message
 */
- (void)session:(ZCCSession *)session didReceiveText:(NSString *)message from:(NSString *)sender;

@optional
/**
 * @abstract This delegate callback reports informational errors from the session
 *
 * @discussion Called when the session encounters an error. The errors reported with this callback
 * are informational and do not mean that the session is no longer functional.
 *
 * @param session the session that encountered an error. This session should still be functional.
 *
 * @param error the error that was encountered by the session
 */
- (void)session:(ZCCSession *)session didEncounterError:(NSError *)error;


@end

NS_ASSUME_NONNULL_END
