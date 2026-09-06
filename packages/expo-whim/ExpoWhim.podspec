require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

Pod::Spec.new do |spec|
  spec.name = 'ExpoWhim'
  spec.version = package['version']
  spec.summary = package['description']
  spec.description = package['description']
  spec.homepage = package['homepage']
  spec.license = package['license']
  spec.author = package['author']
  spec.source = { git: 'https://github.com/whim-app/whim.git', tag: spec.version.to_s }
  spec.platform = :ios, '18.0'
  spec.swift_version = '6.0'
  spec.static_framework = true
  spec.dependency 'ExpoModulesCore'
  spec.dependency 'WhimCore'
  spec.source_files = 'ios/**/*.{h,m,mm,swift}'
  spec.exclude_files = [
    'ios/**/*.test.swift',
    'ios/**/*.integration.test.swift',
  ]
  spec.resource_bundles = {
    'ExpoWhimContracts' => ['src/events/notes-v1.fixture.json'],
  }
end
