#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint fl_pip.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'fl_pip'
  s.version          = '4.0.0'
  s.summary          = 'A Flutter plugin that displays any Flutter widget in a picture-in-picture window.'
  s.description      = <<-DESC
A Flutter plugin for Android and iOS that displays any Flutter widget in a native
picture-in-picture window.
                       DESC
  s.homepage         = 'https://github.com/Wayaer/fl_pip'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Wayaer' => 'https://github.com/Wayaer' }
  s.source           = { :path => '.' }
  s.source_files     = 'fl_pip/Sources/fl_pip/**/*.swift'
  s.ios.deployment_target = '15.0'
  s.dependency 'Flutter'
  s.dependency 'fl_multi_engine'
  s.resource_bundles = { 'fl_pip_privacy' => ['fl_pip/Sources/fl_pip/PrivacyInfo.xcprivacy'] }
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
