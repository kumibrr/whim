Pod::Spec.new do |spec|
  spec.name = 'WhimCore'
  spec.version = '1.0.0'
  spec.summary = 'Canonical native behavior for Whim.'
  spec.description = 'Shared recording, Note, and Delivery behavior for Whim Apple targets.'
  spec.homepage = 'https://github.com/whim-app/whim'
  spec.license = { type: 'MIT', file: '../../LICENSE' }
  spec.author = { 'Whim' => 'opensource@whim.app' }
  spec.source = { git: 'https://github.com/whim-app/whim.git', tag: spec.version.to_s }
  spec.platform = :ios, '18.0'
  spec.swift_version = '6.0'
  spec.static_framework = true
  spec.dependency 'GRDB.swift', '7.11.1'
  spec.source_files = 'Sources/WhimCore/**/*.swift'
  spec.exclude_files = [
    'Sources/WhimCore/**/*.test.swift',
    'Sources/WhimCore/**/*.integration.test.swift',
  ]
  spec.resource_bundles = {
    'WhimCoreConfigurationTest' => [
      'Sources/WhimCore/WebhookConfiguration/Fixtures/configuration-test-fixture.m4a',
    ],
  }
end
