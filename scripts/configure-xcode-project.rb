#!/usr/bin/env ruby

require 'xcodeproj'

project_path = File.expand_path('../ios/whim.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)
app_target = project.targets.find { |target| target.name == 'whim' }
abort 'Expected Expo target named whim' unless app_target

app_group = project.main_group.groups.find { |group| group.display_name == 'whim' }
abort 'Expected Expo source group named whim' unless app_group
scene_delegate = app_group.files.find { |file| file.path == 'whim/SceneDelegate.swift' }
scene_delegate ||= app_group.new_file('whim/SceneDelegate.swift')
unless app_target.source_build_phase.files_references.include?(scene_delegate)
  app_target.add_file_references([scene_delegate])
end

def virtual_group(project, name)
  group = project.main_group.groups.find { |candidate| candidate.display_name == name }
  group ||= project.main_group.new_group(name)
  group.path = nil
  group.name = name
  group
end

def file_reference(group, path)
  group.files.find { |file| file.path == path } || group.new_file(path)
end

def configure_target(target, bundle_identifier, deployment_target)
  target.build_configurations.each do |configuration|
    settings = configuration.build_settings
    settings['CODE_SIGN_STYLE'] = 'Automatic'
    settings['GENERATE_INFOPLIST_FILE'] = 'YES'
    settings['PRODUCT_BUNDLE_IDENTIFIER'] = bundle_identifier
    settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
    settings['SWIFT_VERSION'] = '6.0'
    settings['WATCHOS_DEPLOYMENT_TARGET'] = deployment_target if target.platform_name == :watchos
    settings['IPHONEOS_DEPLOYMENT_TARGET'] = deployment_target if target.platform_name == :ios
  end
end

watch_group = virtual_group(project, 'WhimWatch')
watch_source = file_reference(
  watch_group,
  '../src/watch/app-composition/WhimWatchApp.swift'
)
watch_test_source = file_reference(
  watch_group,
  '../src/watch/app-composition/WhimWatchApp.test.swift'
)
watch_ui_test_source = file_reference(
  watch_group,
  '../e2e/watch/WhimWatch.e2e.test.swift'
)

watch_target = project.targets.find { |target| target.name == 'WhimWatch' }
watch_target ||= project.new_target(:application, 'WhimWatch', :watchos, '11.0')
watch_target.product_type = Xcodeproj::Constants::PRODUCT_TYPE_UTI[:application]
watch_target.add_file_references([watch_source]) unless watch_target.source_build_phase.files_references.include?(watch_source)
configure_target(watch_target, 'app.whim.ios.watchkitapp', '11.0')
watch_target.build_configurations.each do |configuration|
  settings = configuration.build_settings
  settings['INFOPLIST_KEY_CFBundleDisplayName'] = 'Whim'
  settings['INFOPLIST_KEY_WKCompanionAppBundleIdentifier'] = 'app.whim.ios'
  settings['SDKROOT'] = 'watchos'
  settings['SKIP_INSTALL'] = 'YES'
  settings['TARGETED_DEVICE_FAMILY'] = '4'
end

package_reference = project.root_object.package_references.find do |reference|
  reference.respond_to?(:relative_path) && reference.relative_path == '../packages/WhimCore'
end
unless package_reference
  package_reference = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
  package_reference.relative_path = '../packages/WhimCore'
  project.root_object.package_references << package_reference
end

package_product = watch_target.package_product_dependencies.find do |dependency|
  dependency.product_name == 'WhimCore'
end
unless package_product
  package_product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  package_product.package = package_reference
  package_product.product_name = 'WhimCore'
  watch_target.package_product_dependencies << package_product

  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = package_product
  watch_target.frameworks_build_phase.files << build_file
end

app_target.add_dependency(watch_target) unless app_target.dependencies.any? { |dependency| dependency.target == watch_target }
embed_phase = app_target.copy_files_build_phases.find { |phase| phase.name == 'Embed Watch Content' }
embed_phase ||= app_target.new_copy_files_build_phase('Embed Watch Content')
embed_phase.dst_subfolder_spec = '16'
embed_phase.dst_path = '$(CONTENTS_FOLDER_PATH)/Watch'
unless embed_phase.files_references.include?(watch_target.product_reference)
  embed_phase.add_file_reference(watch_target.product_reference)
end

watch_tests = project.targets.find { |target| target.name == 'WhimWatchTests' }
watch_tests ||= project.new_target(:unit_test_bundle, 'WhimWatchTests', :watchos, '11.0')
watch_tests.add_file_references([watch_test_source]) unless watch_tests.source_build_phase.files_references.include?(watch_test_source)
watch_tests.add_dependency(watch_target) unless watch_tests.dependencies.any? { |dependency| dependency.target == watch_target }
configure_target(watch_tests, 'app.whim.ios.watchkitapp.tests', '11.0')
watch_tests.build_configurations.each do |configuration|
  settings = configuration.build_settings
  settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
  settings['SDKROOT'] = 'watchos'
  settings['TARGETED_DEVICE_FAMILY'] = '4'
  settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/WhimWatch.app/WhimWatch'
  settings['TEST_TARGET_NAME'] = 'WhimWatch'
end

watch_ui_tests = project.targets.find { |target| target.name == 'WhimWatchUITests' }
watch_ui_tests ||= project.new_target(:ui_test_bundle, 'WhimWatchUITests', :watchos, '11.0')
unless watch_ui_tests.source_build_phase.files_references.include?(watch_ui_test_source)
  watch_ui_tests.add_file_references([watch_ui_test_source])
end
unless watch_ui_tests.dependencies.any? { |dependency| dependency.target == watch_target }
  watch_ui_tests.add_dependency(watch_target)
end
configure_target(watch_ui_tests, 'app.whim.ios.watchkitapp.uitests', '11.0')
watch_ui_tests.build_configurations.each do |configuration|
  settings = configuration.build_settings
  settings['SDKROOT'] = 'watchos'
  settings['TARGETED_DEVICE_FAMILY'] = '4'
  settings['TEST_TARGET_NAME'] = 'WhimWatch'
end

bridge_group = virtual_group(project, 'WhimBridgeIntegrationTests')
bridge_source = file_reference(
  bridge_group,
  '../packages/expo-whim/ios/app-composition/ExpoWhimModule.integration.test.swift'
)
bridge_tests = project.targets.find { |target| target.name == 'WhimBridgeIntegrationTests' }
bridge_tests ||= project.new_target(:unit_test_bundle, 'WhimBridgeIntegrationTests', :ios, '18.0')
bridge_tests.add_file_references([bridge_source]) unless bridge_tests.source_build_phase.files_references.include?(bridge_source)
bridge_tests.add_dependency(app_target) unless bridge_tests.dependencies.any? { |dependency| dependency.target == app_target }
configure_target(bridge_tests, 'app.whim.ios.bridge-integration-tests', '18.0')
bridge_tests.build_configurations.each do |configuration|
  settings = configuration.build_settings
  settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
  settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/whim.app/whim'
  settings['TEST_TARGET_NAME'] = 'whim'
end

project.save

def save_scheme(project_path, name, launch_target, test_targets)
  scheme = Xcodeproj::XCScheme.new
  scheme.add_build_target(launch_target)
  scheme.set_launch_target(launch_target)
  test_targets.each { |target| scheme.add_test_target(target) }
  scheme.save_as(project_path, name, true)

  schemes_directory = File.join(project_path, 'xcshareddata', 'xcschemes')
  expected_path = File.join(schemes_directory, "#{name}.xcscheme")
  actual_path = Dir.glob(File.join(schemes_directory, '*.xcscheme')).find do |candidate|
    File.basename(candidate).casecmp?(File.basename(expected_path))
  end
  if actual_path && actual_path != expected_path
    temporary_path = "#{actual_path}.case-normalization"
    File.rename(actual_path, temporary_path)
    File.rename(temporary_path, expected_path)
  end
end

save_scheme(project_path, 'Whim', app_target, [bridge_tests])
save_scheme(project_path, 'WhimWatch', watch_target, [watch_tests, watch_ui_tests])
save_scheme(project_path, 'WhimWatchUITests', watch_target, [watch_ui_tests])
