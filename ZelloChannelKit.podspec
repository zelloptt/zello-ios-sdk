# coding: utf-8
Pod::Spec.new do |spec|

  spec.name         = "ZelloChannelKit"
  spec.version      = "0.5.5"
  spec.summary      = "WebSocket based API to connect to Zello channels"
  spec.description  = <<-DESC
The Zello Channels SDK allows you to integrate Zello push-to-talk into your own application. The SDK communicates with a Zello server over a web socket connection using a JSON-based protocol, and offers a simple API to send and receive audio, images, and text over Zello channels. Supported features include:

Send voice messages from the device microphone
Play incoming voice messages through the device speaker
Send voice messages from your own audio code, e.g. from a file
Receive voice message data with your own audio code with optional pass-through to the device speaker
Send and recieve text messages
Send and receive images
Send the device's current location, and receive location messages from other users
The protocol specification is also available if you prefer to develop your own client in-house.
                   DESC

  spec.homepage     = "https://github.com/zelloptt/zello-channel-api/"
  spec.license      = "MIT"
  spec.author       = { "Zello, Inc." => "dev@zello.com" }
  spec.platform     = :ios, "9.3"

  spec.source       = { :git => "https://github.com/zelloptt/zello-ios-sdk.git", :tag => "v#{spec.version}" }


  spec.source_files  = "ZelloChannelKit/ZelloChannelKit/**/*.{h,m,mm}"
  spec.public_header_files = [
    "ZelloChannelKit/ZelloChannelKit/ZelloChannelKit.h",
    "ZelloChannelKit/ZelloChannelKit/ZCCErrors.h",
    "ZelloChannelKit/ZelloChannelKit/images/ZCCImageInfo.h",
    "ZelloChannelKit/ZelloChannelKit/streams/ZCCIncomingVoiceConfiguration.h",
    "ZelloChannelKit/ZelloChannelKit/streams/zCCIncomingVoiceStream.h",
    "ZelloChannelKit/ZelloChannelKit/location/ZCCLocationInfo.h",
    "ZelloChannelKit/ZelloChannelKit/streams/ZCCOutgoingVoiceConfiguration.h",
    "ZelloChannelKit/ZelloChannelKit/streams/ZCCOutgoingVoiceStream.h",
    "ZelloChannelKit/ZelloChannelKit/ZCCSession.h",
    "ZelloChannelKit/ZelloChannelKit/streams/ZCCStreamState.h",
    "ZelloChannelKit/ZelloChannelKit/ZCCTypes.h",
    "ZelloChannelKit/ZelloChannelKit/streams/ZCCVoiceStream.h"
  ]
  
  spec.subspec 'libopus' do |opus|
    opus.source_files = "LibOpus/CSource/**/*.{h,cpp}"
    opus.private_header_files = "LibOpus/CSource/**/*.h"
    opus.preserve_paths = "LibOpus/CSource/include/opus/*.h"
    opus.compiler_flags = "-Wno-implicit-retain-self"
    opus.library = "c++"
    opus.xcconfig = {
      'CLANG_CXX_LANGUAGE_STANDARD' => 'c++11',
      'CLANG_CXX_LIBRARY' => 'libc++'
    }
    opus.vendored_library = "ZelloChannelKit/ZelloChannelKit/libopus.a"
  end

  spec.subspec 'SocketRocket' do |sr|
    sr.source_files = "ZelloChannelKit/ZelloChannelKit/network/SocketRocket/**/*.{h,m}"
    sr.private_header_files = "ZelloChannelKit/ZelloChannelKit/network/SocketRocket/**/*.h"
    sr.compiler_flags = "-Wno-implicit-retain-self", "-Wno-switch"
  end
  
  spec.libraries = "icucore", "c++"

end
