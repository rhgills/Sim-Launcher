require 'plist'

module SimLauncher
class Simulator

  def initialize( iphonesim_path_external = nil )
    @iphonesim_path = iphonesim_path_external || iphonesim_path(xcode_version)
  end

  def showsdks
    run_synchronous_command( 'showsdks' )
  end

  def info_plist_path_for_app_bundle(app_path)
     File.join(app_path, "Info.plist")
  end
  
  def bundle_identifier_for_app_bundle(app_path)
    info_plist_path = info_plist_path_for_app_bundle(app_path)
    
    # this plist might be binary. convert it if needed and we'll pass directly, preserving the current format.
    xml = `plutil -convert xml1 -o - \"#{info_plist_path}\"` # -o - means output to stdout
    info_plist = Plist::parse_xml(xml)
    bundle_identifier = info_plist['CFBundleIdentifier']
  end


  def installed_app_directory_path(sdk_version, app_path, other_args = {} )  
    # other_args:
    # :launch_app_and_retry_if_not_found
    
    bundle_identifier = bundle_identifier_for_app_bundle(app_path)
    fail "Couldn't find a bundle identifier for the app at #{app_path}. app_path may be wrong or the Info.plist may be missing." unless bundle_identifier
    
    applications_root = File.expand_path("~/Library/Application Support/iPhone Simulator/#{sdk_version}/Applications")
    
    path = nil
    other_app_path = nil
    
    fail "Directory at #{applications_root} doesn't exist." if Dir.exists?(applications_root) == false

    applications = Dir.new(applications_root)
    
    applications.each do |random_id_directory_name|
      
      next if random_id_directory_name == '.' 
      next if random_id_directory_name == '..'
      
      random_id_directory_path = File.join(applications_root, random_id_directory_name)

      next unless File.directory?(random_id_directory_path)
      random_id_directory = Dir.new(random_id_directory_path)
      
      
      
      random_id_directory.find do |file|
        other_app_path = File.join(random_id_directory_path, file) if file =~ /^.*\.app$/
      end
      
      if other_app_path
         other_bundle_identifier = bundle_identifier_for_app_bundle(other_app_path)
         if other_bundle_identifier == bundle_identifier
            path = random_id_directory_path
            break
          end
      end
   end
 
    
    return path if path
    return path if !other_args[:launch_app_and_retry_if_not_found]
    
    # we didn't find the app_directory. It's likely the app hasn't been launched in the simulator yet, so there is none. Launch it and then close it to create the directory, and try again.
    
    # assuming that the launch_ios_app command won't return before the directory is created.
    # TODO: test this
    launch_ios_app(app_path, sdk_version, 'iphone')
    quit_simulator
    
    return installed_app_directory_path(sdk_version, app_path, :launch_app_and_retry_if_not_found => false)
  end

  def path_to_defaults(sdk_version, app_path)
    # TODO: the defaults file won't exist if the application hasn't been started yet. 
    # If thats the case, we need to start the app once, quit it, then we'll find our path.
    
    
    # ~/Library/Application Support/iPhone Simulator/<SDK_VERSION>/Applications/<SOME_RANDOM_ID>/Library/Preferences/<BUNDLE_ID>.plist
    # Because we don't know <SOME_RANDOM_ID>, we have to inspect the Info.plist located at *.app/Info.plist for all <SOME_RANDOM_ID> folder under Applications for the current <SDK_VERSION>.
    # compare this to the Info.plist found at #{app_path}/Info.plist
    
    installed_app = installed_app_directory_path(sdk_version, app_path, :launch_app_and_retry_if_not_found => true)
    bundle_identifier = bundle_identifier_for_app_bundle(app_path)
    fail "Couldn't find installed simulator app for app_path: #{app_path}." unless installed_app
    
    File.join(installed_app, "Library", "Preferences", "#{bundle_identifier}.plist")
  end
  
  def write_defaults(defaults_path, new_defaults)
    # does not overwrite the entire file.
    # pass :clear_defaults to launch_ios_app if you want to clean before setting.
  
  
    defaults = Plist::parse_xml(defaults_path)
    defaults = Hash.new(defaults) # preserve any old values
    
    new_defaults.each do |key, value|
      defaults[key] = value # overwrites values
    end
  
    File.write(defaults_path, defaults.to_plist)
  end
  
  def clear_defaults(defaults_path)
     begin 
       FileUtils.rm(defaults_path)
     rescue Exception
       puts "Failed to delete file at defaults_path: #{$!}"
     end
   end

  def launch_ios_app(app_path, sdk_version, device_family, app_args = nil, other_args = {})
    # other_args:
    # :clear_defaults
    # :set_defaults
    
    if problem = SimLauncher.check_app_path( app_path )
      bangs = '!'*80
      raise "\n#{bangs}\nENCOUNTERED A PROBLEM WITH THE SPECIFIED APP PATH:\n\n#{problem}\n#{bangs}"
    end
    sdk_version ||= SdkDetector.new(self).latest_sdk_version
    args = ["--args"] + app_args.flatten if app_args
    
    if( other_args[:clear_defaults] || other_args[:set_defaults ] ) 
      # we can't just grab path_to_defaults always - if we're called recursively by path_to_defaults because this is the first time the app at app_path is being launched, we'll infinite loop if we call it now.
      defaults = path_to_defaults(sdk_version, app_path)
      
      should_clear_defaults = other_args[:clear_defaults]
      clear_defaults(defaults) if( should_clear_defaults ) 

      new_defaults = other_args[:set_defaults]
      if( new_defaults ) 
        write_defaults(defaults, new_defaults)
      end
    end
    
    run_synchronous_command( :launch, app_path, '--sdk', sdk_version, '--family', device_family, '--exit', *args )
  end

  def launch_ipad_app( app_path, sdk, app_args )
    launch_ios_app( app_path, sdk, 'ipad', app_args )
  end

  def launch_iphone_app( app_path, sdk, app_args )
    launch_ios_app( app_path, sdk, 'iphone', app_args )
  end

  def quit_simulator
    `echo 'application "iPhone Simulator" quit' | osascript`
  end

  def run_synchronous_command( *args )
    cmd = cmd_line_with_args( args )
    puts "executing #{cmd}" if $DEBUG
    `#{cmd}`
  end

  def cmd_line_with_args( args )
    cmd_sections = [@iphonesim_path] + args.map{ |x| "\"#{x.to_s}\"" } << '2>&1'
    cmd_sections.join(' ')
  end
  
  def xcode_version
    version = `xcodebuild -version`
    raise "xcodebuild not found" unless $? == 0
    version[/([0-9]\.[0-9])/, 1].to_f
  end
  
  def iphonesim_path(version)
    installed = `which ios-sim`
    if installed =~ /(.*ios-sim)/
      puts "Using installed ios-sim at #{$1}"
      return $1
    end

    File.join( File.dirname(__FILE__), '..', '..', 'native', 'ios-sim' )
  end
end
end
