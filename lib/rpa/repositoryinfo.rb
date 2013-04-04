#
# Copyright (C) 2004 Mauricio Julio Fernández Pradier
# See LICENSE.txt for additional licensing information.
#

module RPA

require 'rpa/util'
require 'rpa/transaction'
require 'time'

# Represents the information on available packages.
class RepositoryInfo
    DEFAULT_SRC = ["http://rpa-base.rubyforge.org/ports/ports.info"]
    @@instances = {}
    class << self
        private :new
        # Returns the RepositoryInfo object associated to the given
        # configuration. There can only be one (kind of parameterized
        # singleton).
        #
        def instance(config, logger = nil)
            @@instances[Marshal.dump(config.determinant_values)] ||= 
                new config, logger
        end
    end

    # +config+ is the configuration (esp. path info) for the local
    # installation. 
    def initialize(config, logger = nil)
        @logger = logger
        @sources = DEFAULT_SRC
        @config = config
        @fileops = FileOperations.new logger
        @cachefile = File.join(@config["prefix"], @config["rpa-base"],
                               "available")
        unless File.dir?(File.dirname(@cachefile))
            @fileops.mkdir_p(File.dirname(@cachefile), :mode => 0755)
        end
        cachedinfo = YAML.load(File.read_b(@cachefile)) rescue nil
        cachedinfo ||= []
        @ports = cachedinfo.map{|x| Port.new(x["metadata"], x["url"], @config) }
    end

    # Add a source of port information. 
    def add_source(url)
        @sources << url
    end

    require 'rpa/open-uri'
    # Get port info from the registered sources.
    # The information is cached between different runs of the RPA tools.
    def update(notify_since = Time.new - 3600*24*20)
        localinst = LocalInstallation.instance @config
        localinst.acquire_lock
        verbose = @config["verbose"]

        newinfo = []
        @sources.each do |src|
            puts "Getting port info from #{src}." if verbose >= 2
            begin
                RPA.fetch_file(@config, src) do |is|
                     newinfo = newinfo + (YAML.load(is.read) || [])
                end
                # FIXME: what about repeated ports, etc?
            rescue Exception => e
                puts "Couldn't retrieve port info from #{src}." if verbose >= 2
                raise
            end
        end
        newinfo = newinfo.sort_by{|port| port["metadata"]["name"] }
        @ports = newinfo.map{|x| Port.new(x["metadata"], x["url"], @config) }
        oldports = File.open(@cachefile){|f| YAML.load(f)} || [] rescue []
        Transaction.atomic_write(@cachefile, newinfo.to_yaml)
        return changes_since(oldports, newinfo, notify_since)
    ensure
        localinst.release_lock unless localinst.nil?
    end

    # Returns an array of Port objects corresponding to the available ports.
    def ports
        @ports
    end

    private
    def changes_since(old_info, new_info, since_when)
        old_info = Hash[*old_info.map{|x| [x["metadata"]["name"], x["metadata"]]}.flatten]
        new_info = Hash[*new_info.map{|x| [x["metadata"]["name"], x["metadata"]]}.flatten]
        newports = (new_info.keys - old_info.keys).sort
        added_ports = []
        modified_ports = []
        newports.each do |pname|
            if new_info[pname]["date"] && Time.rfc2822(new_info[pname]["date"]) > since_when 
                added_ports << new_info[pname]
            end
        end
        commonports = (new_info.keys - newports).sort
        commonports.each do |pname|
            next unless new_info[pname]["version"] != old_info[pname]["version"]
            if new_info[pname]["date"] && Time.rfc2822(new_info[pname]["date"]) > since_when 
                modified_ports << [old_info[pname], new_info[pname]]
            end
        end
        return added_ports, modified_ports
    end
end

end # namespace RPA
