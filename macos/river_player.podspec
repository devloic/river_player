Pod::Spec.new do |s|
  s.name             = 'river_player'
  s.version          = '0.1.4'
  s.summary          = 'Same good old Better Player but it will get updated and fixed.'
  s.description      = <<-DESC
Same good old Better Player but it will get updated and fixed.
                       DESC
  s.homepage         = 'https://github.com/RevEngine3r/river_player'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'RevEngine3r' => 'revengine3r@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :osx, '10.11'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end