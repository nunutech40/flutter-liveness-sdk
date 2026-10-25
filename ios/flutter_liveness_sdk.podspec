Pod::Spec.new do |s|
  s.name = 'flutter_liveness_sdk'
  s.version = '0.1.0'
  s.summary = 'Native face action liveness capture for Flutter.'
  s.description = 'Camera based face action challenges for Android and iOS Flutter apps.'
  s.homepage = 'https://github.com/nunutech40/flutter-liveness-sdk'
  s.license = { :file => '../LICENSE' }
  s.author = { 'nunutech40' => 'https://github.com/nunutech40' }
  s.source = { :path => '.' }
  s.source_files = 'Classes/**/*.swift'
  s.static_framework = true
  s.dependency 'Flutter'
  s.dependency 'GoogleMLKit/FaceDetection', '~> 9.0'
  s.platform = :ios, '15.5'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
