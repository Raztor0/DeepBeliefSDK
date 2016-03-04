Pod::Spec.new do |s|
  s.name         = "DeepBeliefSDK"
  s.version      = "1.0.0"
  s.summary      = "This is the Deep Belief SDK for object recognition."
  s.homepage     = "http://github.com/jetpacapp/DeepBeliefSDK"
  s.license      = { :type => 'Commercial', :text => 'Please refer to https://github.com/Raztor0/DeepBeliefSDK/blob/master/LICENSE'}
  s.author       = { "Raztor0" => "https://github.com/Raztor0" }
  s.source       = { :git => 'https://github.com/Raztor0/DeepBeliefSDK.git', :tag => s.version.to_s}
  s.platform = :ios
  s.ios.deployment_target = '8.0'
  s.requires_arc = true
  s.frameworks = 'Accelerate', 'UIKit', 'CoreGraphics', 'Foundation'
  s.vendored_libraries = 'iOSLibrary/DeepBelief.framework/DeepBelief'
end
