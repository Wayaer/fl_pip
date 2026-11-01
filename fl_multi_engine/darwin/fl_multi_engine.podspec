#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint fl_multi_engine.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'fl_multi_engine'
  s.version          = '0.0.1'
  s.summary          = 'Creates, destroys and connects named Flutter engines.'
  s.description      = <<-DESC
Creates, destroys and connects named Flutter engines on Android, iOS, HarmonyOS, macOS, Windows and Linux.
                       DESC
  s.homepage         = 'https://github.com/Wayaer/fl_pip'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Wayaer' => 'https://github.com/Wayaer' }

  s.source           = { :path => '.' }
  s.source_files = 'fl_multi_engine/Sources/fl_multi_engine/**/*.swift'

  # Set the deployment targets for both iOS and macOS.
  s.ios.deployment_target = '15.0'
  s.osx.deployment_target = '12.0'

  # Define the platform-specific dependencies.
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'

  # Flutter.framework does not contain a i386 slice, which is specific to iOS.
  s.ios.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.osx.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'fl_multi_engine_privacy' => ['fl_multi_engine/Sources/fl_multi_engine/PrivacyInfo.xcprivacy']}
end
