#
# Copyright (C) 2004 Mauricio Julio Fernández Pradier
# See LICENSE.txt for additional licensing information.
#

module RPA

require 'rpa/util'

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
    def update
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
                p e
                puts "Couldn't retrieve port info from #{src}." if verbose >= 2
            end
        end
        newinfo = newinfo.sort_by{|port| port["metadata"]["name"] }
        @ports = newinfo.map{|x| Port.new(x["metadata"], x["url"], @config) }
        File.open(@cachefile, "wb") { |f| f.write newinfo.to_yaml }
    ensure
        localinst.release_lock unless localinst.nil?
    end

    # Returns an array of Port objects corresponding to the available ports.
    def ports
        @ports
    end
end

end # namespace RPA
