
# Note that this install.rb is ugly because quite a lot of code is
# needed to bootstrap rpa-base. rpafied install.rb scripts are MUCH shorter
# and cleaner normally.

$:.delete "."

$get_defaults = false
$rpa_defaults_text = nil
begin
require 'rpa/defaults'
require 'rpa/install'
puts "Defaults loaded..."
rescue LoadError
    puts <<EOF
No previous version of rpa-base detected. rpa-base will bootstrap and
you will be allowed to set the default paths for the RPA installation.

EOF
    puts "=" * 80
    puts
    $rpa_base_get_defaults = true
    $:.unshift "./lib"
    # now adjust rpa/defaults.rb
    require 'rpa/defaults.rb'
    puts <<-EOF
    You can now modify the default paths used by RPA.
    EOF
    labels = ["Prefix", "RPA base directory", "Module directory", 
            "Extension directory"]
    keys = %w[prefix rpa-base sitelibdir so-dir]
    defs = [RPA::Defaults::PREFIX, RPA::Defaults::RPA_BASE,
            RPA::Defaults::SITELIBDIR, RPA::Defaults::SO_DIR]
    defaults = {}
    labels.each_with_index do |label, i|
        puts "#{label} (will be left as \"#{defs[i]}\" if you just press enter): "
        val = $stdin.gets.chomp
        val = defs[i] if /\A\s*\z/.match val
        defaults[keys[i]] = val
    end
    puts "Storing defaults..."
    $rpa_defaults_text = <<EOF
module RPA
    RPABASE_VERSION = #{RPA::RPABASE_VERSION.inspect}
    VERSION = #{RPA::VERSION.inspect}
    module Defaults
        PREFIX = #{defaults["prefix"].inspect}
        RPA_BASE = #{defaults["rpa-base"].inspect}
        SITELIBDIR = #{defaults["sitelibdir"].inspect}
        SO_DIR = #{defaults["so-dir"].inspect}
    end
end
EOF
    puts "Reloading defaults..."
    defs = %w[PREFIX RPA_BASE SITELIBDIR SO_DIR]
    defs.each{|x| RPA::Defaults.send(:remove_const, x)}
    RPA.send(:remove_const, "VERSION")
    RPA.send(:remove_const, "RPABASE_VERSION")
    $verbose = nil
    eval $rpa_defaults_text
    $verbose = false
    puts "=" * 80
    puts
else # $rpa_base_get_defaults
    puts "Recovering defaults..."
    $rpa_defaults_text = <<EOF
module RPA
    RPABASE_VERSION = "0.2.0"
    VERSION = "0.0"
    module Defaults
        PREFIX = #{RPA::Defaults::PREFIX.inspect}
        RPA_BASE = #{RPA::Defaults::RPA_BASE.inspect}
        SITELIBDIR = #{RPA::Defaults::SITELIBDIR.inspect}
        SO_DIR = #{RPA::Defaults::SO_DIR.inspect}
    end
end
EOF
end

require 'rpa/install'
require 'rbconfig'
class Install_rpa_base < RPA::Install::Application
    name "rpa-base"
    version "0.2.0-21"
    classification Application.Admin
    build do
        skip_default Installrdoc
        installdocs %w[README.txt LICENSE.txt THANKS TODO manifesto.txt
            user_stories.txt]
        task do 
            fname = File.join("rpa/tmp", @config["sitelibdir"], "rpa/defaults.rb")
            sitelibdir = ::Config::CONFIG["sitelibdir"]
            sitelibdir.gsub!(/^#{Regexp.escape @config["prefix"]}/, "")
            fname2 = File.join("rpa/tmp", sitelibdir, "rpa/defaults.rb")
            [fname, fname2].each{|nam| File.open(nam, "w"){|f| f.puts $rpa_defaults_text }}
        end
    end
    install { skip_default RunUnitTests }
    description <<EOF
A port/package manager for the Ruby Production Archive (RPA)
    
rpa-base is a port/package manager created to be the base for RPA's
client-side package management. You can think of it as RPA's apt-get +
dpkg. It features:
* modular, extensible design with 2-phase install
* strong dependency management
* atomic (de)installs: the system is design to prevent unclean states in case 
  of crashes or power outages during operation
* parallel installs/builds
* handling C extensions
* API safety
* rdoc and ri integration
* automatic running of unit tests on install
EOF
end

