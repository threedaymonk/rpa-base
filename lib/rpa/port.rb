#
# Copyright (C) 2004 Mauricio Julio Fernández Pradier
# See LICENSE.txt for additional licensing information.
#

module RPA

# Represents a port.
class Port
    require 'rbconfig'
    BROKEN_WINDOWS = ::Config::CONFIG["arch"] =~ /msdos|win32/i
    
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
            src = @url.gsub(%r{\Afile://}, "")
            len = 0
            display_progress = lambda do |rec|
                done = 40 * rec / len
                bar = "" + "=" * done + " " * (40 - done)
                txt = "%03d%% [%s] #{len} bytes\r" % [100 * rec / len, bar]
                print txt
            end
            if verbose >= 2
                open(src, :content_length_proc => lambda{|len| }, 
                     :progress_proc => display_progress) do |is|
                         f.write(is.read(4096)) until is.eof?
                     end
                puts
            else
                open(src) { |is| f.write(is.read(4096)) until is.eof? }
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
