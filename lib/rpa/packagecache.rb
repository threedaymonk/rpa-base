#
# Copyright (C) 2004 Mauricio Julio Fernández Pradier
# See LICENSE.txt for additional licensing information.
#

require 'rpa/base'
require 'rpa/transaction'
require 'rpa/package'

module RPA

class PackageCache
    def initialize(dir, logger = nil)
        @dir = dir
        @fileops = fileoperations_class.new logger
    end

    def has_package?(meta)
        if meta["name"] && meta["version"] && meta["platform"]
            canonical_name = Package.normalized_name meta
            fname = File.join(@dir, canonical_name)
            if File.exist? fname
                return fname
            else
                return nil
            end
        end
        matcher = Package.name_matcher(meta["name"], meta["version"],
                                       meta["platform"])
        Dir["#{@dir}/#{matcher}"].sort.last # the latest version
    end

    alias_method :retrieve_package, :has_package?

    def store_package(file)
        @fileops.mkdir_p @dir unless File.dir? @dir
        meta = nil
        Package.open(file) do |pkg|
            meta = pkg.metadata
        end
        return if has_package? meta
        canonical_name = File.join(@dir, Package.normalized_name(meta))
        File.open(file, "rb") do |is|
            tmpname = "#{canonical_name}.#{Time.now.to_i}.#{rand(1000000)}.tmp"
            File.open(tmpname, "wb") do |out|
                #FIXME: factor out atomic write
                #FIXME: locking?
                out.write is.read(4096) until is.eof?
                out.fsync
            end
            File.rename(tmpname, canonical_name)
            begin
                d = open(File.dirname(canonical_name), "r")
                d.fsync rescue nil
                d.close
            rescue Exception
                # for win32
            end
        end
    end

    def cleanup
        Dir["#{@dir}/*.tmp"].each{|f| @fileops.rm_f f}
        Dir["#{@dir}/*.rpa"].each{|f| @fileops.rm_f f}
    end

    private
    def fileoperations_class
        FileOperations
    end
end

end # RPA
