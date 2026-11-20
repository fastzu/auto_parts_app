require 'xcodeproj'

project_path = File.join(__dir__, 'Runner.xcodeproj')
project = Xcodeproj::Project.open(project_path)

runner_target = project.targets.find { |t| t.name == 'Runner' }
raise 'Runner target not found!' unless runner_target

# 1) إضافة NSSupportsLiveActivities إلى Runner/Info.plist
runner_plist_path = File.join(__dir__, 'Runner', 'Info.plist')
runner_plist = Xcodeproj::Plist.read_from_path(runner_plist_path)
runner_plist['NSSupportsLiveActivities'] = true
Xcodeproj::Plist.write_to_path(runner_plist, runner_plist_path)

# 2) ضبط Podfile ليدعم iOS 16.2 المطلوب لـ Live Activities
podfile_path = File.join(__dir__, 'Podfile')
if File.exist?(podfile_path)
  podfile = File.read(podfile_path)
  if podfile.include?("platform :ios")
    podfile.gsub!(/#?\s*platform :ios,\s*'[0-9.]+'/, "platform :ios, '16.2'")
  else
    podfile = "platform :ios, '16.2'\n" + podfile
  end
  File.write(podfile_path, podfile)
end

# 3) ربط Runner.entitlements بـ Runner
runner_bundle_id = 'com.autoparts.app'
runner_target.build_configurations.each do |cfg|
  bid = cfg.build_settings['PRODUCT_BUNDLE_IDENTIFIER']
  runner_bundle_id = bid if bid && !bid.empty? && !bid.include?('$(')
  cfg.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
end

ext_name = 'AutoPartsLiveActivity'
existing_ext = project.targets.find { |t| t.name == ext_name }

if existing_ext.nil?
  ext_target = project.new_target(:app_extension, ext_name, :ios, '16.2')

  ext_group = project.main_group.find_subpath(ext_name, true)
  ext_group.set_source_tree('<group>')
  ext_group.set_path(ext_name)

  swift_ref = ext_group.new_file('AutoPartsLiveActivity.swift')
  ext_group.new_file('Info.plist')
  ext_group.new_file('AutoPartsLiveActivity.entitlements')

  ext_target.add_file_references([swift_ref])

  ext_target.build_configurations.each do |cfg|
    cfg.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = "#{runner_bundle_id}.#{ext_name}"
    cfg.build_settings['INFOPLIST_FILE'] = "#{ext_name}/Info.plist"
    cfg.build_settings['CODE_SIGN_ENTITLEMENTS'] = "#{ext_name}/#{ext_name}.entitlements"
    cfg.build_settings['SWIFT_VERSION'] = '5.0'
    cfg.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.2'
    cfg.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
    cfg.build_settings['SKIP_INSTALL'] = 'YES'
    cfg.build_settings['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
    cfg.build_settings['GENERATE_INFOPLIST_FILE'] = 'NO'
    cfg.build_settings['MARKETING_VERSION'] = '$(FLUTTER_BUILD_NAME)'
    cfg.build_settings['CURRENT_PROJECT_VERSION'] = '$(FLUTTER_BUILD_NUMBER)'
  end

  runner_target.add_dependency(ext_target)

  embed_phase = runner_target.new_copy_files_build_phase('Embed App Extensions')
  embed_phase.symbol_dst_subfolder_spec = :plug_ins
  build_file = embed_phase.add_file_reference(ext_target.product_reference)
  build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

  # نقل مرحلة التضمين قبل Thin Binary لتفادي خطأ Cycle inside Runner
  thin_idx = runner_target.build_phases.index { |p| p.respond_to?(:name) && p.name == 'Thin Binary' }
  if thin_idx
    runner_target.build_phases.delete(embed_phase)
    runner_target.build_phases.insert(thin_idx, embed_phase)
  end
end

project.save
puts "Successfully configured AutoPartsLiveActivity Widget Extension!"