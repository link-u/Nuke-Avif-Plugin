#
# Be sure to run `pod lib lint Nuke-Avif-Plugin.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'Nuke-Avif-Plugin'
  s.version          = '0.1.0'
  s.summary          = 'A short description of Nuke-Avif-Plugin.'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = <<-DESC
TODO: Add long description of the pod here.
                       DESC

  s.homepage         = 'https://github.com/link-u/Nuke-Avif-Plugin'
  # s.screenshots     = 'www.example.com/screenshots_1', 'www.example.com/screenshots_2'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'murakami' => 'zonaryfund@gmail.com' }
  s.source           = { :git => 'git@github.com:link-u/Nuke-Avif-Plugin.git', :tag => s.version.to_s }
  
  s.ios.deployment_target = '11.0'

  s.source_files = 'Nuke-Avif-Plugin/**/*'
  s.dependency 'Nuke', '~> 9.0'
  s.dependency 'libavif/libdav1d-8bit'
  s.dependency 'libdav1d/8bit'
  
  # s.resource_bundles = {
  #   'Nuke-Avif-Plugin' => ['Nuke-Avif-Plugin/Assets/*.png']
  # }

  # s.public_header_files = 'Pod/Classes/**/*.h'
  # s.frameworks = 'UIKit', 'MapKit'
  # s.dependency 'AFNetworking', '~> 2.3'
end
