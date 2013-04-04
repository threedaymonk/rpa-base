#!/usr/bin/ruby

require 'rpa/base'
require 'rpa/util'
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
        next unless File.dir? portdir
        puts "Loading #{portdir}/install.rb"
        Dir.chdir(portdir) { load "install.rb" }
        meta = RPA::Install.children.last.metadata
        dest = %w[name version].map{|x| meta[x]}.join "_"
        url = baseurl + (baseurl[-1] == '/' ? "": '/') + dest + ".rps"
        meta.delete "platform" # don't want it for now
        portinfo << {"metadata" => meta, "url" => url }       
        puts "Creating #{dest}.rps"
        RPA::Package.pack(portdir, "#{dest}.rps")
    end
end

portinfo = portinfo.sort_by{|x| x["metadata"]["name"]}

File.open(destfile, "w") {|f| f.write portinfo.to_yaml}
