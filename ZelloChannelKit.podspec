# coding: utf-8
#
#  Be sure to run `pod spec lint ZelloChannelKit.podspec' to ensure this is a
#  valid spec and to remove all comments including this before submitting the spec.
#
#  To learn more about Podspec attributes see https://guides.cocoapods.org/syntax/podspec.html
#  To see working Podspecs in the CocoaPods repo see https://github.com/CocoaPods/Specs/
#

Pod::Spec.new do |spec|

  # ―――  Spec Metadata  ―――――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  #
  #  These will help people to find your library, and whilst it
  #  can feel like a chore to fill in it's definitely to your advantage. The
  #  summary should be tweet-length, and the description more in depth.
  #

  spec.name         = "ZelloChannelKit"
  spec.version      = "0.5.1"
  spec.summary      = "WebSocket based API to connect to Zello channels"

  # This description is used to generate tags and improve search results.
  #   * Think: What does it do? Why did you write it? What is the focus?
  #   * Try to keep it short, snappy and to the point.
  #   * Write the description between the DESC delimiters below.
  #   * Finally, don't worry about the indent, CocoaPods strips it!
  spec.description  = <<-DESC
The Zello Channels SDK allows you to integrate Zello push-to-talk into your own application. The SDK communicates with a Zello server over a web socket connection using a JSON-based protocol, and offers a simple API for connecting to a Zello channel and sending and receiving audio. Supported features include:

Send voice messages from the device microphone
Play incoming voice messages through the device speaker
Send voice messages from your own audio code, e.g. from a file
Receive voice message data with your own audio code with optional pass-through to the device speaker
The protocol specification is also available if you prefer to develop your own client in-house.
                   DESC

  spec.homepage     = "https://github.com/zelloptt/zello-channel-api/"
  # spec.screenshots  = "www.example.com/screenshots_1.gif", "www.example.com/screenshots_2.gif"


  # ―――  Spec License  ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  #
  #  Licensing your code is important. See https://choosealicense.com for more info.
  #  CocoaPods will detect a license file if there is a named LICENSE*
  #  Popular ones are 'MIT', 'BSD' and 'Apache License, Version 2.0'.
  #

  spec.license      = "MIT"
  # spec.license      = { :type => "MIT", :file => "FILE_LICENSE" }


  # ――― Author Metadata  ――――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  #
  #  Specify the authors of the library, with email addresses. Email addresses
  #  of the authors are extracted from the SCM log. E.g. $ git log. CocoaPods also
  #  accepts just a name if you'd rather not provide an email address.
  #
  #  Specify a social_media_url where others can refer to, for example a twitter
  #  profile URL.
  #

  spec.author             = { "Greg Cooksey" => "greg@zello.com" }
  # Or just: spec.author    = "Greg Cooksey"
  # spec.authors            = { "Greg Cooksey" => "greg@zello.com" }
  # spec.social_media_url   = "https://twitter.com/Greg Cooksey"

  # ――― Platform Specifics ――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  #
  #  If this Pod runs only on iOS or OS X, then specify the platform and
  #  the deployment target. You can optionally include the target after the platform.
  #

  # spec.platform     = :ios
  spec.platform     = :ios, "9.3"

  #  When using multiple platforms
  # spec.ios.deployment_target = "5.0"
  # spec.osx.deployment_target = "10.7"
  # spec.watchos.deployment_target = "2.0"
  # spec.tvos.deployment_target = "9.0"


  # ――― Source Location ―――――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  #
  #  Specify the location from where the source should be retrieved.
  #  Supports git, hg, bzr, svn and HTTP.
  #

  spec.source       = { :git => "https://github.com/zelloptt/zello-ios-sdk.git", :tag => "v#{spec.version}" }


  # ――― Source Code ―――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  #
  #  CocoaPods is smart about how it includes source code. For source files
  #  giving a folder will include any swift, h, m, mm, c & cpp files.
  #  For header files it will include any header in the folder.
  #  Not including the public_header_files will make all headers public.
  #

  spec.source_files  = "ZelloChannelKit/ZelloChannelKit/**/*.{h,m,mm}"
  # spec.exclude_files = "Classes/Exclude"

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
  
  # libopus
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

  # SocketRocket
  spec.subspec 'SocketRocket' do |sr|
    sr.source_files = "ZelloChannelKit/ZelloChannelKit/network/SocketRocket/**/*.{h,m}"
    sr.private_header_files = "ZelloChannelKit/ZelloChannelKit/network/SocketRocket/**/*.h"
    sr.compiler_flags = "-Wno-implicit-retain-self", "-Wno-switch"
  end
  
  spec.module_map = "ZelloChannelKit/ZelloChannelKit.modulemap"


  # ――― Project Linking ―――――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  #
  #  Link your library with frameworks, or libraries. Libraries do not include
  #  the lib prefix of their name.
  #

  # spec.framework  = "SomeFramework"
  # spec.frameworks = "SomeFramework", "AnotherFramework"

  # spec.library   = "iconv"
  # spec.libraries = "iconv", "xml2"
  spec.libraries = "icucore", "c++"
  # spec.vendored_libraries = "ZelloChannelKit/ZelloChannelKit/libopus.a"

  # ――― Project Settings ――――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  #
  #  If your library depends on compiler flags you can set them in the xcconfig hash
  #  where they will only apply to your library. If you depend on other Podspecs
  #  you can include multiple dependencies to ensure it works.

  # spec.requires_arc = true

  # spec.xcconfig = { "HEADER_SEARCH_PATHS" => "$(SDKROOT)/usr/include/libxml2" }
  # spec.dependency "JSONKit", "~> 1.4"

end
