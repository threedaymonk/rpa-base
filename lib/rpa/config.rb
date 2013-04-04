#
# Copyright (C) 2004 Mauricio Julio Fernández Pradier
# See LICENSE.txt for additional licensing information.
#

require 'optparse'
require 'rpa/defaults'
require 'rpa/base'

module RPA

class Config
    require "rbconfig"
    require 'ostruct'

    DETERMINANT_VALUES = %w[prefix rpa-base sitelibdir so-dir]
    VALUES = [] # the array will be appended to by def_param

    # what we really want is one of those 'ordered hashes' but we don't care
    # about O(n) access for now.
    @parameters = []
    @parameter_lambdas = {}
    class << self
        attr_reader :parameters

        def def_param(name, desc, parameter = nil, 
                      exported_name = "--with-#{name}", parentname = nil, &block)
            RPA::Config::VALUES << name
            param = OpenStruct.new
            param.name = name
            param.desc = desc
            param.param = parameter
            param.exported_name = exported_name
            param.parent = parentname
            @parameter_lambdas[param.name] = lambda do |param_array|
                parent = param_array.find{|x| x.name == parentname }
                value = parent.value if parent
                block.call(value || nil)
            end
            param.value = @parameter_lambdas[param.name][@parameters]
            param.done = false
            @parameters << param
        end
    end

    def_param("prefix", "Base prefix of the local installation", "PATH") do
        RPA::Defaults::PREFIX
    end

    def_param("make-prog", "Make executable", "PROG") { "make" }
    def_param("ruby-prog", "Ruby executable", "PROG") do
        File.join(::Config::CONFIG["bindir"], 
                  ::Config::CONFIG["ruby_install_name"])
    end
    def_param("rpa-base", "Metadata directory", "PATH") do
        RPA::Defaults::RPA_BASE
    end
    def_param("sitelibdir", 
              "Path for Ruby modules relative to $prefix",
              "PATH", "--with-sitelibdir", "rpa-base") do |rpabase|
        RPA::Defaults::SITELIBDIR
    end
    def_param("so-dir",
              "Path for Ruby extensions relative to $prefix", 
              "PATH", "--with-so-dir", "sitelibdir") do |sitelibdir|
                  RPA::Defaults::SO_DIR
              end
    def_param("configfile",
             "Path to a file containing the configuration options", 
              "PATH", "--with-configfile") do "<none>" end
    def_param("verbose", "Verbosity level", "LEVEL", "--verbose") { 4 }
    def_param("debug", "Debug mode", nil, "--debug") { false }
    def_param("force", "Force installation despite file conflicts", nil,
              "--force") { false }
    def_param("build", "Only buils the .rpa packages.", nil,
              "--build") { false }
    def_param("parallelize", "Parallelize operations.", nil,
              "--parallelize") { false }
    def_param("no-tests", "Skip unit tests on install.", nil,
              "--no-tests") { true }

    def self.new(argv)
        options = parse(argv)
        options["verbose"] = options["verbose"].to_i
        super options
    end

    def self.parse(argv)
        options = {}
        params = Marshal.load(Marshal.dump(RPA::Config.parameters))
        opts = OptionParser.new do |opts|
            opts.banner = "Usage: ruby install.rb [options]"
            opts.separator ""
            opts.separator "Local installation options:"
            params.each do |param|
                if param.param
                    opts.on("--#{param.name} #{param.param}",
                            "#{param.desc}", "#{param.value}") do |o|
                                param.value = o
                                param.done = true
                            end
                else
                    opts.on("--#{param.name}", "#{param.desc}") do |o|
                        param.value = o
                        param.done = true
                    end
                end
            end
            opts.on_tail("-h", "--help", "Show this message") do
                puts opts
                exit # FIXME: is this right?
            end
        end
        opts.parse! argv
        configfile_param = params.find{|x| x.name == "configfile"}
        if configfile_param.value  != "<none>" # was specified
            begin
                file_opts = YAML.load(File.read(configfile_param.value))
            rescue
                raise "The configuration could not be loaded from #{configfile_param.value}"
            end
            options.update file_opts
        end
        params.each do |param| 
            if param.done 
                options[param.name] = param.value
            else
                next if options[param.name]  # was set with --config-file
                options[param.name] = @parameter_lambdas[param.name][params]
                param.done = true
            end
        end
        options
    end
    
    attr_reader :values
    
    def initialize(values)
        @values = values.clone
        # base-dirs represent the dirs that won't be removed on package
        # uninstall even when empty
        @values["base-dirs"] = [@values["sitelibdir"], @values["so-dir"]]
    end

    def determinant_values
        @values.select{|k,v| DETERMINANT_VALUES.include? k}
    end

    def [](key)
        raise "Unknown config field #{key}." unless @values.has_key?(key)
        @values[key]
    end
end

end
