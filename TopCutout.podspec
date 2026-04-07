Pod::Spec.new do |s|
  s.name             = 'TopCutout'
  s.version          = '0.2.0'
  s.summary          = 'Top cutout geometry for iPhone screens, including notch and Dynamic Island layouts.'
  s.description      = <<-DESC
TopCutout is an iOS library that exposes generated top cutout metadata for iPhone screens.
It provides runtime lookup for the current device, cutout geometry helpers, and optional sensor housing paths.
  DESC
  s.homepage         = 'https://github.com/rijieli/TopCutout'
  s.license          = { :type => 'Apache-2.0', :file => 'LICENSE' }
  s.author           = 'rijieli'
  s.source           = { :git => 'https://github.com/rijieli/TopCutout.git', :tag => s.version.to_s }

  s.platform         = :ios, '15.0'
  s.swift_versions   = ['5.8']
  s.source_files     = 'Sources/TopCutout/**/*.swift'
  s.frameworks       = 'UIKit', 'SwiftUI'
end
