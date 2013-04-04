#!/usr/bin/ruby

require 'rpa/base'
require 'rpa/install'
require 'rpa/package'
require 'yaml'

unless ARGV.size == 3
    puts <<EOF
Syntax:
    rpa-buildrepos.rb <info file> <base url> <ports dir>
EOF
    exit
end

destfile = ARGV[0]
baseurl = ARGV[1]
portsdir = ARGV[2]
portinfo = []
RPA::Install.auto_install = false
Dir.chdir(ARGV[2]) do 
    Dir["*"].each do |portdir|
        load File.join(portdir, "install.rb")
        meta = RPA::Install.children.last.metadata
        url = baseurl + (baseurl[-1] == '/' ? "": '/') + portdir + ".rps"
        portinfo << {"metadata" => meta, "url" => url }       
        RPA::Package.pack(portdir, "#{portdir}.rps")
    end
end

portinfo = portinfo.sort_by{|x| x["metadata"]["name"]}

File.open(destfile, "w") {|f| f.write portinfo.to_yaml}
