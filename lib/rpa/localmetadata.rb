#
# Copyright (C) 2004 Mauricio Julio Fernández Pradier
# See LICENSE.txt for additional licensing information.
#

require 'rpa/base'
require 'rpa/transaction'

module RPA

class LocalMetadata
    def initialize(dir, logger = nil)
        @dir = dir
        @fileops = fileoperations_class.new logger
    end

    # Registers the given metadata (associated to the package
    # <tt>metadata["name"]</tt>).
    def register_metadata(metadata)
        infodir = File.join(@dir, "info")
        unless File.dir? infodir
            @fileops.mkdir_p(infodir, :mode => 0755)
        end
        file_class.open(File.join(infodir, metadata["name"]), "wb") do |f|
            f.write metadata.to_yaml
        end
        instfile = File.join(@dir, "installed")
        installed = YAML.load(file_class.read(instfile)) rescue []
        installed ||= []
        installed << metadata["name"]
        installed = installed.uniq
        Transaction::atomic_write(instfile, installed.to_yaml)
    end

    # Retrieves the metadata corresponding to +pkgname+.
    def retrieve_metadata(pkgname)
        infofile = File.join(@dir, "info", pkgname)
        instfile = File.join(@dir, "installed")
        installed = YAML.load(file_class.read(instfile)) rescue []
        installed ||= []
        if installed.include? pkgname
            YAML.load(file_class.read(infofile)) || nil
        else
            nil
        end
    end

    # Removes the metadata corresponding to +pkgname+.
    def remove_metadata(pkgname)
        instfile = File.join(@dir, "installed")
        installed = YAML.load(file_class.read(instfile)) rescue []
        installed ||= []
        installed.delete pkgname
        Transaction::atomic_write(instfile, installed.to_yaml)
        infofile = File.join(@dir, "info", pkgname)
        @fileops.rm_f(infofile) rescue nil
    end

    def installed_ports
        instfile = File.join(@dir, "installed")
        YAML.load(file_class.read(instfile)) || []
    rescue
        []
    end

    def installed_files
        #TODO: cache
        infodir = File.join(@dir, "info")
        instfile = File.join(@dir, "installed")
        installed = YAML.load(file_class.read(instfile)) rescue []
        installed ||= []
        files = {}
        installed.map{|x| File.join(infodir, x)}.each do |fname|
            pkgfiles = YAML.load(file_class.read(fname))
            pkgfiles["files"].each {|f| files[f] = pkgfiles["name"]}
        end
        files
    end
    
    private

    def fileoperations_class
        FileOperations
    end
    
    def file_class
        File
    end

    def dir_class
        Dir
    end

end
end

