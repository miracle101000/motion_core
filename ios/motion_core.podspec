#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint motion_core.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'motion_core'
  s.version          = '0.1.0'
  s.summary          = 'Unified fused device-motion stream for Flutter, backed by Core Motion.'
  s.description      = <<-DESC
A Flutter plugin that exposes iOS Core Motion (CMDeviceMotion) and Android sensor
fusion through one stream with identical axes, units and reference frames:
attitude, gravity, user acceleration, rotation rate, calibrated magnetic field and heading.
                       DESC
  s.homepage         = 'https://github.com/miracle101000/motion_core'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'miracle101000' => 'https://github.com/miracle101000' }
  s.source           = { :path => '.' }
  s.source_files = 'motion_core/Sources/motion_core/**/*.swift'
  s.dependency 'Flutter'
  s.frameworks = 'CoreMotion'
  s.platform = :ios, '12.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # Privacy manifest (motion data is not a "required reason" API, but SDKs are
  # expected to ship a manifest).
  s.resource_bundles = {'motion_core_privacy' => ['motion_core/Sources/motion_core/PrivacyInfo.xcprivacy']}
end
