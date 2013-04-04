#
# Copyright (C) 2004 Mauricio Julio Fernández Pradier
# See LICENSE.txt for additional licensing information.
#

module RPA

# Represents a port.
class Port
    require 'rbconfig'
    BROKEN_WINDOWS = ::Config::CONFIG["arch"] =~ /msdos|win32|mingw/i
    
    attr_reader :metadata, :url
    def initialize(metadata, url, config)
        @url = url
        @metadata = metadata
        @config = config
        @fileops = FileOperations.new
    end

    require 'rpa/open-uri'
    # Download the .rps to the specified directory.
    def download(tmpdir = RPA::TEMP_DIR)
        verbose = @config["verbose"]

        name = @metadata["name"]
        destdir = File.join(tmpdir, name)
        #TODO: download w/o putting it all in mem
        dest = File.join(tmpdir, "#{name}_#{rand(100000)}.rps")
        @fileops.rm_rf(dest) if File.dir? dest
        @fileops.mkdir_p(tmpdir) rescue nil
        #TODO: version comparison (?)
        File.open(dest, "wb") do |f|
            puts "Getting port #{name} from #{@url}." if verbose >= 2
            RPA.fetch_file(@config, @url) do |is|
                f.write(is.read(4096)) until is.eof?
            end
        end
        extract dest, destdir
        @fileops.rm_f(dest)
        destdir
    end

    private
    def extract(pkg, destdir)
        Package.open(pkg) do |port|
            port.each { |entry| port.extract_entry(destdir, entry) }
        end
    end
end

end # namespace RPA
