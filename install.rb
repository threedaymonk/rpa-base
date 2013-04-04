
# This file mainly stolen from rdoc's sources and modified afterwards.

require 'rbconfig'
require 'find'
require 'ftools'

include Config

$stdout.sync = true
$ruby = CONFIG['ruby_install_name']

##
# Install a binary file. We patch in on the way through to
# insert a #! line. If this is a Unix install, we name
# the command (for example) 'rdoc' and let the shebang line
# handle running it. Under windows, we add a '.rb' extension
# and let file associations to their stuff
#

def installBIN(from, opfile)

  tmp_dir = nil
  for t in [".", "/tmp", "c:/temp", $bindir]
    stat = File.stat(t) rescue next
    if stat.directory? and stat.writable?
      tmp_dir = t
      break
    end
  end

  fail "Cannot find a temporary directory" unless tmp_dir
  tmp_file = File.join(tmp_dir, "_tmp")
    
    
  File.open(from) do |ip|
    File.open(tmp_file, "w") do |op|
      ruby = File.join(CONFIG["bindir"], $ruby)
      op.puts "#!#{ruby}"
      op.write ip.read
    end
  end

  if CONFIG["target_os"] =~ /dos|win32/i
      target = File.join($bindir, opfile)
      File.open(target + ".bat", "w") do |f|
          ruby = File.join($bindir, $ruby).gsub(/\//,"\\")
          wtarget = target.gsub(/\//,"\\")
          f.puts "@#{ruby} #{wtarget} %1 %2 %3 %4 %5 %6 %7 %8 %9"
      end
  end
  File::install(tmp_file, File.join($bindir, opfile), 0755, true)
  File::unlink(tmp_file)
end



$sitedir = CONFIG["sitelibdir"]
unless $sitedir
  version = CONFIG["MAJOR"]+"."+CONFIG["MINOR"]
  $libdir = File.join(CONFIG["libdir"], "ruby", version)
  $sitedir = $:.find {|x| x =~ /site_ruby/}
  if !$sitedir
    $sitedir = File.join($libdir, "site_ruby")
  elsif $sitedir !~ Regexp.quote(version)
    $sitedir = File.join($sitedir, version)
  end
end

$bindir =  CONFIG["bindir"]

puts "Where should the executables be installed?"
puts "(will be left as \"#{$bindir}\" if you just press enter): "
val = gets.chomp
unless /\A\s*\z/.match val
    $bindir = val
end

rpa_dest = File.join($sitedir, "rpa")

File::makedirs(rpa_dest,
               true)

File::chmod(0755, rpa_dest)

# The library files
files = %w{
 rpa/*.rb
 rpa.rb
}.collect {|f| Dir.glob(f)}.flatten

for aFile in files
  File::install(aFile, File.join($sitedir, aFile), 0644, true)
end

# now adjust rpa/defaults.rb
require 'rpa/defaults'
puts <<EOF
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
    val = gets.chomp
    val = defs[i] if /\A\s*\z/.match val
    defaults[keys[i]] = val
end
puts "Storing defaults..."
File.open(File.join($sitedir, "rpa/defaults.rb"), "w") do |f|
    f.puts <<EOF

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
end

# and the executable
bin_files = %w{
 bin/*.rb
 bin/rpa
 bin/rpaadmin
}.collect {|f| Dir.glob(f)}.flatten 
bin_files.each { |f| installBIN(f, f.gsub(/\Abin\//, "")) }

