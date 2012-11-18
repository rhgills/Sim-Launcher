require_relative '../lib/sim_launcher'

# this is why you need to learn rspec.
# pisspoor replacement by just verifing that each method does what it says on the tin. 
# LEARN RSPEC NOW!

sim = SimLauncher::Simulator.new

app_path = "/Users/robert/Documents/the-queue-stable/Frank/frankified_build/Frankified.app"
app_dir_path = "/Users/robert/Documents/the-queue-stable/Frank"
applications_root = File.expand_path("~/Library/Application Support/iPhone Simulator/6.0/Applications")
puts sim.info_plist_path_for_app_bundle(app_path)

puts sim.bundle_identifier_for_app_bundle(app_path)



 puts sim.installed_app_directory_path('6.0', app_path)
 
 puts defaults = sim.path_to_defaults('6.0', app_path)


 # sim.clear_defaults(defaults
 sim.write_defaults(defaults, {"somekey" => "somevalue"})
 