//
//  ZCCSocket.m
//  sdk
//
//  Created by Greg Cooksey on 1/31/18.
//  Copyright © 2018 Zello. All rights reserved.
//

#import "ZCCSRWebSocket.h"
#import "ZCCChannelInfo.h"
#import "ZCCSocket.h"
#import "ZCCCommands.h"
#import "ZCCErrors.h"
#import "ZCCImageHeader.h"
#import "ZCCImageMessage.h"
#import "ZCCLocationInfo+Internal.h"
#import "ZCCProtocol.h"
#import "ZCCQueueRunner.h"
#import "ZCCStreamParams.h"
#import "ZCCWebSocketFactory.h"

typedef NS_ENUM(NSInteger, ZCCSocketRequestType) {
  ZCCSocketRequestTypeLogon = 1,
  ZCCSocketRequestTypeStartStream,
  ZCCSocketRequestTypeImageMessage,
  ZCCSocketRequestTypeLocationMessage,
  ZCCSocketRequestTypeTextMessage
};

@interface ZCCSocketResponseCallback : NSObject
@property (nonatomic, readonly) NSInteger sequenceNumber;
@property (nonatomic, readonly) ZCCSocketRequestType requestType;
@property (nonatomic, strong) ZCCLogonCallback logonCallback;
@property (nonatomic, strong) ZCCStartStreamCallback startStreamCallback;
@property (nonatomic, strong) ZCCSendImageCallback sendImageCallback;
/**
 * @warning simpleCommandCallback is called on an arbitrary thread/queue, so if it needs to perform
 *          work on a particular queue, it is responsible for dispatching to that queue.
 */
@property (nonatomic, strong) ZCCSimpleCommandCallback simpleCommandCallback;
@property (nonatomic, strong) dispatch_block_t timeoutBlock;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithSequenceNumber:(NSInteger)sequenceNumber type:(ZCCSocketRequestType)type NS_DESIGNATED_INITIALIZER;
@end

@implementation ZCCSocketResponseCallback
- (instancetype)initWithSequenceNumber:(NSInteger)sequenceNumber type:(ZCCSocketRequestType)type {
  self = [super init];
  if (self) {
    _sequenceNumber = sequenceNumber;
    _requestType = type;
  }
  return self;
}
@end

@interface ZCCSocket () <ZCCSRWebSocketDelegate>
@property (nonatomic, strong, readonly) ZCCQueueRunner *workRunner;

/// @warning Only access nextSequenceNumber from the workRunner's queue
@property (nonatomic) NSInteger nextSequenceNumber;

@property (nonatomic, strong, readonly) ZCCSRWebSocket *webSocket;

@property (nonatomic, strong) NSMutableDictionary <NSNumber *, ZCCSocketResponseCallback *> *callbacks;

@property (nonatomic, strong) ZCCQueueRunner *delegateRunner;

@end

@implementation ZCCSocket

#pragma mark - NSObject

- (instancetype)initWithURL:(NSURL *)url {
  return [self initWithURL:url socketFactory:[[ZCCWebSocketFactory alloc] init]];
}

- (instancetype)initWithURL:(NSURL *)url socketFactory:(ZCCWebSocketFactory *)factory {
  self = [super init];
  if (self) {
    _callbacks = [[NSMutableDictionary alloc] init];
    _delegateRunner = [[ZCCQueueRunner alloc] initWithName:@"ZCCSocketDelegate"];
    _webSocket = [factory socketWithURL:url];
    _webSocket.delegate = self;
    _workRunner = [[ZCCQueueRunner alloc] initWithName:@"ZCCSocket"];
  }
  return self;
}

- (void)dealloc {
  _webSocket.delegate = nil;
}

#pragma mark - Properties

- (void)setDelegateQueue:(dispatch_queue_t)queue {
  if (queue) {
    self.delegateRunner = [[ZCCQueueRunner alloc] initWithQueue:queue];
  } else {
    self.delegateRunner = [[ZCCQueueRunner alloc] initWithName:@"ZCCSocketDelegate"];
  }
}

#pragma mark - Networking

- (void)close {
  [self.webSocket close];
}

- (void)open {
  [self.webSocket open];
}

- (void)sendImage:(ZCCImageMessage *)message callback:(ZCCSendImageCallback)callback timeoutAfter:(NSTimeInterval)timeout {
  [self.workRunner runSync:^{
    [self sendRequest:^NSString *(NSInteger seqNo) {
      return [ZCCCommands sendImage:message sequenceNumber:seqNo];
    } type:ZCCSocketRequestTypeImageMessage timeout:timeout prepareCallback:^(ZCCSocketResponseCallback *responseCallback) {
      responseCallback.sendImageCallback = callback;
    } failBlock:^(NSString *failureReason) {
      callback(NO, 0, failureReason);
    } timeoutBlock:^(ZCCSocketResponseCallback *responseCallback) {
      responseCallback.sendImageCallback(NO, 0, @"Send image timed out");
    }];
  }];
}

- (void)sendImageData:(ZCCImageMessage *)message imageId:(UInt32)imageId {
  NSData *thumbnailDataMessage = [ZCCCommands messageForImageThumbnailData:message imageId:imageId];
  NSError *error = nil;
  if (![self.webSocket sendData:thumbnailDataMessage error:&error]) {
    // TODO: Return error to caller
    NSLog(@"[ZCC] Failed to send thumbnail: %@", error);
  }

  NSData *imageDataMessage = [ZCCCommands messageForImageData:message imageId:imageId];
  if (![self.webSocket sendData:imageDataMessage error:&error]) {
    // TODO: Return error to caller
    NSLog(@"[ZCC] Failed to send image: %@", error);
  }
}

- (void)sendLogonWithAuthToken:(NSString *)authToken
                  refreshToken:(NSString *)refreshToken
                       channel:(NSString *)channel
                      username:(NSString *)username
                      password:(NSString *)password
                      callback:(ZCCLogonCallback)callback
                  timeoutAfter:(NSTimeInterval)timeout {
  [self.workRunner runSync:^{
    [self sendRequest:^NSString *(NSInteger seqNo) {
      return [ZCCCommands logonWithSequenceNumber:seqNo authToken:authToken refreshToken:refreshToken channel:channel username:username password:password];
    } type:ZCCSocketRequestTypeLogon timeout:timeout prepareCallback:^(ZCCSocketResponseCallback *responseCallback) {
      responseCallback.logonCallback = callback;
    } failBlock:^(NSString *failureReason) {
      callback(NO, nil, failureReason);
    } timeoutBlock:^(ZCCSocketResponseCallback *responseCallback) {
      responseCallback.logonCallback(NO, nil, @"Timed out");
    }];
  }];
}

- (void)sendLocation:(ZCCLocationInfo *)location recipient:(NSString *)username timeoutAfter:(NSTimeInterval)timeout {
  ZCCSimpleCommandCallback callback = ^(BOOL success, NSString *errorMessage) {
    if (!success && errorMessage) {
      [self reportError:errorMessage];
    }
  };

  [self.workRunner runSync:^{
    [self sendRequest:^NSString *(NSInteger seqNo) {
      return [ZCCCommands sendLocation:location sequenceNumber:seqNo recipient:username];
    } type:ZCCSocketRequestTypeLocationMessage timeout:timeout prepareCallback:^(ZCCSocketResponseCallback *responseCallback) {
      responseCallback.simpleCommandCallback = callback;
    } failBlock:^(NSString *failureReason) {
      callback(NO, failureReason);
    } timeoutBlock:^(ZCCSocketResponseCallback *responseCallback) {
      responseCallback.simpleCommandCallback(NO, @"Send location timed out");
    }];
  }];
}

- (void)sendTextMessage:(NSString *)message recipient:(NSString *)username timeoutAfter:(NSTimeInterval)timeout {
  ZCCSimpleCommandCallback callback = ^(BOOL success, NSString *errorMessage) {
    if (!success && errorMessage) {
      [self reportError:errorMessage];
    }
  };

  [self.workRunner runSync:^{
    [self sendRequest:^NSString *(NSInteger seqNo) {
      return [ZCCCommands sendText:message sequenceNumber:seqNo recipient:username];
    } type:ZCCSocketRequestTypeTextMessage timeout:timeout prepareCallback:^(ZCCSocketResponseCallback *responseCallback) {
      responseCallback.simpleCommandCallback = callback;
    } failBlock:^(NSString *failureReason) {
      callback(NO, failureReason);
    } timeoutBlock:^(ZCCSocketResponseCallback *responseCallback) {
      responseCallback.simpleCommandCallback(NO, @"Send text timed out");
    }];
  }];
}

- (void)sendStartStreamWithParams:(ZCCStreamParams *)params
                           recipient:(NSString *)username
                         callback:(nonnull ZCCStartStreamCallback)callback
                     timeoutAfter:(NSTimeInterval)timeout {
  [self.workRunner runSync:^{
    [self sendRequest:^(NSInteger seqNo) {
      return [ZCCCommands startStreamWithSequenceNumber:seqNo params:params recipient:username];
    } type:ZCCSocketRequestTypeStartStream timeout:timeout prepareCallback:^(ZCCSocketResponseCallback *responseCallback) {
      responseCallback.startStreamCallback = callback;
    } failBlock:^(NSString *failureReason) {
      callback(NO, 0, failureReason);
    } timeoutBlock:^(ZCCSocketResponseCallback *responseCallback) {
      responseCallback.startStreamCallback(NO, 0, @"Timed out");
    }];
  }];
}

/**
 * This method manages the boilerplate of sending messages to the WSS server that we expect responses
 * to. It takes a number of block parameters that serve to fill in the details of the message we
 * send to the server and the handling we do when we receive a response.
 *
 * @warning Only call from workRunner
 *
 * @param prepareRequest this block is called with the sequence number that should be used for the
 * request. It should return a string to be sent to the server.
 *
 * @param requestType the type of the request. Categorizes the ZCCSocketRequestCallback object that
 * represents the pending request.
 *
 * @param timeout if > 0, specifies the amount of time to wait after sending the message to the
 * server before calling the timedOut block.
 *
 * @param prepareCallback this block is called with the ZCCSocketRequestCallback object that will
 * be used to handle responses from the server. The block should set the appropriate callback
 * property of the ZCCSocketRequestCallback object and do any other necessary preparation.
 *
 * @param fail this block is called if the request fails to send in the same call context
 * as sendRequest:... was called
 *
 * @param timedOut this block is called if timeout > 0 and the request is still outstanding when
 * the timeout expires. Its argument is the response callback object for this request.
 */
- (void)sendRequest:(NSString * (^)(NSInteger seqNo))prepareRequest
               type:(ZCCSocketRequestType)requestType
            timeout:(NSTimeInterval)timeout
    prepareCallback:(void (^)(ZCCSocketResponseCallback *responseCallback))prepareCallback
          failBlock:(void (^)(NSString *failureReason))fail
       timeoutBlock:(void (^)(ZCCSocketResponseCallback *responseCallback))timedOut {
  NSInteger seqNo = [self incrementedSequenceNumber];
  NSString *request = prepareRequest(seqNo);
  NSError *error = nil;
  if (![self.webSocket sendString:request error:&error]) {
    if (error) {
      [self.delegateRunner runAsync:^{
        fail(error.localizedDescription);
      }];
      return;
    }

    [self.delegateRunner runAsync:^{
      fail(@"Failed to send");
    }];
    return;
  }

  dispatch_block_t timeoutBlock = nil;
  if (timeout > 0) {
    timeoutBlock = dispatch_block_create(0, ^{
      ZCCSocketResponseCallback *responseCallback = self.callbacks[@(seqNo)];
      if (responseCallback) {
        [self.delegateRunner runAsync:^{
          timedOut(responseCallback);
        }];
        self.callbacks[@(seqNo)] = nil;
      }
    });
    [self.workRunner run:timeoutBlock after:timeout];
  }

  ZCCSocketResponseCallback *responseCallback = [[ZCCSocketResponseCallback alloc] initWithSequenceNumber:seqNo type:requestType];
  prepareCallback(responseCallback);
  responseCallback.timeoutBlock = timeoutBlock;
  self.callbacks[@(seqNo)] = responseCallback;
}

- (void)sendStopStream:(NSUInteger)streamId {
  [self.workRunner runSync:^{
    NSInteger seqNo = [self incrementedSequenceNumber];
    NSString *stopCommand = [ZCCCommands stopStreamWithSequenceNumber:seqNo streamId:streamId];
    NSError *error = nil;
    if (![self.webSocket sendString:stopCommand error:&error]) {
      // TODO: Add a way to return error instead of logging and silently failing
      NSLog(@"[ZCC] Failed to send stop stream: %@", error);
    }
  }];
}

- (void)sendAudioData:(NSData *)data stream:(NSUInteger)streamId {
  NSData *dataMessage = [ZCCCommands messageForAudioData:data stream:streamId];
  NSError *error = nil;
  if (![self.webSocket sendData:dataMessage error:&error]) {
    // TODO: Add a way to return error instead of logging and silently failing
    NSLog(@"[ZCC] Failed to send audio: %@", error);
  }
}

#pragma mark - SRWebSocketDelegate

- (void)webSocketDidOpen:(ZCCSRWebSocket *)webSocket {
  id<ZCCSocketDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(socketDidOpen:)]) {
    [self.delegateRunner runAsync:^{
      [delegate socketDidOpen:self];
    }];
  }
}

- (void)webSocket:(ZCCSRWebSocket *)webSocket didFailWithError:(NSError *)error {
  id<ZCCSocketDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(socketDidClose:withError:)]) {
    // TODO: Wrap error in something more meaningful to our SDK?
    [self.delegateRunner runAsync:^{
      [delegate socketDidClose:self withError:error];
    }];
  }
}

- (void)webSocket:(ZCCSRWebSocket *)webSocket didCloseWithCode:(NSInteger)code reason:(nullable NSString *)reason wasClean:(BOOL)wasClean {
  id<ZCCSocketDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(socketDidClose:withError:)]) {
    // Anything other than code 1000 (ZCCSRStatusCodeNormal) is an error so we should report it to our delegate
    NSError *error = nil;
    if (code != ZCCSRStatusCodeNormal) {
      NSDictionary *errorInfo = nil;
      if (reason) {
        errorInfo = @{ZCCErrorWebSocketReasonKey:reason};
      }
      error = [NSError errorWithDomain:ZCCErrorDomain code:ZCCErrorCodeWebSocketError userInfo:errorInfo];
    }

    [self.delegateRunner runAsync:^{
      [delegate socketDidClose:self withError:error];
    }];
  }
}

- (void)webSocket:(ZCCSRWebSocket *)webSocket didReceiveMessageWithString:(NSString *)string {
  [self.workRunner runSync:^{
    NSError *error = nil;
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (!json) {
      id<ZCCSocketDelegate> delegate = self.delegate;
      if ([delegate respondsToSelector:@selector(socket:didEncounterErrorParsingMessage:)]) {
        [self.delegateRunner runAsync:^{
          NSMutableDictionary *info = [@{ZCCServerInvalidMessageKey:string} mutableCopy];
          if (error) {
            info[NSUnderlyingErrorKey] = error;
          }
          NSError *parseError = [NSError errorWithDomain:ZCCErrorDomain code:ZCCErrorCodeBadResponse userInfo:info];
          [delegate socket:self didEncounterErrorParsingMessage:parseError];
        }];
      }
      return;
    }

    id seqNo = json[ZCCSeqKey];
    if ([seqNo isKindOfClass:[NSNumber class]]) {
      [self handleResponse:json original:string];
      return;
    }
    id command = json[ZCCCommandKey];
    if (![command isKindOfClass:[NSString class]]) {
      [self reportInvalidJSONInMessage:nil key:@"command" errorDescription:@"command missing or not string" original:string];
      return;
    }

    if ([command isEqualToString:ZCCEventOnChannelStatus]) {
      [self handleChannelStatus:json original:string];
      return;
    }
    if ([command isEqualToString:ZCCEventOnStreamStart]) {
      [self handleStreamStart:json original:string];
      return;
    }
    if ([command isEqualToString:ZCCEventOnStreamStop]) {
      [self handleStreamStop:json original:string];
      return;
    }
    if ([command isEqualToString:ZCCEventOnError]) {
      [self handleError:json original:string];
      return;
    }
    if ([command isEqualToString:ZCCEventOnLocation]) {
      [self handleLocation:json original:string];
      return;
    }
    if ([command isEqualToString:ZCCEventOnTextMessage]) {
      [self handleTextMessage:json original:string];
      return;
    }
    if ([command isEqualToString:ZCCEventOnImage]) {
      [self handleImage:json original:string];
      return;
    }

    [self reportInvalidJSONInMessage:command key:ZCCCommandKey errorDescription:@"unrecognized command" original:string];
  }];
}

- (void)handleResponse:(NSDictionary *)encoded original:(NSString *)original {
  NSNumber *seq = encoded[ZCCSeqKey];
  ZCCSocketResponseCallback *callback = self.callbacks[seq];
  if (!callback) {
    return;
  }
  switch (callback.requestType) {
    case ZCCSocketRequestTypeLogon:
      [self handleLogonResponse:encoded callback:callback original:original];
      break;

    case ZCCSocketRequestTypeStartStream:
      [self handleStartStreamResponse:encoded callback:callback original:original];
      break;

    case ZCCSocketRequestTypeTextMessage:
    case ZCCSocketRequestTypeLocationMessage:
      [self handleSimpleCommandResponse:encoded callback:callback original:original];
      break;

    case ZCCSocketRequestTypeImageMessage:
      [self handleSendImageResponse:encoded callback:callback original:original];
      break;
  }
  if (callback.timeoutBlock) {
    dispatch_block_cancel(callback.timeoutBlock);
  }
  self.callbacks[seq] = nil;
}

- (void)handleLogonResponse:(NSDictionary *)encoded callback:(ZCCSocketResponseCallback *)callback original:(NSString *)original {
  if (!callback.logonCallback) {
    // Incorrect response type
    [self reportInvalidStringMessage:original];
    return;
  }

  id success = encoded[ZCCSuccessKey];
  if ([success isKindOfClass:[NSNumber class]] && [success boolValue]) {
    id refreshToken = encoded[ZCCRefreshTokenKey];
    if (![refreshToken isKindOfClass:[NSString class]]) {
      refreshToken = nil;
    }
    [self.delegateRunner runAsync:^{
      callback.logonCallback(YES, refreshToken, nil);
    }];
    return;
  }

  id errorMessage = encoded[ZCCErrorKey];
  if (![errorMessage isKindOfClass:[NSString class]]) {
    errorMessage = nil;
  }
  [self.delegateRunner runAsync:^{
    callback.logonCallback(NO, nil, errorMessage);
  }];
}

- (void)handleSendImageResponse:(NSDictionary *)encoded callback:(ZCCSocketResponseCallback *)callback original:(NSString *)original {
  if (!callback.sendImageCallback) {
    // Incorrect response type
    [self reportInvalidStringMessage:original];
    return;
  }

  id success = encoded[ZCCSuccessKey];
  if ([success isKindOfClass:[NSNumber class]] && [success boolValue]) {
    id imageId = encoded[ZCCImageIDKey];
    if (![imageId isKindOfClass:[NSNumber class]]) {
      // Missing or invalid image ID
      [self.delegateRunner runAsync:^{
        callback.sendImageCallback(NO, 0, @"image_id missing or invalid");
      }];
      return;
    }
    long long imageIdValue = [imageId longLongValue];
    if (imageIdValue < 0 || imageIdValue > UINT32_MAX) {
      // Image ID out of range
      [self.delegateRunner runAsync:^{
        callback.sendImageCallback(NO, 0, [NSString stringWithFormat:@"image_id (%lld) out of range", imageIdValue]);
      }];
      return;
    }
    [self.delegateRunner runAsync:^{
      callback.sendImageCallback(YES, (UInt32)imageIdValue, nil);
    }];
    return;
  }

  // Handle error from server
  id errorMessage = encoded[ZCCErrorKey];
  if (![errorMessage isKindOfClass:[NSString class]]) {
    errorMessage = nil;
  }
  [self.delegateRunner runAsync:^{
    callback.sendImageCallback(NO, 0, errorMessage);
  }];
}

- (void)handleStartStreamResponse:(NSDictionary *)encoded callback:(ZCCSocketResponseCallback *)callback original:(NSString *)original {
  if (!callback.startStreamCallback) {
    // Incorrect response type
    [self reportInvalidStringMessage:original];
    return;
  }

  id success = encoded[ZCCSuccessKey];
  if ([success isKindOfClass:[NSNumber class]] && [success boolValue]) {
    id streamId = encoded[ZCCStreamIDKey];
    if (![streamId isKindOfClass:[NSNumber class]]) {
      // Missing or invalid stream id
      [self.delegateRunner runAsync:^{
        callback.startStreamCallback(NO, 0, @"stream_id missing or invalid");
      }];
      return;
    }
    long long streamIdValue = [streamId longLongValue];
    if (streamIdValue < 0 || streamIdValue > UINT32_MAX) {
      // Stream ID out of range
      [self.delegateRunner runAsync:^{
        callback.startStreamCallback(NO, 0, @"stream_id out of range");
      }];
      return;
    }
    [self.delegateRunner runAsync:^{
      callback.startStreamCallback(YES, (NSUInteger)streamIdValue, nil);
    }];
    return;
  }

  // I'm guessing at how to handle error responses when attempting to start a stream
  id errorMessage = encoded[ZCCErrorKey];
  if (![errorMessage isKindOfClass:[NSString class]]) {
    errorMessage = nil;
  }
  [self.delegateRunner runAsync:^{
    callback.startStreamCallback(NO, 0, errorMessage);
  }];
}

- (void)handleSimpleCommandResponse:(NSDictionary *)encoded callback:(ZCCSocketResponseCallback *)callback original:(NSString *)original {
  if (!callback.simpleCommandCallback) {
    [self reportInvalidStringMessage:original];
    return;
  }
  ZCCSimpleCommandCallback simpleCallback = callback.simpleCommandCallback;

  id success = encoded[ZCCSuccessKey];
  if ([success isKindOfClass:[NSNumber class]] && [success boolValue]) {
    simpleCallback(YES, nil);
    return;
  }

  id errorMessage = encoded[ZCCErrorKey];
  if (![errorMessage isKindOfClass:[NSString class]]) {
    errorMessage = @"Unknown server error";
  }
  simpleCallback(NO, errorMessage);
}

- (void)handleChannelStatus:(NSDictionary *)encoded original:(NSString *)original {
  id channelName = encoded[ZCCChannelNameKey];
  if (![channelName isKindOfClass:[NSString class]]) {
    [self reportInvalidJSONInMessage:ZCCEventOnChannelStatus key:ZCCChannelNameKey errorDescription:@"Channel name missing or not a string" original:original];
    return;
  }
  id status = encoded[ZCCChannelStatusStatusKey];
  if (![status isKindOfClass:[NSString class]]) {
    [self reportInvalidJSONInMessage:ZCCEventOnChannelStatus key:ZCCChannelStatusStatusKey errorDescription:@"Channel status missing or not a string" original:original];
    return;
  }
  id numUsers = encoded[ZCCChannelStatusNumberOfUsersKey];
  if (![numUsers isKindOfClass:[NSNumber class]]) {
    [self reportInvalidJSONInMessage:ZCCEventOnChannelStatus key:ZCCChannelStatusNumberOfUsersKey errorDescription:@"Number of users missing or not a number" original:original];
    return;
  }
  ZCCChannelInfo channelInfo = ZCCChannelInfoZero();
  channelInfo.status = ZCCChannelStatusFromString(status);
  id images = encoded[@"images_supported"];
  if ([images isKindOfClass:[NSNumber class]]) {
    channelInfo.imagesSupported = [images boolValue];
  }
  id texting = encoded[@"texting_supported"];
  if ([texting isKindOfClass:[NSNumber class]]) {
    channelInfo.textingSupported = [texting boolValue];
  }
  id locations = encoded[@"locations_supported"];
  if ([locations isKindOfClass:[NSNumber class]]) {
    channelInfo.locationsSupported = [locations boolValue];
  }

  id<ZCCSocketDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(socket:didReportStatus:forChannel:usersOnline:)]) {
    [self.delegateRunner runAsync:^{
      [delegate socket:self didReportStatus:channelInfo forChannel:channelName usersOnline:[numUsers integerValue]];
    }];
  }
}

- (void)handleStreamStart:(NSDictionary *)encoded original:(NSString *)original {
  id type = encoded[ZCCStreamTypeKey];
  if (![type isKindOfClass:[NSString class]]) {
    [self reportInvalidJSONInMessage:ZCCEventOnStreamStart key:ZCCStreamTypeKey errorDescription:@"type is missing or invalid" original:original];
    return;
  }
  id codec = encoded[ZCCStreamCodecKey];
  if (![codec isKindOfClass:[NSString class]]) {
    [self reportInvalidJSONInMessage:ZCCEventOnStreamStart key:ZCCStreamCodecKey errorDescription:@"codec is missing or invalid" original:original];
    return;
  }
  id header = encoded[ZCCStreamCodecHeaderKey];
  if (![header isKindOfClass:[NSString class]]) {
    [self reportInvalidJSONInMessage:ZCCEventOnStreamStart key:ZCCStreamCodecHeaderKey errorDescription:@"codec_header missing or invalid" original:original];
    return;
  }
  header = [header stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  NSData *headerData = [[NSData alloc] initWithBase64EncodedString:header options:0];
  if (!headerData) {
    [self reportInvalidJSONInMessage:ZCCEventOnStreamStart key:ZCCStreamCodecHeaderKey errorDescription:@"codec_header missing or invalid" original:original];
    return;
  }
  id packetDuration = encoded[ZCCStreamPacketDurationKey];
  if (![packetDuration isKindOfClass:[NSNumber class]]) {
    [self reportInvalidJSONInMessage:ZCCEventOnStreamStart key:ZCCStreamPacketDurationKey errorDescription:@"packet_duration missing or not a number" original:original];
    return;
  }
  long long packetDurationValue = [packetDuration longLongValue];
  if (packetDurationValue < 0) {
    [self reportInvalidJSONInMessage:ZCCEventOnStreamStart key:ZCCStreamPacketDurationKey errorDescription:@"packet_duration out of range" original:original];
    return;
  }
  id streamId = encoded[ZCCStreamIDKey];
  if (![streamId isKindOfClass:[NSNumber class]]) {
    [self reportInvalidJSONInMessage:ZCCEventOnStreamStart key:ZCCStreamIDKey errorDescription:@"stream_id missing or invalid" original:original];
    return;
  }
  long long streamIdValue = [streamId longLongValue];
  if (streamIdValue < 0 || streamIdValue > UINT32_MAX) {
    // Stream ID out of range
    [self reportInvalidJSONInMessage:ZCCEventOnStreamStart key:ZCCStreamIDKey errorDescription:@"stream_id out of range" original:original];
    return;
  }
  // Should we check that streamId fits into 16 bits?
  id channel = encoded[ZCCChannelNameKey];
  if (![channel isKindOfClass:[NSString class]]) {
    [self reportInvalidJSONInMessage:ZCCEventOnStreamStart key:ZCCChannelNameKey errorDescription:@"channel missing or invalid" original:original];
    return;
  }
  id from = encoded[ZCCFromUserKey];
  if (![from isKindOfClass:[NSString class]]) {
    [self reportInvalidJSONInMessage:ZCCEventOnStreamStart key:ZCCFromUserKey errorDescription:@"from missing or invalid" original:original];
    return;
  }

  ZCCStreamParams *params = [[ZCCStreamParams alloc] init];
  params.codecName = codec;
  params.type = type;
  params.codecHeader = headerData;
  params.packetDuration = (NSUInteger)packetDurationValue;
  id<ZCCSocketDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(socket:didStartStreamWithId:params:channel:sender:)]) {
    [self.delegateRunner runAsync:^{
      [delegate socket:self didStartStreamWithId:(NSUInteger)streamIdValue params:params channel:channel sender:from];
    }];
  }
}

- (void)handleStreamStop:(NSDictionary *)encoded original:(NSString *)original {
  id streamId = encoded[ZCCStreamIDKey];
  if (![streamId isKindOfClass:[NSNumber class]]) {
    [self reportInvalidJSONInMessage:ZCCEventOnStreamStop key:ZCCStreamIDKey errorDescription:@"stream_id missing or invalid" original:original];
    return;
  }
  long long streamIdValue = [streamId longLongValue];
  if (streamIdValue < 0 || streamIdValue > UINT32_MAX) {
    // Stream ID out of range
    [self reportInvalidJSONInMessage:ZCCEventOnStreamStop key:ZCCStreamIDKey errorDescription:@"stream_id out of range" original:original];
    return;
  }

  id<ZCCSocketDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(socket:didStopStreamWithId:)]) {
    [self.delegateRunner runAsync:^{
      [delegate socket:self didStopStreamWithId:(NSUInteger)streamIdValue];
    }];
  }
}

- (void)handleError:(NSDictionary *)encoded original:(NSString *)original {
  id errorMessage = encoded[ZCCErrorKey];
  if (![errorMessage isKindOfClass:[NSString class]]) {
    [self reportInvalidJSONInMessage:ZCCEventOnError key:ZCCErrorKey errorDescription:@"error missing or not string" original:original];
    return;
  }

  [self reportError:errorMessage];
}

- (void)handleLocation:(NSDictionary *)encoded original:(NSString *)original {
  id latitude = encoded[ZCCLatitudeKey];
  if (![latitude isKindOfClass:[NSNumber class]]) {
    [self reportInvalidJSONInMessage:ZCCEventOnLocation key:ZCCLatitudeKey errorDescription:@"latitude missing or invalid" original:original];
    return;
  }
  double latitudeValue = [latitude doubleValue];
  id longitude = encoded[ZCCLongitudeKey];
  if (![longitude isKindOfClass:[NSNumber class]]) {
    [self reportInvalidJSONInMessage:ZCCEventOnLocation key:ZCCLongitudeKey errorDescription:@"longitude missing or invalid" original:original];
    return;
  }
  double longitudeValue = [longitude doubleValue];
  id accuracy = encoded[ZCCAccuracyKey];
  if (![accuracy isKindOfClass:[NSNumber class]]) {
    [self reportInvalidJSONInMessage:ZCCEventOnLocation key:ZCCAccuracyKey errorDescription:@"accuracy missing or invalid" original:original];
    return;
  }
  double accuracyValue = [accuracy doubleValue];
  id sender = encoded[ZCCFromUserKey];
  if (![sender isKindOfClass:[NSString class]]) {
    [self reportInvalidJSONInMessage:ZCCEventOnLocation key:ZCCFromUserKey errorDescription:@"from missing or invalid" original:original];
    return;
  }
  id address = encoded[ZCCReverseGeocodedKey];
  if (![address isKindOfClass:[NSString class]]) {
    address = nil;
  }

  ZCCLocationInfo *location = [[ZCCLocationInfo alloc] initWithLatitude:latitudeValue longitude:longitudeValue accuracy:accuracyValue];
  if (address) {
    [location setAddress:address];
  }

  id<ZCCSocketDelegate> delegate = self.delegate;
  [self.delegateRunner runAsync:^{
    [delegate socket:self didReceiveLocationMessage:location sender:sender];
  }];
}

- (void)handleTextMessage:(NSDictionary *)encoded original:(NSString *)original {
  id message = encoded[ZCCTextContentKey];
  if (![message isKindOfClass:[NSString class]]) {
    [self reportInvalidJSONInMessage:ZCCEventOnTextMessage key:ZCCTextContentKey errorDescription:@"text missing or invalid" original:original];
    return;
  }
  id sender = encoded[ZCCFromUserKey];
  if (![sender isKindOfClass:[NSString class]]) {
    [self reportInvalidJSONInMessage:ZCCEventOnTextMessage key:ZCCFromUserKey errorDescription:@"from missing or invalid" original:original];
    return;
  }

  id<ZCCSocketDelegate> delegate = self.delegate;
  [self.delegateRunner runAsync:^{
    [delegate socket:self didReceiveTextMessage:message sender:sender];
  }];
}

- (void)handleImage:(NSDictionary *)encoded original:(NSString *)original {
  ZCCImageHeader *header = [[ZCCImageHeader alloc] init];
  id channel = encoded[ZCCChannelNameKey];
  if ([channel isKindOfClass:[NSString class]]) {
    header.channel = channel;
  }
  id sender = encoded[ZCCFromUserKey];
  if (![sender isKindOfClass:[NSString class]]) {
    [self reportInvalidJSONInMessage:ZCCEventOnImage key:ZCCFromUserKey errorDescription:@"from missing or invalid" original:original];
    return;
  }
  header.sender = sender;
  id imageId = encoded[ZCCMessageIDKey];
  if (![imageId isKindOfClass:[NSNumber class]]) {
    [self reportInvalidJSONInMessage:ZCCEventOnImage key:ZCCMessageIDKey errorDescription:@"message_id missing or invalid" original:original];
    return;
  }
  long long imageIdValue = [imageId longLongValue];
  if (imageIdValue < 0 || imageIdValue > UINT32_MAX) {
    [self reportInvalidJSONInMessage:ZCCEventOnImage key:ZCCMessageIDKey errorDescription:@"message_id out of range" original:original];
    return;
  }
  header.imageId = (NSUInteger)imageIdValue;

  id source = encoded[ZCCImageSourceKey];
  if ([source isKindOfClass:[NSString class]]) {
    header.source = source;
  }
  id type = encoded[ZCCStreamTypeKey];
  if (![type isKindOfClass:[NSString class]]) {
    [self reportInvalidJSONInMessage:ZCCEventOnImage key:ZCCStreamTypeKey errorDescription:@"type missing or invalid" original:original];
    return;
  }
  if ([type isEqualToString:@"jpeg"]) {
    header.imageType = ZCCImageTypeJPEG;
  } else {
    header.imageType = ZCCImageTypeUnkown;
  }
  id height = encoded[ZCCImageHeightKey];
  if ([height isKindOfClass:[NSNumber class]]) {
    long long heightValue = [height longLongValue];
    if (heightValue < 0 || heightValue > INT32_MAX) {
      [self reportInvalidJSONInMessage:ZCCEventOnImage key:ZCCImageHeightKey errorDescription:@"height out of range" original:original];
      return;
    }
    header.height = (NSInteger)heightValue;
  }
  id width = encoded[ZCCImageWidthKey];
  if ([width isKindOfClass:[NSNumber class]]) {
    long long widthValue = [width longLongValue];
    if (widthValue < 0 || widthValue > INT32_MAX) {
      [self reportInvalidJSONInMessage:ZCCEventOnImage key:ZCCImageWidthKey errorDescription:@"width out of range" original:original];
      return;
    }
    header.width = (NSInteger)widthValue;
  }

  id<ZCCSocketDelegate> delegate = self.delegate;
  [self.delegateRunner runAsync:^{
    [delegate socket:self didReceiveImageHeader:header];
  }];
}

/**
 * Report an error parsing a JSON message from the server
 *
 * @param message the type of message
 * @param key the key we were trying to retrieve
 * @param description a description of the error encountered
 * @param original the original string we were trying to parse
 */
- (void)reportInvalidJSONInMessage:(nullable NSString *)message key:(NSString *)key errorDescription:(NSString *)description original:(NSString *)original {
  id<ZCCSocketDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(socket:didEncounterErrorParsingMessage:)]) {
    NSMutableDictionary *info = [@{ZCCServerInvalidMessageKey:original,
                                  ZCCInvalidJSONKeyKey:key,
                                  ZCCInvalidJSONProblemKey:description} mutableCopy];
    if (message) {
      info[ZCCInvalidJSONMessageKey] = message;
    }
    NSError *error = [NSError errorWithDomain:ZCCErrorDomain code:ZCCErrorCodeInvalidMessage userInfo:info];
    [self.delegateRunner runAsync:^{
      [delegate socket:self didEncounterErrorParsingMessage:error];
    }];
  }
}

- (void)reportInvalidStringMessage:(NSString *)message {
  id<ZCCSocketDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(socket:didEncounterErrorParsingMessage:)]) {
    NSError *error = [NSError errorWithDomain:ZCCErrorDomain code:ZCCErrorCodeBadResponse userInfo:@{ZCCServerInvalidMessageKey:message}];
    [self.delegateRunner runAsync:^{
      [delegate socket:self didEncounterErrorParsingMessage:error];
    }];
  }
}

- (void)webSocket:(ZCCSRWebSocket *)webSocket didReceiveMessageWithData:(NSData *)data {
  [self.workRunner runSync:^{
    if (data.length < 1) {
      [self reportUnrecognizedBinaryMessage:data type:0];
      return;
    }
    uint8_t type;
    [data getBytes:&type length:1];
    switch (type) {
      case 0x01:
        [self handleAudioData:data];
        break;

      case 0x02:
        [self handleImageData:data];
        break;

      default:
        [self reportUnrecognizedBinaryMessage:data type:type];
    }
  }];
}

- (void)handleAudioData:(NSData *)data {
  NSUInteger minValidLength = sizeof(uint8_t) + sizeof(uint32_t) + sizeof(uint32_t);
  if (data.length < minValidLength) { // minimum audio data message is 9 bytes
    uint8_t type = 0;
    if (data.length >= 1) {
      [data getBytes:&type length:1];
    }
    [self reportUnrecognizedBinaryMessage:data type:type];
    return;
  }

  uint32_t streamId = 0;
  NSUInteger streamIdOffset = 1; // 1 byte for type
  [data getBytes:&streamId range:NSMakeRange(streamIdOffset, sizeof(streamId))];
  streamId = ntohl(streamId);
  uint32_t packetId = 0;
  NSUInteger packetIdOffset = streamIdOffset + sizeof(streamId);
  [data getBytes:&packetId range:NSMakeRange(packetIdOffset, sizeof(packetId))];
  packetId = ntohl(packetId);
  NSUInteger dataOffset = packetIdOffset + sizeof(packetId);
  NSData *audio = [data subdataWithRange:NSMakeRange(dataOffset, data.length - dataOffset)];
  id<ZCCSocketDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(socket:didReceiveAudioData:streamId:packetId:)]) {
    [self.delegateRunner runAsync:^{
      [delegate socket:self didReceiveAudioData:audio streamId:streamId packetId:packetId];
    }];
  }
}

- (void)handleImageData:(NSData *)data {
  NSUInteger minValidLength = sizeof(uint8_t) + sizeof(uint32_t) + sizeof(uint32_t);
  if (data.length < minValidLength) {
    [self reportUnrecognizedBinaryMessage:data type:0x02];
    return;
  }

  uint32_t imageId;
  NSUInteger offset = 1; // 1 byte for type
  [data getBytes:&imageId range:NSMakeRange(offset, sizeof(imageId))];
  imageId = ntohl(imageId);
  offset += sizeof(imageId);
  uint32_t imageType;
  [data getBytes:&imageType range:NSMakeRange(offset, sizeof(imageType))];
  imageType = ntohl(imageType);
  if (imageType != 0x01 & imageType != 0x02) {
    [self reportUnrecognizedBinaryMessage:data type:0x02];
    return;
  }
  offset += sizeof(imageType);
  NSData *imageData = [data subdataWithRange:NSMakeRange(offset, data.length - offset)];

  id<ZCCSocketDelegate> delegate = self.delegate;
  [self.delegateRunner runAsync:^{
    [delegate socket:self didReceiveImageData:imageData imageId:imageId isThumbnail:(imageType == 0x02)];
  }];
}

- (void)reportUnrecognizedBinaryMessage:(NSData *)data type:(NSInteger)type {
  id<ZCCSocketDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(socket:didReceiveData:unrecognizedType:)]) {
    [self.delegateRunner runAsync:^{
      [delegate socket:self didReceiveData:data unrecognizedType:type];
    }];
  }
}

#pragma mark - Private

- (NSInteger)incrementedSequenceNumber {
    self.nextSequenceNumber += 1;
    return self.nextSequenceNumber;
}

- (void)reportError:(nonnull NSString *)errorMessage {
  id<ZCCSocketDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(socket:didReportError:)]) {
    [self.delegateRunner runAsync:^{
      [delegate socket:self didReportError:errorMessage];
    }];
  }
}

@end
