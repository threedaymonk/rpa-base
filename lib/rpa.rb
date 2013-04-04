#
# Copyright (C) 2004 Mauricio Julio Fernández Pradier
# See LICENSE.txt for additional licensing information.
#

require 'rpa/defaults.rb'

module RPA
    @path = File.join(RPA::Defaults::PREFIX, RPA::Defaults::SITELIBDIR)
    $:.unshift @path
    @path2 = File.join(RPA::Defaults::PREFIX, RPA::Defaults::SO_DIR)
    $:.unshift @path2
    @forcepath = false
    @version = RPA::VERSION

    def self.version=(version)
        return if @version == version
        if @version && @forcepath
            raise "Warning, trying to use RPA version #{version} but " + 
                "#{@version} was in use."
        end
        npath = @path.gsub(/#{Regexp.escape(RPA::VERSION)}/, version)
        npath2 = @path2.gsub(/#{Regexp.escape(RPA::VERSION)}/, version)
        if !File.directory?(npath)
            raise "Couldn't find RPA directory for version #{version}." 
        end
        @forcepath = true
        @version = version
        @path = npath
        @path2 = npath2
        $:.delete @path
        $:.delete @path2
        $:.unshift @path
        $:.unshift @path2
    end
end

if __FILE__ == $0
    puts <<EOF
You are running the wrong file. If you're using win32, please cd to another
directory in order to run the real rpa.bat.
EOF
end
