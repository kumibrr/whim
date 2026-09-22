#!/usr/bin/env ruby

require 'xcodeproj'

project_path = File.expand_path('../ios/whim.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)
app_target = project.targets.find { |target| target.name == 'whim' }
abort 'Expected iPhone target named whim' unless app_target

app_group = project.main_group.groups.find { |group| group.display_name == 'whim' }
abort 'Expected iPhone source group named whim' unless app_group

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
    settings['OTHER_SWIFT_FLAGS'] = settings['OTHER_SWIFT_FLAGS'].to_s.gsub(/\s*-D\s+EXPO_CONFIGURATION_(DEBUG|RELEASE)\b/, '').strip
    settings.delete('OTHER_SWIFT_FLAGS') if ['', '$(inherited)'].include?(settings['OTHER_SWIFT_FLAGS'])
    settings['CODE_SIGN_STYLE'] = 'Automatic'
    settings['CURRENT_PROJECT_VERSION'] = '1'
    settings['MARKETING_VERSION'] = '1.0.0'
    settings['GENERATE_INFOPLIST_FILE'] = 'YES'
    settings['PRODUCT_BUNDLE_IDENTIFIER'] = bundle_identifier
    settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
    settings['SWIFT_VERSION'] = '6.0'
    settings['WATCHOS_DEPLOYMENT_TARGET'] = deployment_target if target.platform_name == :watchos
    settings['IPHONEOS_DEPLOYMENT_TARGET'] = deployment_target if target.platform_name == :ios
  end
end

watch_group = virtual_group(project, 'WhimWatch')
repository_root = File.expand_path('..', __dir__)
watch_paths = Dir.glob(File.join(repository_root, 'src/watch/**/*.swift'))
test_source = ->(path) { path.include?('.test.') || path.include?('.test-support.') }
references = ->(paths) { paths.map { |path| file_reference(watch_group, "../" + path.delete_prefix(repository_root + '/')) } }
watch_sources = references.call(watch_paths.reject(&test_source))
watch_test_sources = references.call(watch_paths.select(&test_source))
watch_ui_test_sources = references.call(Dir.glob(File.join(repository_root, 'e2e/{watch,cross-device}/*.swift')))
# Remove references to the retired scaffold test, including its navigator entry.
watch_group.files.select { |file| file.path == '../src/watch/app-composition/WhimWatchApp.test.swift' }.each(&:remove_from_project)

watch_target = project.targets.find { |target| target.name == 'WhimWatch' }
watch_target ||= project.new_target(:application, 'WhimWatch', :watchos, '11.0')
watch_target.product_type = Xcodeproj::Constants::PRODUCT_TYPE_UTI[:application]
watch_target.source_build_phase.files.each { |entry| entry.remove_from_project if entry.file_ref && test_source.call(entry.file_ref.path) }
watch_sources.each { |source| watch_target.add_file_references([source]) unless watch_target.source_build_phase.files_references.include?(source) }
configure_target(watch_target, 'app.whim.ios.watchkitapp', '11.0')
watch_target.build_configurations.each do |configuration|
  settings = configuration.build_settings
  settings['INFOPLIST_KEY_CFBundleDisplayName'] = 'Whim'
  settings['INFOPLIST_KEY_WKCompanionAppBundleIdentifier'] = 'app.whim.ios'
  settings['INFOPLIST_KEY_NSMicrophoneUsageDescription'] = 'Whim records voice Notes on your Apple Watch.'
  settings.delete('INFOPLIST_KEY_UIBackgroundModes')
  settings['INFOPLIST_FILE'] = 'WhimWatch-Info.plist'
  settings['CODE_SIGN_ENTITLEMENTS'] = 'WhimWatch.entitlements'
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
watch_tests.source_build_phase.files.each { |entry| entry.remove_from_project unless watch_test_sources.include?(entry.file_ref) }
watch_test_sources.each { |source| watch_tests.add_file_references([source]) unless watch_tests.source_build_phase.files_references.include?(source) }
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
watch_ui_test_sources.each { |source| watch_ui_tests.add_file_references([source]) unless watch_ui_tests.source_build_phase.files_references.include?(source) }
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

# Both Apple apps consume the same native package; the iPhone also links presentation models.
app_target.shell_script_build_phases.each(&:remove_from_project)

iphone_group = virtual_group(project, 'WhimIPhone')
model_manifest = File.read(File.join(repository_root, 'Package.swift'))
model_sources = model_manifest.match(/let modelSources = \[(.*?)\]/m)[1].scan(/"([^"]+)"/).flatten
iphone_views = Dir.glob(File.join(repository_root, 'src/iphone/**/*.swift')).reject do |path|
  relative = path.delete_prefix(File.join(repository_root, 'src/iphone/'))
  test_source.call(path) || model_sources.include?(relative)
end
view_references = iphone_views.map { |path| file_reference(iphone_group, '../' + path.delete_prefix(repository_root + '/')) }
app_target.source_build_phase.files.each { |entry| entry.remove_from_project unless view_references.include?(entry.file_ref) }
view_references.each { |reference| app_target.add_file_references([reference]) unless app_target.source_build_phase.files_references.include?(reference) }

presentation_reference = project.root_object.package_references.find { |reference| reference.respond_to?(:relative_path) && reference.relative_path == '..' }
unless presentation_reference
  presentation_reference = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
  presentation_reference.relative_path = '..'
  project.root_object.package_references << presentation_reference
end
[[package_reference, 'WhimCore'], [presentation_reference, 'WhimIPhone']].each do |reference, name|
  next if app_target.package_product_dependencies.any? { |dependency| dependency.product_name == name }
  product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  product.package = reference; product.product_name = name
  app_target.package_product_dependencies << product
  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = product
  app_target.frameworks_build_phase.files << build_file
end
configure_target(app_target, 'app.whim.ios', '18.0')
app_target.build_configurations.each do |configuration|
  configuration.base_configuration_reference = nil
  settings = configuration.build_settings
  %w[SWIFT_OBJC_BRIDGING_HEADER OTHER_LDFLAGS OTHER_CFLAGS OTHER_SWIFT_FLAGS HEADER_SEARCH_PATHS LIBRARY_SEARCH_PATHS FRAMEWORK_SEARCH_PATHS].each { |key| settings.delete(key) }
  settings['SWIFT_VERSION'] = '6.0'
  settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'Whim'
  settings['INFOPLIST_FILE'] = 'whim/Info.plist'
  settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  settings['CODE_SIGN_ENTITLEMENTS'] = 'whim/whim.entitlements'
  settings['TARGETED_DEVICE_FAMILY'] = '1'
end

# System entry points share source definitions with the hosting application.
intent_group = virtual_group(project, 'WhimIntents')
intent_refs = Dir.glob(File.join(repository_root, 'src/intents/**/*.swift')).reject(&test_source).map { |path| file_reference(intent_group, '../' + path.delete_prefix(repository_root + '/')) }
[app_target, watch_target].each do |host|
  intent_refs.each { |ref| host.add_file_references([ref]) unless host.source_build_phase.files_references.include?(ref) }
end
widget_group = virtual_group(project, 'WhimWidgets')
[[:ios, 'WhimLiveActivity', app_target, '18.0', 'app.whim.ios.activity', 'whim/whim.entitlements'],
 [:watchos, 'WhimComplication', watch_target, '11.0', 'app.whim.ios.watchkitapp.complication', 'WhimWatch.entitlements']].each do |platform, name, host, version, identifier, entitlements|
  target = project.targets.find { |candidate| candidate.name == name } || project.new_target(:app_extension, name, platform, version)
  configure_target(target, identifier, version)
  paths = Dir.glob(File.join(repository_root, 'src/widgets/app-composition/*.swift'))
  paths += Dir.glob(File.join(repository_root, platform == :ios ? 'src/widgets/{recording-activity,recording-control}/*.swift' : 'src/widgets/recording-complication/*.swift'))
  refs = paths.reject(&test_source).map { |path| file_reference(widget_group, '../' + path.delete_prefix(repository_root + '/')) }
  refs += intent_refs.reject { |ref| ref.path.end_with?('/WhimShortcutsProvider.swift') } if platform == :ios
  target.source_build_phase.files.each { |entry| entry.remove_from_project unless refs.include?(entry.file_ref) }
  refs.each { |ref| target.add_file_references([ref]) unless target.source_build_phase.files_references.include?(ref) }
  unless target.package_product_dependencies.any? { |dependency| dependency.product_name == 'WhimCore' }
    product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
    product.package = package_reference; product.product_name = 'WhimCore'
    target.package_product_dependencies << product
    build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
    build_file.product_ref = product; target.frameworks_build_phase.files << build_file
  end
  target.build_configurations.each do |configuration|
    settings = configuration.build_settings
    settings['INFOPLIST_FILE'] = "#{name}-Info.plist"
    settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = '$(inherited) WHIM_WIDGET_EXTENSION'
    settings['CURRENT_PROJECT_VERSION'] = '1'
    settings['MARKETING_VERSION'] = '1.0.0'
    settings['CODE_SIGN_ENTITLEMENTS'] = entitlements
    settings['SKIP_INSTALL'] = 'YES'
    settings['TARGETED_DEVICE_FAMILY'] = platform == :ios ? '1' : '4'
    settings['SDKROOT'] = platform == :ios ? 'iphoneos' : 'watchos'
    settings['SUPPORTED_PLATFORMS'] = platform == :ios ? 'iphoneos iphonesimulator' : 'watchos watchsimulator'
  end
  host.add_dependency(target) unless host.dependencies.any? { |dependency| dependency.target == target }
  phase = host.copy_files_build_phases.find { |candidate| candidate.name == 'Embed App Extensions' } || host.new_copy_files_build_phase('Embed App Extensions')
  phase.dst_subfolder_spec = '13'
  phase.add_file_reference(target.product_reference) unless phase.files_references.include?(target.product_reference)
end

# Tests compile the same system-surface source as the extensions, with boundary fixtures.
surface_tests = project.targets.find { |target| target.name == 'WhimSystemSurfaceTests' } || project.new_target(:unit_test_bundle, 'WhimSystemSurfaceTests', :ios, '18.0')
configure_target(surface_tests, 'app.whim.ios.systemsurfacetests', '18.0')
surface_group = virtual_group(project, 'WhimSystemSurfaceTests')
surface_paths = Dir.glob(File.join(repository_root, 'src/intents/**/*.swift')) + Dir.glob(File.join(repository_root, 'src/widgets/{recording-control,recording-activity}/**/*.swift'))
surface_paths << File.join(repository_root, 'src/iphone/app-composition/IPhoneModel.test-support.swift')
surface_refs = surface_paths.map { |path| file_reference(surface_group, '../' + path.delete_prefix(repository_root + '/')) }
surface_tests.source_build_phase.files.each { |entry| entry.remove_from_project unless surface_refs.include?(entry.file_ref) }
surface_refs.each { |ref| surface_tests.add_file_references([ref]) unless surface_tests.source_build_phase.files_references.include?(ref) }
surface_tests.add_dependency(app_target) unless surface_tests.dependencies.any? { |dependency| dependency.target == app_target }
unless surface_tests.package_product_dependencies.any? { |dependency| dependency.product_name == 'WhimCore' }
  product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  product.package = package_reference; product.product_name = 'WhimCore'
  surface_tests.package_product_dependencies << product
  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = product; surface_tests.frameworks_build_phase.files << build_file
end
surface_tests.build_configurations.each do |configuration|
  settings = configuration.build_settings
  settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
  settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/whim.app/whim'
  settings['TEST_TARGET_NAME'] = 'whim'
  settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = '$(inherited) WHIM_SYSTEM_SURFACE_TESTS'
  settings['TARGETED_DEVICE_FAMILY'] = '1'
end

# Every app/extension links WhimCore and shares preferences through its App Group.
privacy_reference = project.files.find { |file| file.path == 'whim/PrivacyInfo.xcprivacy' }
abort 'Expected shared privacy manifest' unless privacy_reference
project.targets.select { |target| %w[whim WhimWatch WhimLiveActivity WhimComplication].include?(target.name) }.each do |target|
  unless target.resources_build_phase.files_references.include?(privacy_reference)
    target.resources_build_phase.add_file_reference(privacy_reference)
  end
end

project.build_configurations.each do |configuration|
  %w[OTHER_CFLAGS OTHER_CPLUSPLUSFLAGS OTHER_SWIFT_FLAGS].each { |key| configuration.build_settings.delete(key) }
end
# Remove unreachable project objects after source membership changes.
reachable = {}
visit = lambda do |value|
  case value
  when Hash then value.each_value { |child| visit.call(child) }
  when Array then value.each { |child| visit.call(child) }
  when String
    object = project.objects_by_uuid[value]
    if object && !reachable[value]
      reachable[value] = true
      visit.call(object.to_hash)
    end
  end
end
visit.call(project.root_object.uuid)
project.objects.reject { |object| reachable[object.uuid] }.each(&:remove_from_project)
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

save_scheme(project_path, 'Whim', app_target, [surface_tests])
save_scheme(project_path, 'WhimWatch', watch_target, [watch_tests, watch_ui_tests])
save_scheme(project_path, 'WhimWatchUITests', watch_target, [watch_ui_tests])
