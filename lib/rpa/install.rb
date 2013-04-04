#
# Copyright (C) 2004 Mauricio Julio Fernández Pradier
# See LICENSE.txt for additional licensing information.
#

require 'rpa/base'
require 'rpa/helper'
require 'rpa/classification'
require 'time'

module RPA
        
module Install
    @children = []
    @auto_install = true
    class << self; attr_accessor :children, :auto_install; end
    at_exit_handler_class = Class.new do
        def initialize; at_exit { run }; @procs = [] end
        def register(&aproc); @procs << aproc end
        def run; @procs.each{|x| x.call} unless $! end
        def cancel; @procs = [] end
    end
    AtExitHandler = at_exit_handler_class.new

    module StandaloneInheritanceMagic
        def inherited(child)
            super
            # don't want to add a hook for the classes we're defining
            # in this file!
            if self != InstallerBase
                child.inherited_hook
                if RPA::Install.auto_install
                    RPA::Install::AtExitHandler.register do 
                        unless child.aborted
                            repos = RPA::LocalInstallation.instance(RPA::Config.new(ARGV))
                            repos.apply_pending_rollbacks
                            child.metadata["wanted"] = true
                            repos.run_installer child
                            repos.commit # the port + all deps were installed OK
                        end
                    end
                    # only use at_exit for one installer at most
                    RPA::Install.auto_install = false
                else
                    RPA::Install.children << child
                end
            end
        end
    end

    class InstallerBase
        extend RPA::Helper
        include RPA::Helper # import the constants
        extend StandaloneInheritanceMagic
        include RPA::Classification::TOP
        #TODO: make something more sensible with default vals, etc
        FIELDS = [ :name, :version, :requires, :suggests, :classification, 
                :description, :test_suite, :build_requires]
        class << self
            attr_reader :metadata, :config
            attr_writer :config
            attr_accessor :aborted
            attr_accessor :package_file

            FIELDS.each do |field|
                define_method(field) do |*args|
                    vmethod = "validate_#{field}"
                    args = send(vmethod, *args)
                    #FIXME: full blown object?
                    @metadata ||= 
                        {'platform' => ::Config::CONFIG['target'],
                         'rpaversion' => RPA::VERSION, 
                         'date' => Time.new.rfc2822} 
                    @metadata[field.to_s] = args
                    instance_variable_set "@#{field}", args
                end
            end

            def run
                @package_file = nil
                validate_metadata
                @tasks.each do |task|
                    task.each do |subtask|
                        if @config["debug"] || @config["verbose"] >= 5
                            puts "Running task #{subtask.class}."
                        end
                        subtask.run self 
                    end
                end
            end

            def validate_metadata
                raise "No metadata specified." unless metadata
                raise "Missing 'version' in metadata." if !metadata["version"]
                raise "Missing 'classification' in metadata." if !metadata["classification"]
                raise "Missing 'description' in metadata." if !metadata["description"]
            end

            def validate_description(desc)
                desc
            end

            # verify the package satisfies the naming policy
            def validate_name(name)
                return name if name =~ /\A[a-z]([0-9a-z+-]|\.)+\z/
                @aborted = true
                raise RuntimeError, "Name #{name} not policy-compliant."
            end

            # verify that the version is valid
            def validate_version(version)
                return version if version =~ /\A[0-9]([0-9]|(\.[0-9]))*[a-z]*-([0-9]+)\z/
                @aborted = true
                raise RuntimeError, "Version #{version} not policy-compliant."
            end

            # verify that
            # * the dependencies exist
            # * the version constraints are OK
            def validate_requires(*require_list)
                require_list
            end

            def validate_build_requires(*require_list)
                validate_requires(*require_list)
            end

            # check that all suggested packaged actually exist
            def validate_suggests(*suggestions)
                suggestions
            end

            # verify that this is a valid classification
            def validate_classification(*classification)
                if classification.size > 4
                    raise RuntimeError, "No more than 4 categories allowed."
                end
                bad = classification.reject do |x| 
                    x.is_a? RPA::Classification::Category
                end
                unless bad.empty?
                    raise RuntimeError, "Bad categories: #{bad.inspect}"
                end
                classification.map{|x| x.long_name }
            end

            def validate_test_suite(test_suite)
                test_suite
            end
                

            private
            meths = { :prebuild => 0, :build => 1, :install => 2,
                      :postinstall => 3}
            meths.each do |m, idx|
                module_eval <<-EOF
                    def #{m}(&block)
                        o = helper_collector
                        o.instance_eval(&block)
                        @tasks[#{idx}].map! do |x|
                            if o.rejected.any?{|k| x.is_a? k}
                                toadd = o.tasks.select{|k| x.class === k}
                                toadd.each{|x| o.tasks.delete(x)}
                                toadd
                            else
                                # not overriden
                                x
                            end
                        end
                        @tasks[#{idx}].flatten!
                        @tasks[#{idx}] += o.tasks
                    end
                EOF
            end
            
            def helper_collector
                kl = Class.new do
                    attr_accessor :tasks, :rejected

                    def initialize
                        @tasks = []
                        @rejected = []
                    end

                    def skip_default(klass)
                        @rejected << klass
                    end
                end
                cons = RPA::Helper.constants.map{|x| RPA::Helper.const_get x}
                helpers = cons.select{|x| Class === x} - [RPA::Helper::HelperBase]
                helpers.each do |klass|
                    mname = klass.to_s.downcase.split(/::/).last
                    # what we want is 
                    #kl.send(:define_method, mname) do |*args| 
                    #    @tasks << klass.new(*args) 
                    #end
                    # but blocks don't accept blocks (yet), so we make it
                    # dirty
                    kl.module_eval <<-EOF
                        def #{mname}(*args, &block)
                            @rejected << #{klass.to_s}
                            @tasks << #{klass.to_s}.new(*args, &block)
                        end
                    EOF
                end
                kl.new
            end
        end
    end # class InstallerBase

    class PureRubyLibrary < InstallerBase
        def self.inherited_hook
            @tasks = [ 
                [testversion, installpredependencies, installdependencies, clean],
                [installchangelogs, installdocs,
                    installrdoc, installman, installexamples,
                compress, installtests, installmodules,
                fixperms],
                [ md5sums, moduledeps, installmetadata, buildpkg, 
                    extractpkg, rununittests],
                []
            ]
        end
    end

    class Application < InstallerBase
        def self.inherited_hook
            @tasks = [
                [testversion, installpredependencies, installdependencies, clean],
                [buildextensions, installchangelogs, installdocs,
                    installrdoc, installman, installexamples,
                compress, installtests, installmodules, installexecutables,
                installextensions, moduledeps, fixperms,
                fixshebangs], 
                [ md5sums, moduledeps, installmetadata, buildpkg, 
                    extractpkg, rununittests],
                []
            ]
        end
    end

    class FullInstaller < InstallerBase
        def self.inherited_hook
            @tasks = [
                [testversion, installpredependencies, installdependencies, clean],
                    [buildextensions, installchangelogs, installdocs,
                        installrdoc, installman,
                    installexamples, compress,
                    installtests, installmodules, installexecutables,
                    installextensions, moduledeps,
                    fixperms, fixshebangs],
                    [ md5sums, moduledeps, installmetadata, buildpkg, 
                        extractpkg, rununittests],
                []
            ]
        end
    end
end # module Install

class Uninstaller
    require 'digest/md5'

    def initialize(metadata, config = RPA::Config.new, logger = nil)
        @metadata = metadata
        @config = config
        @fileops = FileOperations.new logger
        @logger = logger
    end

    def run(previous_files = nil)
        previous_files ||= {}
        (@metadata["files"] || []).each do |fname|
            # we check if the file is "owned" by the package we're removing,
            # since this could be running as as the result of a conflict when
            # unpacking
            from_pkg = previous_files[fname]
            next if from_pkg && from_pkg != @metadata["name"]
            #FIXME: log this operation?
            begin
                nam = File.join(@config["prefix"], fname)
                oldmd5 = @metadata["md5sums"][fname]
                if oldmd5 
                    if same_md5(oldmd5, nam)
                        File.unlink nam
                        fsync_dir File.dirname(nam)
                    else
                        if @config["verbose"].to_i >= 3
                            puts "Keeping locally modified #{nam}."
                        end
                    end
                else
                    File.unlink nam
                    fsync_dir File.dirname(nam)
                end
            rescue SystemCallError
                #ignore
            end
            # Errno::ENOENT if not fully installed
        end
        (@metadata["dirs"] || []).sort.reverse.each do |dname|
            # reverse sort to remove children before parents
            next if @config["base-dirs"].include? dname
            next if @config["base-dirs"].any?{|x| x[/\A#{Regexp.escape(dname)}/]}
            dstdir = File.join @config["prefix"], dname
            if Dir.glob("#{dstdir}/*", File::FNM_DOTMATCH).size == 2
                # includes . and .. only, remove it
                begin
                    Dir.rmdir dstdir
                    fsync_dir File.dirname(dstdir)
                rescue SystemCallError
                    #ignore 
                end
                # Errno::ENOENT if not fully installed
            end
        end
    end

    private
    def fsync_dir(dirname)
            # make sure this hits the disc
        begin
            dir = open(dirname, "r")
            dir.fsync
        rescue IOError, SystemCallError, Errno::EACCES
        # ignore IOError if it's an unpatched (old) Ruby
        ensure
            dir.close if dir rescue nil
        end
    end

    def same_md5(md5, file)
        digest = Digest::MD5.new
        File.open(file, "rb") do |f|
            digest << f.read(4096) until f.eof?
        end
        digest.hexdigest == md5
    end
end

end



