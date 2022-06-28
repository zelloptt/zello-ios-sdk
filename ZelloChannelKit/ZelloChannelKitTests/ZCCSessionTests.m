//
//  ZCCSessionTests.m
//  ZelloChannelKitTests
//
//  Created by Greg Cooksey on 3/22/18.
//  Copyright © 2018 Zello. All rights reserved.
//

#import <CoreLocation/CoreLocation.h>
#import <OCMock/OCMock.h>
#import <XCTest/XCTest.h>
#import "ZCCSession.h"
#import "ImageUtilities.h"
#import "ZCCAddressFormattingService.h"
#import "ZCCChannelInfo.h"
#import "ZCCEncoderOpus.h"
#import "ZCCErrors.h"
#import "ZCCGeocodingService.h"
#import "ZCCImageHeader.h"
#import "ZCCImageInfo.h"
#import "ZCCImageMessage.h"
#import "ZCCImageMessageManager.h"
#import "ZCCImageUtils.h"
#import "ZCCIncomingVoiceConfiguration.h"
#import "ZCCIncomingVoiceStreamInfo+Internal.h"
#import "ZCCLocationInfo.h"
#import "ZCCLocationService.h"
#import "ZCCOutgoingVoiceConfiguration.h"
#import "ZCCPermissionsManager.h"
#import "ZCCSocket.h"
#import "ZCCSocketFactory.h"
#import "ZCCStreamParams.h"
#import "ZCCVoiceStreamsManager.h"

@interface ZCCMockLocationService : NSObject <ZCCLocationService>
@property (nonatomic) CLAuthorizationStatus authorizationStatus;
@property (nonatomic) BOOL locationServicesEnabled;
@property (nonatomic, strong, nullable) void (^mockedRequestLocation)(ZCCLocationRequestCallback callback);
@end
@implementation ZCCMockLocationService
- (void)requestLocation:(ZCCLocationRequestCallback)callback {
  if (self.mockedRequestLocation) {
    self.mockedRequestLocation(callback);
  }
}
@end

@interface ZCCLocationInfo (Testing)
@property (nonatomic) double latitude;
@property (nonatomic) double longitude;
@property (nonatomic) double accuracy;
@property (nonatomic, copy) NSString *address;
@end

@interface ZCCSession (Testing) <ZCCSocketDelegate>
@property (nonatomic, strong, nonnull) ZCCPermissionsManager *permissionsManager;
@property (nonatomic, strong, nonnull) ZCCSocketFactory *socketFactory;
@property (nonatomic, strong, nonnull) ZCCVoiceStreamsManager *streamsManager;
@property (nonatomic, strong, nonnull) ZCCImageMessageManager *imageManager;
@property (nonatomic, strong, nonnull) id<ZCCAddressFormattingService> addressFormattingService;
@property (nonatomic, strong, nonnull) id<ZCCGeocodingService> geocodingService;
@property (nonatomic, strong, nonnull) id<ZCCLocationService> locationService;
@end

@interface ZCCSessionTests : XCTestCase

@property (nonatomic, strong) NSURL *exampleURL;

/// Mocked ZCCPermissionsManager
@property (nonatomic, strong) id permissionsManager;
/// Mocked ZCCLocationService
@property (nonatomic, strong) ZCCMockLocationService *locationService;
/// Mocked ZCCGeocodingService
@property (nonatomic, strong) id geocodingService;
/// Mocked ZCCAddressFormattingService
@property (nonatomic, strong) id addressFormattingService;
/// Mocked id<ZCCSessionDelegate>
@property (nonatomic, strong) id sessionDelegate;
/// Mocked ZCCSocket
@property (nonatomic, strong) id socket;

@property (nonatomic, strong) XCTestExpectation *sessionDidStartConnecting;
@property (nonatomic, strong) XCTestExpectation *socketOpened;
@property (nonatomic, strong) XCTestExpectation *logonSent;
@end

@implementation ZCCSessionTests

- (void)setUp {
  [super setUp];
  self.exampleURL = [NSURL URLWithString:@"wss://example.com/"];

  self.permissionsManager = OCMClassMock([ZCCPermissionsManager class]);

  self.addressFormattingService = OCMProtocolMock(@protocol(ZCCAddressFormattingService));
  self.geocodingService = OCMProtocolMock(@protocol(ZCCGeocodingService));
  self.locationService = [[ZCCMockLocationService alloc] init];
  self.sessionDelegate = OCMProtocolMock(@protocol(ZCCSessionDelegate));
  self.socket = OCMClassMock([ZCCSocket class]);

  self.sessionDidStartConnecting = [[XCTestExpectation alloc] initWithDescription:@"Session delegate informed connect started"];
  self.socketOpened = [[XCTestExpectation alloc] initWithDescription:@"Socket opened"];
  self.logonSent = [[XCTestExpectation alloc] initWithDescription:@"Logon sent"];
}

- (void)tearDown {
  self.permissionsManager = nil;
  self.sessionDelegate = nil;
  self.socket = nil;

  self.sessionDidStartConnecting = nil;
  self.socketOpened = nil;
  self.logonSent = nil;
  [super tearDown];
}

#pragma mark - Setup utilities

- (ZCCSession *)sessionWithUsername:(nullable NSString *)username password:(nullable NSString *)password {
  NSString *claims = [[@"{}" dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
  NSString *authToken = [NSString stringWithFormat:@".%@.", claims];
  ZCCSession *session = [[ZCCSession alloc] initWithURL:self.exampleURL authToken:authToken username:username password:password channel:@"test" callbackQueue:nil];
  session.delegate = self.sessionDelegate;
  session.permissionsManager = self.permissionsManager;
  session.addressFormattingService = self.addressFormattingService;
  session.geocodingService = self.geocodingService;
  session.locationService = self.locationService;
  session.socketFactory.createSocketWithURL = ^(NSURL *socketURL) {
    XCTAssertEqualObjects(socketURL, self.exampleURL);
    return self.socket;
  };
  return session;
}

- (void)expectSessionDidStartConnecting:(ZCCSession *)session {
  OCMExpect([self.sessionDelegate sessionDidStartConnecting:session]).andDo(^(NSInvocation *invocation) {
    [self.sessionDidStartConnecting fulfill];
  });
}

- (void)expectSocketOpened {
  OCMExpect([self.socket open]).andDo(^(NSInvocation *invocation) {
    [self.socketOpened fulfill];
  });
}

- (void)expectLogonWithUsername:(NSString *)username password:(NSString *)password logonCallbackHandler:(void (^)(ZCCLogonCallback callback))handler {
  OCMExpect([self.socket sendLogonWithAuthToken:OCMOCK_ANY refreshToken:OCMOCK_ANY channel:@"test" username:username password:password callback:OCMOCK_ANY timeoutAfter:30.0]).andDo(^(NSInvocation *invocation) {
    if (handler) {
      __unsafe_unretained ZCCLogonCallback callback = nil;
      [invocation getArgument:&callback atIndex:7];
      handler(callback);
    }
    [self.logonSent fulfill];
  });
}

- (void)connectSession:(ZCCSession *)session {
  [self expectSocketOpened];
  [session connect];
  XCTAssertEqual([XCTWaiter waitForExpectations:@[self.socketOpened] timeout:3], XCTWaiterResultCompleted);
  [self expectLogonWithUsername:@"" password:@"" logonCallbackHandler:^(ZCCLogonCallback callback) {
    callback(YES, nil, nil);
  }];
  [session socketDidOpen:self.socket];
  XCTAssertEqual([XCTWaiter waitForExpectations:@[self.logonSent] timeout:3.0], XCTWaiterResultCompleted);
}

#pragma mark - Tests

#pragma mark -connect

- (void)testConnect_noUsernameOrPassword_opensWebSocketToServer {
  ZCCSession *session = [self sessionWithUsername:nil password:nil];

  [self expectSocketOpened];

  [session connect];

  XCTAssertEqual([XCTWaiter waitForExpectations:@[self.socketOpened] timeout:1], XCTWaiterResultCompleted);

  OCMVerifyAll(self.socket);
}

- (void)testConnect_noUsernameOrPassword_SendsLogonToServer {
  ZCCSession *session = [self sessionWithUsername:nil password:nil];
  [self expectSocketOpened];
  [session connect];
  XCTAssertEqual([XCTWaiter waitForExpectations:@[self.socketOpened] timeout:1], XCTWaiterResultCompleted);
  OCMVerifyAll(self.socket);

  OCMExpect([self.socket sendLogonWithAuthToken:OCMOCK_ANY refreshToken:OCMOCK_ANY channel:@"test" username:@"" password:@"" callback:OCMOCK_ANY timeoutAfter:30.0]).andDo(^(NSInvocation *invocation) {
    [self.logonSent fulfill];
  });
  [session socketDidOpen:self.socket];

  XCTAssertEqual([XCTWaiter waitForExpectations:@[self.logonSent] timeout:1], XCTWaiterResultCompleted);

  OCMVerifyAll(self.socket);
}

// Verify that session behaves correctly when logging in successfully without a username or password
- (void)testConnect_noUsernameOrPasswordLogonSucceeds_CallsDelegate {
  [self expectSocketOpened];
  ZCCSession *session = [self sessionWithUsername:nil password:nil];
  [self expectSessionDidStartConnecting:session];
  XCTestExpectation *delegateCalled = [[XCTestExpectation alloc] initWithDescription:@"Session delegate called"];
  OCMExpect([self.sessionDelegate sessionDidConnect:session]).andDo(^(NSInvocation *invocation) {
    [delegateCalled fulfill];
  });
  [session connect];
  XCTWaiterResult waitResult = [XCTWaiter waitForExpectations:@[self.sessionDidStartConnecting, self.socketOpened] timeout:3];
  XCTAssertEqual(waitResult, XCTWaiterResultCompleted);
  OCMVerifyAll(self.socket);

  [self expectLogonWithUsername:@"" password:@"" logonCallbackHandler:^(ZCCLogonCallback callback) {
    callback(YES, nil, nil);
  }];
  [session socketDidOpen:self.socket];

  waitResult = [XCTWaiter waitForExpectations:@[self.logonSent, delegateCalled] timeout:1];
  XCTAssertEqual(waitResult, XCTWaiterResultCompleted);

  OCMVerifyAll(self.socket);
  OCMVerifyAll(self.sessionDelegate);
  XCTAssertEqual(session.state, ZCCSessionStateConnected);
}

// Verify that session behaves correctly with logging in successfully with a username and password
- (void)testConnect_usernameAndPasswordLogonSucceeds_CallsDelegate {
  [self expectSocketOpened];
  ZCCSession *session = [self sessionWithUsername:@"bogusUser" password:@"bogusPassword"];
  XCTestExpectation *delegateCalled = [[XCTestExpectation alloc] initWithDescription:@"Session delegate called"];
  OCMExpect([self.sessionDelegate sessionDidConnect:session]).andDo(^(NSInvocation *invocation) {
    [delegateCalled fulfill];
  });
  [session connect];
  XCTAssertEqual([XCTWaiter waitForExpectations:@[self.socketOpened] timeout:1], XCTWaiterResultCompleted);
  OCMVerifyAll(self.socket);

  [self expectLogonWithUsername:@"bogusUser" password:@"bogusPassword" logonCallbackHandler:^(ZCCLogonCallback callback) {
    callback(YES, nil, nil);
  }];
  [session socketDidOpen:self.socket];

  XCTWaiterResult waitResult = [XCTWaiter waitForExpectations:@[self.logonSent, delegateCalled] timeout:3];
  XCTAssertEqual(waitResult, XCTWaiterResultCompleted);

  OCMVerifyAll(self.socket);
  OCMVerifyAll(self.sessionDelegate);
  XCTAssertEqual(session.state, ZCCSessionStateConnected);
}

// Verify that session behaves correctly when logging in fails
- (void)testConnect_LogonFails_CallsDelegate {
  ZCCSession *session = [self sessionWithUsername:nil password:nil];
  XCTestExpectation *delegateCalled = [[XCTestExpectation alloc] initWithDescription:@"Session delegate called"];
  OCMExpect([self.sessionDelegate session:session didFailToConnectWithError:OCMOCK_ANY]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained NSError *error = nil;
    [invocation getArgument:&error atIndex:3];
    XCTAssertEqualObjects(error.domain, ZCCErrorDomain);
    XCTAssertEqual(error.code, ZCCErrorCodeConnectFailed);
    XCTAssertEqualObjects(error.userInfo[ZCCServerErrorMessageKey], @"Uh oh");
    [delegateCalled fulfill];
  });
  [self expectSocketOpened];

  [session connect];
  XCTAssertEqual([XCTWaiter waitForExpectations:@[self.socketOpened] timeout:1], XCTWaiterResultCompleted);
  OCMVerifyAll(self.socket);

  [self expectLogonWithUsername:@"" password:@"" logonCallbackHandler:^(ZCCLogonCallback callback) {
    callback(NO, nil, @"Uh oh");
  }];
  [session socketDidOpen:self.socket];

  XCTWaiterResult waitResult = [XCTWaiter waitForExpectations:@[self.logonSent, delegateCalled] timeout:5];
  XCTAssertEqual(waitResult, XCTWaiterResultCompleted);

  OCMVerifyAll(self.socket);
  OCMVerify([self.socket close]);
  OCMVerifyAll(self.sessionDelegate);
}

#pragma mark Channel status events

// Verify that we report the correct channel features and online status after we get a channel status event
- (void)testOnChannelStatus_propertiesReflectStatus {
  ZCCSession *session = [self sessionWithUsername:nil password:nil];
  XCTAssertEqual(session.channelStatus, ZCCChannelStatusOffline);
  [self connectSession:session];

  ZCCChannelInfo channelInfo;
  channelInfo.status = ZCCChannelStatusOffline;
  [session socket:self.socket didReportStatus:channelInfo forChannel:@"test" usersOnline:1];
  XCTAssertEqual(session.channelStatus, ZCCChannelStatusOffline);

  channelInfo.status = ZCCChannelStatusOnline;
  [session socket:self.socket didReportStatus:channelInfo forChannel:@"test" usersOnline:1];
  XCTAssertEqual(session.channelStatus, ZCCChannelStatusOnline);

  channelInfo.locationsSupported = YES;
  [session socket:self.socket didReportStatus:channelInfo forChannel:@"test" usersOnline:1];
  XCTAssertEqual(session.channelFeatures, ZCCChannelFeaturesLocationMessages);

  channelInfo.textingSupported = YES;
  [session socket:self.socket didReportStatus:channelInfo forChannel:@"test" usersOnline:1];
  XCTAssertEqual(session.channelFeatures, (ZCCChannelFeaturesLocationMessages | ZCCChannelFeaturesTextMessages));

  channelInfo.imagesSupported = YES;
  [session socket:self.socket didReportStatus:channelInfo forChannel:@"test" usersOnline:1];
  XCTAssertEqual(session.channelFeatures, (ZCCChannelFeaturesImageMessages | ZCCChannelFeaturesLocationMessages | ZCCChannelFeaturesTextMessages));

  channelInfo.locationsSupported = NO;
  [session socket:self.socket didReportStatus:channelInfo forChannel:@"test" usersOnline:1];
  XCTAssertEqual(session.channelFeatures, (ZCCChannelFeaturesImageMessages | ZCCChannelFeaturesTextMessages));

  // Verify that the session reflects the number of online users in the channel
  XCTAssertEqual(session.channelUsersOnline, 1);

  [session socket:self.socket didReportStatus:channelInfo forChannel:@"test" usersOnline:23];
  XCTAssertEqual(session.channelUsersOnline, 23);
}

// Verify that we tell our delegate there's new information about the channel when we get a channel status event
- (void)testOnChannelStatus_callsDelegate {
  __block BOOL tooEarly = YES;
  ZCCSession *session = [self sessionWithUsername:nil password:nil];
  XCTestExpectation *calledDelegate = [[XCTestExpectation alloc] initWithDescription:@"called delegate"];
  OCMExpect([self.sessionDelegate sessionDidUpdateChannelStatus:session]).andDo(^(NSInvocation *invocation) {
    XCTAssertFalse(tooEarly);
    [calledDelegate fulfill];
  });

  [self connectSession:session];

  tooEarly = NO;
  [session socket:self.socket didReportStatus:ZCCChannelInfoZero() forChannel:@"test" usersOnline:1];

  XCTAssertEqual([XCTWaiter waitForExpectations:@[calledDelegate] timeout:3.0], XCTWaiterResultCompleted);
  OCMVerifyAll(self.sessionDelegate);
}

// Verify that channel status properties have meaningful values when the session is disconnected
- (void)testChannelProperties_userDisconnectedSession {
  ZCCSession *session = [self sessionWithUsername:nil password:nil];
  XCTAssertEqual(session.channelStatus, ZCCChannelStatusOffline);
  XCTAssertEqual(session.channelFeatures, ZCCChannelFeaturesNone);
  XCTAssertEqual(session.channelUsersOnline, 0);

  [self connectSession:session];
  ZCCChannelInfo channelInfo = ZCCChannelInfoZero();
  channelInfo.status = ZCCChannelStatusOnline;
  channelInfo.imagesSupported = YES;
  channelInfo.textingSupported = YES;
  [session socket:self.socket didReportStatus:channelInfo forChannel:@"test" usersOnline:14];
  XCTAssertEqual(session.channelStatus, ZCCChannelStatusOnline);
  XCTAssertEqual(session.channelFeatures, (ZCCChannelFeaturesImageMessages | ZCCChannelFeaturesTextMessages));
  XCTAssertEqual(session.channelUsersOnline, 14);

  // Disconnect and verify we've reset channel properties
  XCTestExpectation *disconnected = [[XCTestExpectation alloc] initWithDescription:@"closed socket"];
  OCMExpect([self.socket close]).andDo(^(NSInvocation *invocation) {
    [disconnected fulfill];
  });
  [session disconnect];
  XCTAssertEqual([XCTWaiter waitForExpectations:@[disconnected] timeout:3.0], XCTWaiterResultCompleted);

  XCTAssertEqual(session.channelStatus, ZCCChannelStatusOffline);
  XCTAssertEqual(session.channelFeatures, ZCCChannelFeaturesNone);
  XCTAssertEqual(session.channelUsersOnline, 0);
}

- (void)testChannelProperties_serverDisconnected {
  ZCCSession *session = [self sessionWithUsername:nil password:nil];

  [self connectSession:session];
  ZCCChannelInfo channelInfo = ZCCChannelInfoZero();
  channelInfo.status = ZCCChannelStatusOnline;
  channelInfo.imagesSupported = YES;
  [session socket:self.socket didReportStatus:channelInfo forChannel:@"test" usersOnline:10];
  XCTAssertEqual(session.channelStatus, ZCCChannelStatusOnline);
  XCTAssertEqual(session.channelFeatures, ZCCChannelFeaturesImageMessages);
  XCTAssertEqual(session.channelUsersOnline, 10);

  [session socketDidClose:self.socket withError:nil];
  XCTAssertEqual(session.channelStatus, ZCCChannelStatusOffline);
  XCTAssertEqual(session.channelUsersOnline, 0);
  XCTAssertEqual(session.channelFeatures, ZCCChannelFeaturesNone);
}

#pragma mark -disconnect

// Verify that session disconnects web socket when user calls -disconnect
- (void)testDisconnect_ClosesSocketAndCallsDelegate {
  ZCCSession *session = [self sessionWithUsername:nil password:nil];
  [self connectSession:session];

  XCTestExpectation *socketClosed = [[XCTestExpectation alloc] initWithDescription:@"Socket closed"];
  OCMExpect([self.socket close]).andDo(^(NSInvocation *invocation) {
    [socketClosed fulfill];
  });
  XCTestExpectation *sessionDidDisconnect = [[XCTestExpectation alloc] initWithDescription:@"Session delegate informed socket disconnected"];
  OCMExpect([self.sessionDelegate sessionDidDisconnect:session]).andDo(^(NSInvocation *invocation) {
    [sessionDidDisconnect fulfill];
  });
  [session disconnect];
  XCTWaiterResult waitResult = [XCTWaiter waitForExpectations:@[socketClosed, sessionDidDisconnect] timeout:3.0];
  XCTAssertEqual(waitResult, XCTWaiterResultCompleted);

  OCMVerifyAll(self.socket);
  OCMVerifyAll(self.sessionDelegate);
  XCTAssertEqual(session.state, ZCCSessionStateDisconnected);
}

#pragma mark -startVoiceMessage

// Verify that we return nil if the session is not connected to the server
- (void)testStartVoiceMessage_notConnected_returnsNil {
  OCMStub([self.permissionsManager recordPermission]).andReturn(AVAudioSessionRecordPermissionGranted);
  ZCCSession *session = [self sessionWithUsername:nil password:nil];

  ZCCOutgoingVoiceStream *stream = [session startVoiceMessage];
  XCTAssertNil(stream);
}

// Verify that we return nil if microphone permission has not been granted by the user
- (void)testStartVoiceMessage_ConnectedNoMicrophonePermission_returnsNil {
  OCMStub([self.permissionsManager recordPermission]).andReturn(AVAudioSessionRecordPermissionDenied);
  ZCCSession *session = [self sessionWithUsername:nil password:nil];
  [self connectSession:session];

  ZCCOutgoingVoiceStream *stream = [session startVoiceMessage];
  XCTAssertNil(stream);
}

// Verify that we start opening a stream if we're connected and have microphone permission
- (void)testStartVoiceMessage_ConnectedMicrophonePermissionGranted_StartsConnecting {
  OCMStub([self.permissionsManager recordPermission]).andReturn(AVAudioSessionRecordPermissionGranted);
  ZCCSession *session = [self sessionWithUsername:nil password:nil];
  [self connectSession:session];

  XCTestExpectation *startStreamSent = [[XCTestExpectation alloc] initWithDescription:@"start_stream sent"];
  OCMExpect([self.socket sendStartStreamWithParams:OCMOCK_ANY recipient:nil callback:OCMOCK_ANY timeoutAfter:30.0]).andDo(^(NSInvocation *invocation) {
    [startStreamSent fulfill];
  });

  ZCCOutgoingVoiceStream *stream = [session startVoiceMessage];
  XCTAssertNotNil(stream);
  XCTAssertEqual([XCTWaiter waitForExpectations:@[startStreamSent] timeout:3.0], XCTWaiterResultCompleted);

  OCMVerifyAll(self.socket);
}

// Verify that we start opening a stream to a specific user if we're connected and have microphone permission
- (void)testStartVoiceMessageToUser_ConnectedMicrophonePermissionGranted_StartsConnecting {
  OCMStub([self.permissionsManager recordPermission]).andReturn(AVAudioSessionRecordPermissionGranted);
  ZCCSession *session = [self sessionWithUsername:nil password:nil];
  [self connectSession:session];

  XCTestExpectation *startStreamSent = [[XCTestExpectation alloc] initWithDescription:@"start_stream sent"];
  OCMExpect([self.socket sendStartStreamWithParams:OCMOCK_ANY recipient:@"exampleUser" callback:OCMOCK_ANY timeoutAfter:30.0]).andDo(^(NSInvocation *invocation) {
    [startStreamSent fulfill];
  });

  ZCCOutgoingVoiceStream *stream = [session startVoiceMessageToUser:@"exampleUser"];
  XCTAssertNotNil(stream);
  XCTAssertEqual([XCTWaiter waitForExpectations:@[startStreamSent] timeout:3.0], XCTWaiterResultCompleted);
  OCMVerifyAll(self.socket);
}

// Verify that we report to the delegate if there is an error opening the stream
- (void)testStartVoiceMessage_ConnectedMicrophonePermissionGrantedErrorOpening_ReportsToDelegate {
  OCMStub([self.permissionsManager recordPermission]).andReturn(AVAudioSessionRecordPermissionGranted);
  ZCCSession *session = [self sessionWithUsername:nil password:nil];
  [self connectSession:session];

  XCTestExpectation *startStreamSent = [[XCTestExpectation alloc] initWithDescription:@"start_stream sent"];
  __block ZCCStartStreamCallback streamStarted;
  OCMExpect([self.socket sendStartStreamWithParams:OCMOCK_ANY recipient:nil callback:OCMOCK_ANY timeoutAfter:30.0]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained ZCCStartStreamCallback callback = nil;
    [invocation getArgument:&callback atIndex:4];
    streamStarted = callback;
    [startStreamSent fulfill];
  });

  ZCCOutgoingVoiceStream *stream = [session startVoiceMessage];
  XCTestExpectation *streamDidEncounterError = [[XCTestExpectation alloc] initWithDescription:@"Delegate informed of stream error"];
  OCMExpect([self.sessionDelegate session:session outgoingVoice:stream didEncounterError:OCMOCK_ANY]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained NSError *error = nil;
    [invocation getArgument:&error atIndex:4];
    XCTAssertEqualObjects(error.domain, ZCCErrorDomain);
    XCTAssertEqual(error.code, ZCCErrorCodeWebSocketError);
    XCTAssertEqualObjects(error.userInfo[ZCCErrorWebSocketReasonKey], @"Uh oh");
    [streamDidEncounterError fulfill];
  });

  XCTAssertNotNil(stream);
  XCTAssertEqual([XCTWaiter waitForExpectations:@[startStreamSent] timeout:3.0], XCTWaiterResultCompleted);
  XCTAssertNotNil(streamStarted);

  if (streamStarted) {
    streamStarted(NO, 0, @"Uh oh");
  }
  XCTAssertEqual([XCTWaiter waitForExpectations:@[streamDidEncounterError] timeout:3.0], XCTWaiterResultCompleted);
  OCMVerifyAll(self.socket);
  OCMVerifyAll(self.sessionDelegate);
}

// Verify that we pass correct parameters when starting a stream with a recipient and a custom source
- (void)testVoiceMessageToUser_startsStream {
  OCMStub([self.permissionsManager recordPermission]).andReturn(AVAudioSessionRecordPermissionGranted);
  ZCCSession *session = [self sessionWithUsername:nil password:nil];
  [self connectSession:session];

  XCTestExpectation *sentCommand = [[XCTestExpectation alloc] initWithDescription:@"start_stream sent"];
  OCMExpect([self.socket sendStartStreamWithParams:OCMOCK_ANY recipient:@"bogusUser" callback:OCMOCK_ANY timeoutAfter:30.0]).andDo(^(NSInvocation *invocation) {
    [sentCommand fulfill];
  });

  ZCCOutgoingVoiceConfiguration *source = [[ZCCOutgoingVoiceConfiguration alloc] init];
  source.sampleRate = [ZCCOutgoingVoiceConfiguration.supportedSampleRates firstObject].unsignedIntegerValue;
  XCTAssertNotNil([session startVoiceMessageToUser:@"bogusUser" source:source]);

  XCTAssertEqual([XCTWaiter waitForExpectations:@[sentCommand] timeout:3.0], XCTWaiterResultCompleted);
  OCMVerifyAll(self.socket);
}

#pragma mark -sendImage:

// Verify that -sendImage: sends the image
- (void)testSendImage_SendsStartImage {
  UIImage *testImage = solidImage(UIColor.redColor, CGSizeMake(100.0f, 100.0f), 1.0);
  ZCCSession *session = [self sessionWithUsername:nil password:nil];
  [self connectSession:session];

  ZCCImageMessage *expected = [[ZCCImageMessageBuilder builderWithImage:testImage] message];
  OCMExpect([self.socket sendImage:expected callback:OCMOCK_ANY timeoutAfter:30.0]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained ZCCSendImageCallback callback;
    [invocation getArgument:&callback atIndex:3];
    callback(YES, 32, nil);
  });
  OCMExpect([self.socket sendImageData:expected imageId:32]);

  XCTAssertTrue([session sendImage:testImage]);

  OCMVerifyAll(self.socket);
}

// Verify that -sendImage:toUser: sends to the recipient
- (void)testSendImageToUser_sendsToRecipient {
  UIImage *testImage = solidImage(UIColor.redColor, CGSizeMake(100.0f, 100.0f), 1.0);
  ZCCSession *session = [self sessionWithUsername:nil password:nil];
  [self connectSession:session];

  ZCCImageMessageBuilder *builder = [ZCCImageMessageBuilder builderWithImage:testImage];
  [builder setRecipient:@"bogusUser"];
  ZCCImageMessage *expected = [builder message];
  OCMExpect([self.socket sendImage:expected callback:OCMOCK_ANY timeoutAfter:30.0]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained ZCCSendImageCallback callback;
    [invocation getArgument:&callback atIndex:3];
    callback(YES, 32, nil);
  });
  OCMExpect([self.socket sendImageData:expected imageId:32]);

  XCTAssertTrue([session sendImage:testImage toUser:@"bogusUser"]);

  OCMVerifyAll(self.socket);
}

// Verify that -sendImage: and -sendImage:toUser: return failure if the session isn't connected
- (void)testSendImage_notConnected_returnsFalse {
  ZCCSession *session = [self sessionWithUsername:nil password:nil];
  UIImage *image = solidImage(UIColor.redColor, CGSizeMake(100.0f, 100.0f), 1.0);
  XCTAssertFalse([session sendImage:image]);
  XCTAssertFalse([session sendImage:image toUser:@"bogusUser"]);
}

// Verify failure reporting from -sendImage:
- (void)testSendImage_socketFailure_reportsError {
  ZCCSession *session = [self sessionWithUsername:nil password:nil];
  [self connectSession:session];
  UIImage *image = solidImage(UIColor.redColor, CGSizeMake(400.0f, 400.0f), 1.0f);
  ZCCImageMessageBuilder *builder = [ZCCImageMessageBuilder builderWithImage:image];
  ZCCImageMessage *expected = [builder message];
  OCMExpect([self.socket sendImage:expected callback:OCMOCK_ANY timeoutAfter:30.0]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained ZCCSendImageCallback callback;
    [invocation getArgument:&callback atIndex:3];
    callback(NO, 0, @"Failed to send");
  });
  XCTestExpectation *errorReported = [[XCTestExpectation alloc] initWithDescription:@"Session reported error to delegate"];
  NSError *expectedError = [NSError errorWithDomain:ZCCErrorDomain code:ZCCErrorCodeUnknown userInfo:@{ZCCServerErrorMessageKey:@"Failed to send"}];
  OCMExpect([self.sessionDelegate session:session didEncounterError:expectedError]).andDo(^(NSInvocation *invocation) {
    [errorReported fulfill];
  });

  [session sendImage:image];

  XCTAssertEqual([XCTWaiter waitForExpectations:@[errorReported] timeout:3.0], XCTWaiterResultCompleted);
  OCMVerifyAll(self.socket);
}

// Verify receiving images
- (void)testOnImage_SendsImageToDelegate {
  ZCCSession *session = [self sessionWithUsername:nil password:nil];
  [self connectSession:session];

  UIImage *testImage = solidImage(UIColor.redColor, CGSizeMake(400.0, 400.0), 1.0);
  NSData *testImageData = UIImageJPEGRepresentation(testImage, 0.75);
  UIImage *thumbnailImage = [ZCCImageUtils resizeImage:testImage maxSize:CGSizeMake(90.0, 90.0) ignoringScreenScale:YES];
  NSData *thumbnailImageData = UIImageJPEGRepresentation(thumbnailImage, 0.75);

  id uiImage = OCMClassMock([UIImage class]);
  __block UIImage *receivedImage;
  __block UIImage *receivedThumbnail;

  OCMStub(ClassMethod([uiImage imageWithData:testImageData])).andDo(^(NSInvocation *invocation) {
    receivedImage = [[UIImage alloc] initWithData:testImageData];
    [invocation setReturnValue:&receivedImage];
  });
  OCMStub(ClassMethod([uiImage imageWithData:thumbnailImageData])).andDo(^(NSInvocation *invocation) {
    receivedThumbnail = [[UIImage alloc] initWithData:thumbnailImageData];
    [invocation setReturnValue:&receivedThumbnail];
  });

  XCTestExpectation *receivedThumbnailExpectation = [[XCTestExpectation alloc] initWithDescription:@"Received thumbnail callback"];
  OCMExpect([self.sessionDelegate session:session didReceiveImage:[OCMArg checkWithBlock:^BOOL(ZCCImageInfo *actual) {
    if (actual.imageId != 345) {
      return NO;
    }
    if (![actual.sender isEqualToString:@"bogusSender"]) {
      return NO;
    }
    if (actual.thumbnail != receivedThumbnail) {
      return NO;
    }
    if (actual.image) {
      return NO;
    }
    return YES;
  }]]).andDo(^(NSInvocation *invocation) {
    [receivedThumbnailExpectation fulfill];
  });

  ZCCImageHeader *header = [[ZCCImageHeader alloc] init];
  header.imageId = 345;
  header.sender = @"bogusSender";
  header.imageType = ZCCImageTypeJPEG;
  header.height = 400;
  header.width = 400;
  [session socket:self.socket didReceiveImageHeader:header];
  [session socket:self.socket didReceiveImageData:thumbnailImageData imageId:345 isThumbnail:YES];
  XCTAssertEqual([XCTWaiter waitForExpectations:@[receivedThumbnailExpectation] timeout:3.0], XCTWaiterResultCompleted);

  XCTestExpectation *receivedImageExpectation = [[XCTestExpectation alloc] initWithDescription:@"Received image callback"];
  OCMExpect([self.sessionDelegate session:session didReceiveImage:[OCMArg checkWithBlock:^BOOL(ZCCImageInfo *actualInfo) {
    if (actualInfo.imageId != 345) {
      return NO;
    }
    if (![actualInfo.sender isEqualToString:@"bogusSender"]) {
      return NO;
    }
    if (actualInfo.image != receivedImage) {
      return NO;
    }
    if (actualInfo.thumbnail != receivedThumbnail) {
      return NO;
    }
    return YES;
  }]]).andDo(^(NSInvocation *invocation) {
    [receivedImageExpectation fulfill];
  });

  [session socket:self.socket didReceiveImageData:testImageData imageId:345 isThumbnail:NO];
  XCTAssertEqual([XCTWaiter waitForExpectations:@[receivedImageExpectation] timeout:3.0], XCTWaiterResultCompleted);

  OCMVerifyAll(self.sessionDelegate);
  [uiImage stopMocking];
}

#pragma mark -sendText:

- (void)testSendText_SendsSocketMessage {
  ZCCSession *session = [self sessionWithUsername:nil password:nil];
  [self connectSession:session];

  XCTestExpectation *textSent = [[XCTestExpectation alloc] initWithDescription:@"send_text_message sent"];
  OCMExpect([self.socket sendTextMessage:@"test message" recipient:nil timeoutAfter:30.0]).andDo(^(NSInvocation *invocation) {
    [textSent fulfill];
  });
  [session sendText:@"test message"];

  XCTAssertEqual([XCTWaiter waitForExpectations:@[textSent] timeout:3.0], XCTWaiterResultCompleted);
  OCMVerifyAll(self.socket);
}

- (void)testSendTextToUser_SendsSocketMessage {
  ZCCSession *session = [self sessionWithUsername:nil password:nil];
  [self connectSession:session];

  XCTestExpectation *textSent = [[XCTestExpectation alloc] initWithDescription:@"send_text_message sent"];
  OCMExpect([self.socket sendTextMessage:@"test message" recipient:@"bogusUser" timeoutAfter:30.0]).andDo(^(NSInvocation *invocation) {
    [textSent fulfill];
  });
  [session sendText:@"test message" toUser:@"bogusUser"];

  XCTAssertEqual([XCTWaiter waitForExpectations:@[textSent] timeout:3.0], XCTWaiterResultCompleted);
  OCMVerifyAll(self.socket);
}

#pragma mark Location messages

// Verify that -sendLocation returns false if we don't have access to location services
- (void)testSendLocation_NoLocationAccess_ReturnsFalse {
  ZCCSession *session = [self sessionWithUsername:nil password:nil];

  // Verify we don't send location if we aren't connected
  self.locationService.locationServicesEnabled = YES;
  self.locationService.authorizationStatus = kCLAuthorizationStatusAuthorizedWhenInUse;
  XCTAssertFalse([session sendLocationWithContinuation:nil]);

  [self connectSession:session];
  self.locationService.locationServicesEnabled = YES;
  self.locationService.authorizationStatus = kCLAuthorizationStatusDenied;
  XCTAssertFalse([session sendLocationWithContinuation:nil]);

  self.locationService.authorizationStatus = kCLAuthorizationStatusRestricted;
  XCTAssertFalse([session sendLocationWithContinuation:nil]);

  self.locationService.authorizationStatus = kCLAuthorizationStatusNotDetermined;
  XCTAssertFalse([session sendLocationWithContinuation:nil]);

  self.locationService.authorizationStatus = kCLAuthorizationStatusAuthorizedWhenInUse;
  self.locationService.locationServicesEnabled = NO;
  XCTAssertFalse([session sendLocationWithContinuation:nil]);
}

// Verify that sendLocation sends the current location when we do have access to location services
- (void)testSendLocation_sendsLocation {
  [self enableLocationServices];
  CLLocation *bogusLocation = [self mockedLocation];
  ZCCLocationInfo *expectedLocationInfo = [self expectedLocationInfo];
  expectedLocationInfo.address = @"Bogus address, Anytown";
  id placemark = OCMClassMock([CLPlacemark class]);
  OCMExpect([self.addressFormattingService stringFromPlacemark:placemark]).andReturn(@"Bogus address, Anytown");
  OCMStub([self.geocodingService reverseGeocodeLocation:bogusLocation completionHandler:OCMOCK_ANY]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained CLGeocodeCompletionHandler completionHandler;
    [invocation getArgument:&completionHandler atIndex:3];
    completionHandler(@[placemark], nil);
  });

  ZCCSession *session = [self sessionWithUsername:nil password:nil];
  [self connectSession:session];

  XCTestExpectation *callbackCalled = [[XCTestExpectation alloc] initWithDescription:@"-sendLocation callback called"];
  XCTAssertTrue([session sendLocationWithContinuation:^(ZCCLocationInfo *locationInfo, NSError *error) {
    XCTAssertEqualObjects(locationInfo, expectedLocationInfo);
    [callbackCalled fulfill];
  }]);

  OCMVerify([self.socket sendLocation:expectedLocationInfo recipient:nil timeoutAfter:30.0]);
  XCTAssertEqual([XCTWaiter waitForExpectations:@[callbackCalled] timeout:3.0], XCTWaiterResultCompleted);
}

- (void)testSendLocationToUser_sendsSocketMessage {
  [self enableLocationServices];
  ZCCSession *session = [self sessionWithUsername:nil password:nil];
  [self connectSession:session];

  // Message isn't sent until geocoding service returns value
  OCMStub([self.geocodingService reverseGeocodeLocation:OCMOCK_ANY completionHandler:OCMOCK_ANY]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained void (^handler)(NSArray *, NSError *) = nil;
    [invocation getArgument:&handler atIndex:3];
    handler(nil, nil);
  });
  XCTAssertTrue([session sendLocationToUser:@"bogusUser" continuation:nil]);

  ZCCLocationInfo *expectedLocationInfo = [self expectedLocationInfo];
  OCMVerify([self.socket sendLocation:expectedLocationInfo recipient:@"bogusUser" timeoutAfter:30.0]);
}

- (CLLocation *)mockedLocation {
  static CLLocation *location = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    CLLocationCoordinate2D coordinate;
    coordinate.latitude = 45.0;
    coordinate.longitude = 32.5;
    location = [[CLLocation alloc] initWithCoordinate:coordinate altitude:0.0 horizontalAccuracy:15.0 verticalAccuracy:0.0 timestamp:[NSDate dateWithTimeIntervalSinceReferenceDate:0.0]];
  });
  return location;
}

- (void)enableLocationServices {
  self.locationService.locationServicesEnabled = YES;
  self.locationService.authorizationStatus = kCLAuthorizationStatusAuthorizedWhenInUse;
  CLLocation *bogusLocation = [self mockedLocation];
  self.locationService.mockedRequestLocation = ^(ZCCLocationRequestCallback callback) {
    callback(bogusLocation, nil);
  };
}

- (ZCCLocationInfo *)expectedLocationInfo {
  ZCCLocationInfo *expectedLocationInfo = [[ZCCLocationInfo alloc] init];
  expectedLocationInfo.latitude = 45.0;
  expectedLocationInfo.longitude = 32.5;
  expectedLocationInfo.accuracy = 15.0;
  return expectedLocationInfo;
}

// Verify that we report a received location
- (void)testIncomingLocation_reportsToDelegate {
  ZCCSession *session = [self sessionWithUsername:nil password:nil];
  [self connectSession:session];

  ZCCLocationInfo *location = [self expectedLocationInfo];
  location.address = @"Bogus address, Anytown";
  XCTestExpectation *calledDelegate = [[XCTestExpectation alloc] initWithDescription:@"Sent location to delegate"];
  OCMExpect([self.sessionDelegate session:session didReceiveLocation:location from:@"bogusSender"]).andDo(^(NSInvocation *invocation) {
    [calledDelegate fulfill];
  });

  [session socket:self.socket didReceiveLocationMessage:location sender:@"bogusSender"];

  XCTAssertEqual([XCTWaiter waitForExpectations:@[calledDelegate] timeout:3.0], XCTWaiterResultCompleted);
  OCMVerifyAll(self.sessionDelegate);
}

#pragma mark ZCCSocketDelegate

// Verify that we report a connection loss during logon correctly
- (void)testSocketDidClose_LogonInProcess_CallsFailToConnect {
  ZCCSession *session = [self sessionWithUsername:nil password:nil];
  [self expectSocketOpened];
  [session connect];
  XCTAssertEqual([XCTWaiter waitForExpectations:@[self.socketOpened] timeout:3.0], XCTWaiterResultCompleted);

  XCTestExpectation *failedToConnect = [[XCTestExpectation alloc] initWithDescription:@"Delegate informed of failed connection"];
  OCMExpect([self.sessionDelegate session:session didFailToConnectWithError:OCMOCK_ANY]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained NSError *error = nil;
    [invocation getArgument:&error atIndex:3];
    XCTAssertEqualObjects(error.domain, ZCCErrorDomain);
    XCTAssertEqual(error.code, ZCCErrorCodeWebSocketError);
    XCTAssertEqualObjects(error.userInfo[ZCCErrorWebSocketReasonKey], @"Uh oh");
    [failedToConnect fulfill];
  });
  OCMReject([self.sessionDelegate sessionDidDisconnect:OCMOCK_ANY]);

  NSError *socketError = [NSError errorWithDomain:ZCCErrorDomain code:ZCCErrorCodeWebSocketError userInfo:@{ZCCErrorWebSocketReasonKey:@"Uh oh"}];
  [session socketDidClose:self.socket withError:socketError];
  XCTAssertEqual([XCTWaiter waitForExpectations:@[failedToConnect] timeout:3.0], XCTWaiterResultCompleted);

  OCMVerifyAll(self.socket);
  OCMVerifyAll(self.sessionDelegate);
  XCTAssertEqual(session.state, ZCCSessionStateDisconnected);
}

// Verify that we report a connection loss after successful connection correctly
- (void)testSocketDidClose_ConnectionComplete_CallsDisconnected {
  ZCCSession *session = [self sessionWithUsername:nil password:nil];
  [self connectSession:session];

  XCTestExpectation *disconnected = [[XCTestExpectation alloc] initWithDescription:@"Delegate informed of disconnection"];
  OCMExpect([self.sessionDelegate sessionDidDisconnect:session]).andDo(^(NSInvocation *invocation) {
    [disconnected fulfill];
  });
  OCMReject([self.sessionDelegate session:OCMOCK_ANY didFailToConnectWithError:OCMOCK_ANY]);

  [session socketDidClose:self.socket withError:nil];
  XCTAssertEqual([XCTWaiter waitForExpectations:@[disconnected] timeout:3.0], XCTWaiterResultCompleted);

  OCMVerifyAll(self.socket);
  OCMVerifyAll(self.sessionDelegate);
  XCTAssertEqual(session.state, ZCCSessionStateDisconnected);
}

// Verify that we prompt the delegate for player override and start processing when a stream starts
- (void)testSocketDidStartStreamWithId_PromptsDelegateForReceiverOverride {
  ZCCSession *session = [self sessionWithUsername:nil password:nil];
  id streamsManager = OCMClassMock([ZCCVoiceStreamsManager class]);
  session.streamsManager = streamsManager;
  [self connectSession:session];

  ZCCIncomingVoiceStreamInfo *info = [[ZCCIncomingVoiceStreamInfo alloc] initWithChannel:@"test" sender:@"sender"];
  OCMExpect([self.sessionDelegate session:session incomingVoiceWillStart:info]).andReturn(nil);

  ZCCStreamParams *params = [[ZCCStreamParams alloc] init];
  params.codecName = @"bogusCodec";
  params.type = @"bogusType";
  params.codecHeader = [NSData data];
  params.packetDuration = 46;
  [session socket:self.socket didStartStreamWithId:23 params:params channel:@"test" sender:@"sender"];

  OCMVerifyAll(self.sessionDelegate);
  OCMVerify([streamsManager onIncomingStreamStart:23 header:params.codecHeader packetDuration:46 channel:@"test" from:@"sender" receiverConfiguration:nil]);
}

// Verify that we pass custom receiver configuration when delegate specifies one
- (void)testSocketDidStartStreamWithId_CustomReceiver_CreatesStreamWithReceiverConfiguration {
  ZCCSession *session = [self sessionWithUsername:nil password:nil];
  id streamsManager = OCMClassMock([ZCCVoiceStreamsManager class]);
  session.streamsManager = streamsManager;
  [self connectSession:session];

  ZCCIncomingVoiceStreamInfo *info = [[ZCCIncomingVoiceStreamInfo alloc] initWithChannel:@"test" sender:@"sender"];
  ZCCIncomingVoiceConfiguration *config = [[ZCCIncomingVoiceConfiguration alloc] init];
  config.playThroughSpeaker = NO;
  id customReceiver = OCMProtocolMock(@protocol(ZCCVoiceReceiver));
  config.receiver = customReceiver;
  OCMExpect([self.sessionDelegate session:session incomingVoiceWillStart:info]).andReturn(config);

  ZCCStreamParams *params = [[ZCCStreamParams alloc] init];
  params.codecName = @"bogusCodec";
  params.type = @"bogusType";
  params.codecHeader = [NSData data];
  params.packetDuration = 46;
  [session socket:self.socket didStartStreamWithId:23 params:params channel:@"test" sender:@"sender"];

  OCMVerifyAll(self.sessionDelegate);
  OCMVerify([streamsManager onIncomingStreamStart:23 header:params.codecHeader packetDuration:46 channel:@"test" from:@"sender" receiverConfiguration:[OCMArg checkWithBlock:^BOOL(ZCCIncomingVoiceConfiguration *actual) {
    return actual.playThroughSpeaker == NO && actual.receiver == customReceiver;
  }]]);
}

// Verify that we report text messages
- (void)testSocketDidReceiveText_CallsDelegate {
  ZCCSession *session = [self sessionWithUsername:nil password:nil];
  [self connectSession:session];

  XCTestExpectation *received = [[XCTestExpectation alloc] initWithDescription:@"Received text"];
  OCMExpect([self.sessionDelegate session:session didReceiveText:@"test message" from:@"exampleSender"]).andDo(^(NSInvocation *invocation) {
    [received fulfill];
  });

  [session socket:self.socket didReceiveTextMessage:@"test message" sender:@"exampleSender"];

  XCTAssertEqual([XCTWaiter waitForExpectations:@[received] timeout:3.0], XCTWaiterResultCompleted);
  OCMVerifyAll(self.sessionDelegate);
}

@end
