#
# Copyright (C) 2004 Mauricio Julio Fernández Pradier
# See LICENSE.txt for additional licensing information.
#

require 'yaml'
require 'yaml/syck'
require 'optparse'
require 'rpa/defaults'
require 'fileutils'

module RPA

require 'rbconfig'
tmpbase = ENV['TMP']||ENV['TEMP']||ENV['TMPDIR']

case ::Config::CONFIG["arch"]
when /dos|win32/i
    unless tmpbase
        FileUtils.mkdir_p 'c:/temp'
        tmpbase = 'c:/temp'
    end
else
    tmpbase ||= '/tmp'
end

TEMP_DIR = File.join(tmpbase, "RPA_%10.6f" % Time.now())
PWD = Dir.pwd

DEFAULT_TEMP = "tmp"
class << self; attr_accessor :do_cleanup end
@do_cleanup = true

def self.cleanup
    begin
        if @do_cleanup
            FileUtils.rm_rf RPA::TEMP_DIR 
        end
    rescue Exception
    end
end

END { RPA.cleanup }

require 'rpa/config'
require 'rpa/package'
require 'rpa/transaction'
require 'rpa/install'
require 'rpa/localmetadata'
require 'rpa/util'
require 'rpa/packagestate'
require 'rpa/packagecache'
require 'rpa/port'
require 'rpa/repositoryinfo'

# Main class representing the local RPA installation.
class LocalInstallation
    class LockError < StandardError; end

    @@instances = {}
    attr_reader :config

    class << self
        private :new
        def instance(config, clean_state = true, logger = nil)
            @@instances[Marshal.dump(config.determinant_values)] ||= 
                new config, clean_state, logger
        end
    end

    def initialize(config, clean_state = true, logger = nil)
        @config = config
        @fileops = fileoperations_class.new logger
        @logger = logger
        @repositoryinfo = RepositoryInfo.instance(@config, logger)
        rpabase = File.join(@config["prefix"], @config["rpa-base"])
        @localmetadata = LocalMetadata.new(rpabase, logger)
        @packagecache = PackageCache.new(File.join(rpabase, "packages"),
                                         logger)
        @lock = nil
        @locklevel = 0
        apply_pending_rollbacks if clean_state
    end

    def clean_caches
        acquire_lock
        @packagecache.cleanup
    ensure
        release_lock
    end

    # Registers the given metadata (associated to the package
    # <tt>metadata["name"]</tt>).
    def register_metadata(metadata)
        @localmetadata.register_metadata metadata
    end

    # Retrieves the metadata corresponding to +pkgname+.
    def retrieve_metadata(pkgname)
        @localmetadata.retrieve_metadata pkgname
    end

    # Removes the metadata corresponding to +pkgname+.
    def remove_metadata(pkgname)
        @localmetadata.remove_metadata pkgname
    end

    def installed_ports
        @localmetadata.installed_ports
    end

    def installed_files
        @localmetadata.installed_files
    end

    def conflicts?(file)
        installed_files[file]  # nil if no conflict, pkgname otherwise
    end

    def installed?(name)
        return ! retrieve_metadata(name).nil?
    end

    # Runs a "local installation mutator" as a transaction, i.e. a snapshot of
    # the previous state is saved and a rollback performed if something goes
    # wrong (that is if the process is interrupted or the mutator raises an
    # exception).
    def transaction(new_metadata, lightweight = false, &block)
        acquire_lock
        verbose = @config["verbose"]
        #TODO: file locking etc
        recover = File.join(@config["prefix"], @config["rpa-base"], "transactions")
        pending = YAML.load(file_class.read(recover)) rescue []
        pending << packagestate_class.new(self, new_metadata, lightweight)
        @fileops.mkdir_p(File.dirname(recover), :mode => 0755)
        Transaction::atomic_write(recover, pending.to_yaml)
        rollback_proc = lambda do
            puts "Roll back..." if verbose >= 2
            apply_pending_rollbacks
        end
        begin
            if verbose >= 2
                if lightweight
                    puts "Starting lightweight (metadata only) transaction for " +
                        "#{new_metadata["name"]}"
                else
                    puts "Starting transaction for #{new_metadata["name"]}"
                end
            end
            block.call
            if verbose >= 2
                if lightweight
                    puts "Finished lightweight (metadata only) transaction for " +
                        "#{new_metadata["name"]}"
                else
                    puts "Finished transaction for #{new_metadata["name"]}"
                end
            end
            # if it bombs there, rollback
        rescue Interrupt => e
            puts "Transaction cancelled. Undoing changes." if verbose >= 2
            rollback_proc.call
            $! = e
            raise
        rescue Exception => e
            puts "Error while performing the transaction... Undoing changes" if verbose >= 2
            if @config["debug"]
                puts "Backtrace:"
                puts e.backtrace.join("\n")
            end
            rollback_proc.call
            $! = e
            raise
        end
    ensure
        release_lock
    end

    # Clean up the journal & remove all rollback info.
    # USE WITH CARE.
    def commit
        acquire_lock
        recover = File.join(@config["prefix"], @config["rpa-base"], "transactions")
        pending = YAML.load(file_class.read(recover)) rescue []
        Transaction::atomic_write(recover, [].to_yaml)
        puts "Committed changes" if @config["verbose"] >= 4
        # we don't mind being interrupted now cause the rollback info would be
        # removed in apply_pending_rollbacks anyway
        pending.each{|x| x.cleanup}
    ensure
        release_lock
    end

    # Restores a clean state using the information saved in the permanent
    # store during a transaction.
    def apply_pending_rollbacks
        lock_acquired = false
        recover = File.join(@config["prefix"], @config["rpa-base"], "transactions")
        pending = YAML.load(File.read_b(recover)) rescue []
        numpending = pending.size
        return if numpending == 0 # no need to lock, etc
        lock_acquired, bogus = true, acquire_lock
        verbose = @config["verbose"]

        # have to reload after the lock to make sure it wasn't modified before
        recover = File.join(@config["prefix"], @config["rpa-base"], "transactions")
        pending = YAML.load(File.read_b(recover)) rescue []
        numpending = pending.size
        rollbackdir = File.join(@config["prefix"], @config["rpa-base"],
                                "rollback")
        if numpending == 0
            Dir[File.join(rollbackdir, "*")].each {|x| FileUtils.rm_rf x}
            return
        end
        
        if verbose > 2
            puts "#{numpending} stopped transaction(s):" 
            pending.each do |x|
                if x.lightweight
                    info = "metadata"
                else
                    info = x.pkgfile || "cleanup"
                end
                puts "#{x.name} #{x.new_metadata["version"]} #{info}"
            end
            puts
        end

        numpending.times do 
            state = pending.pop
            state.restore self
        end
        Transaction::atomic_write(recover, [].to_yaml)
        Dir[File.join(rollbackdir, "*")].each {|x| FileUtils.rm_rf x}
    ensure
        release_lock if lock_acquired
    end
    
    # Build the port specified in +name+.
    def build(name, copy_rpa = false)
        verbose = @config["verbose"]

        port = @repositoryinfo.ports.find{|x| x.metadata["name"] == name}
        raise RuntimeError, "Couldn't find port #{name}." unless port
        # just copy it if from the cache
        if @packagecache.has_package?("name" => name, "version" =>
                                      port.metadata["version"])
            if copy_rpa
                @fileops.cp(@package_file.retrieve_package("name" => name),
                            RPA::PWD)
            end
            return
        end

        destdir = port.download
        begin
            Dir.chdir(destdir){ load "install.rb" }
        rescue Exception
            RPA::Install::AtExitHandler.cancel
            raise
        end
        Dir.chdir(destdir) do 
            c = RPA::Install.children.last
            saved_build = @config["build"]
            begin
                @config.values["build"] = true
                c.config = @config
                if verbose >= 4
                    puts "Building #{c.metadata["name"]} (#{c.metadata["version"]})."
                end
                c.run
                if copy_rpa
                    @fileops.cp c.package_file, RPA::PWD
                end
            ensure
                @config.values["build"] = saved_build
            end
            @packagecache.store_package c.package_file if write_access?
        end
    end

    # Install the port specified in +name+.
    # It is downloaded and built; in the process, its dependencies will be
    # installed first.
    def install(name, revdep = nil)
        verbose = @config["verbose"]
        port = @repositoryinfo.ports.find{|x| x.metadata["name"] == name}
        raise RuntimeError, "Couldn't find port #{name}." unless port
        meta = port.metadata
        if (pkg = @packagecache.retrieve_package(meta)).nil?
            build(name, false)
            pkg = @packagecache.retrieve_package(meta)
        else
            puts "Reusing cached package #{pkg}." if @config["verbose"] >= 3
        end

        do_install_package = lambda do
            force_transacted_install_package pkg
            metadata = Package.open(pkg){|f| f.metadata}
            unless revdep
                transaction(metadata, true){register_as_wanted name}
            end
        end
        # now we get serious, make sure we're in a clean state
        # we deliberately don't release this lock, cause we DO NOT WANT any
        # other transaction to happen in parallel when we enter the install
        # phase (i.e. first parallel builds, then installs serialized at the
        # process level, so we can commit the changed)
        acquire_lock
        # don't reinstall if it's the same version we have
        if (old = retrieve_metadata(name)) &&
            (port.metadata["version"] == old["version"])
            puts "Package #{name} unchanged." if verbose > 1
            # however, specify it's no longer just a pre-req but wanted too
            # if no revdep was given
            transaction(old, true) { register_as_wanted name } unless revdep
            # that's a 'lightweight transaction', only the metadata is saved
            # to permanent storage since the data itself won't change
            return
        end
            
        if (deps = meta["requires"] || []).size == 0
            transaction(meta, true) { do_install_package.call }
        else
            if @config["verbose"] >= 4 && deps.size != 0
                puts "Installing dependencies #{deps.join(' ')}." 
            end
            transaction(meta, true) do 
                deps.each do |port|
                    install(port, name) 
                end
                do_install_package.call
            end
        end
    end

    # install from the given port, i.e. build the .rpa and install it
    def install_from_port(filename)
        #FIXME: maybe write build_from_port and use that?
        destdir = File.join(RPA::TEMP_DIR, "#{filename}_i_f_p_#{rand(100000)}")
        Package.open(filename) do |port|
            port.each { |entry| port.extract_entry(destdir, entry) }
        end
        begin
            load File.join(destdir, "install.rb")
        rescue Exception
            RPA::Install::AtExitHandler.cancel
            raise
        end
        Dir.chdir(destdir) do 
            c = RPA::Install.children.last
            c.config = @config
            c.run
            transaction(c.metadata, true){register_as_wanted c.metadata["name"]}
            #TODO: decide if we should store this or not
            @packagecache.store_package c.package_file if write_access?
        end
    end

    def get_port(name, destdir)
        port = @repositoryinfo.ports.find{|x| x.metadata["name"] == name}
        port.download(".")
    end

    # Non-transacted install of the +pkgfile+.
    # It will replace the package already installed if need be.
    def force_install_package(pkgfile)
        acquire_lock
        force_install_pkg_impl(pkgfile)
    ensure
        release_lock
    end

    # Transacted install of the specified <tt>.rpa</tt> file (+pkgfile+).
    # It will replace the package already installed if need be.
    def force_transacted_install_package(pkgfile)
        acquire_lock
        meta = Package.open(pkgfile){|p| p.metadata}
        managed, unmanaged = check_conflicts pkgfile
        if managed.size != 0
            str = "File conflicts detected:\n" 
            managed.each{|file, port| str << "  #{file} owned by #{port}\n"}
            raise str
        end
        if unmanaged.size != 0
            if @config["force"]
                unmanaged.each{|f| puts "WARNING: file #{f} will be overwritten."}
            else
                str = "File conflicts detected:\n" 
                unmanaged.each{|f| str << "  #{f}\n"}
                additional =<<EOF

You might want to run with --force to make rpa-base assume the ownership
of these files.

EOF
                str << additional
                raise str
            end
        end
        transaction(meta) { force_install_pkg_impl(pkgfile) }
    ensure
        release_lock
    end
    
    # Run an installer (subclass of RPA::Install::InstallerBase generally) as
    # a transaction.
    def run_installer(installer)
        installer.config = @config
        name = installer.metadata["name"]
        # we don't care about installer.metadata not having the files and dirs
        # info. When force_transacted_install_package is called by one
        # of installers' subtasks, we know that either the new version will be
        # unpacked _AND_ the new metadata registered or the old version will
        # stay. Even in the event of a crash during the 'inner' transaction,
        # it would be completed when the program is run again, leaving the
        # state clean for the following transaction to be carried out.
        transaction(installer.metadata, true){installer.run}
        puts "Installed #{name}" if @config['verbose'] >= 1
    end

    # Transacted uninstall of +name+.
    # <tt>installed_pkgs_meta</tt>:: metadata of the installed package
    # <tt>handle_rev_deps</tt>:: remove reverse-dependencies if +true+
    def uninstall(name, installed_pkgs_meta = nil, handle_rev_deps = true)
        acquire_lock
        meta = retrieve_metadata name
        raise "Package #{name} is not installed." unless meta
        transaction(meta, false) do
            uninstall_impl(name, installed_pkgs_meta, handle_rev_deps) 
        end
    end

    # Specify that +pkgname+ was not installed only to satisfy a dependency.
    def register_as_wanted(pkgname)
        old = retrieve_metadata pkgname
        old["wanted"] = true
        register_metadata old
    end

    # Remove ports that were only installed to satisfy the dependencies of
    # another port that got uninstalled afterwards.
    def gc_unneeded_ports
        acquire_lock
        verbose = @config["verbose"]
        puts "Removing unneeded dependencies" if verbose >= 1
        all = {}
        installed_ports.each do |x|
            all[x] = retrieve_metadata x
            all[x]["visited"] = false
        end
        roots = all.select{|k,v| v["wanted"]}.map{|k,v| v["name"]}
        mark_ports(all, roots)
        to_be_removed = all.reject{|k,x| x["wanted"]}.map{|k,v| k}
        if verbose >= 2
            puts "Will remove: "
            to_be_removed.each {|x| puts " * #{x}" }
        end
        to_be_removed.each {|x| uninstall x}
    ensure
        release_lock
    end

    # See whether the recorded MD5 digests correspond to the files on disk.
    # Returns nil if no change was done, otherwise a hash
    #  { filename =>  ( :deleted | :modified ) }
    def modified_files(port)
        acquire_lock
        raise "Port #{port} is not installed." unless installed? port
        meta = retrieve_metadata port
        ret = nil
        meta["files"].each do |fname|
            md5 = Digest::MD5.new
            srcfile = File.join(@config["prefix"], fname)
            unless File.file? srcfile 
                (ret ||= {})[fname] = :deleted 
                next
            end
            File.open(srcfile, "rb") do |is|
                loop do
                    read = is.read(4096)
                    break if !read || read.size == 0
                    md5 << read
                end
            end 
            (ret ||= {})[fname] = :modified if meta["md5sums"][fname] != md5.hexdigest
        end 
        ret
    ensure
        release_lock
    end

    def check_conflicts(pkg)
        previously_installed_files = installed_files
        conflicts_unmanaged = []
        conflicts_managed = []
        Package.open(pkg) do |inpkg|
            meta = inpkg.metadata
            puts "Checking for file conflicts in #{meta["name"]}." if @config["verbose"] >= 2
            inpkg.each do |entry| 
                next if entry.is_directory
                prev = previously_installed_files[entry.name]
                # file already there, and not managed by RPA
                # OR file managed, belongs to another port
                if File.exist?(File.join(@config["prefix"], entry.name)) && prev == nil
                    conflicts_unmanaged << entry.name
                elsif (prev && prev != meta["name"])
                    conflicts_managed << [entry.name, prev]
                end
            end
        end
        return conflicts_managed, conflicts_unmanaged
    end

    def acquire_lock
        if @lock
            @locklevel += 1
            puts "Locklevel #{@locklevel}" if @config["verbose"] >= 6
            return
        end
        lockfile = File.join(@config["prefix"], @config["rpa-base"],
                             "lock")
        begin
            @lock = File.open(lockfile, "w")
            if @config["parallelize"]
                puts "Trying to acquire lock (parallel mode)" if @config["verbose"] >= 4
                @lock.flock File::LOCK_EX
                puts "Acquired lock (parallel mode)" if @config["verbose"] >= 4
            else
                raise "bad" unless @lock.flock File::LOCK_EX|File::LOCK_NB 
            end
        rescue Exception
            @lock = nil
            raise LockError
        end
        @locklevel = 1
        puts "Locklevel #{@locklevel}" if @config["verbose"] >= 6
    end

    def release_lock
        return unless @lock #FIXME: should never happen
        @locklevel -= 1
        if @locklevel == 0
            @lock.flock File::LOCK_UN
            @lock.close
            @lock = nil
            puts "Releasing lock" if @config["verbose"] >= 6
        end
    end
    
    def packagestate_class
        PackageState
    end
    
    def fileoperations_class
        FileOperations
    end
    
    def file_class
        File
    end

    def dir_class
        Dir
    end

    private
    def write_access?
        begin
            f = File.open(File.join(@config["prefix"], @config["rpa-base"],
                                    "access"), "w")
            f.close
            return true
        rescue Errno::EACCES
            return false
        end
    end

    def force_install_pkg_impl(pkgfile)
        verbose = @config["verbose"]

        Package.open(pkgfile, "r") do |inpkg|
            meta = inpkg.metadata
            previous_meta = retrieve_metadata meta["name"]
            if previous_meta
                    # force package removal, ignore dependencies
                puts "Preparing to replace #{previous_meta["name"]} #{previous_meta["version"]} " + 
                    "with #{pkgfile}" if verbose >= 2
                RPA::Uninstaller.new(previous_meta, @config).run
                remove_metadata meta["name"]
            end
            # we do not have to worry about the files we're about to install now
            # w.r.t. the transaction, since if this was called while doing a
            # rollback and we get interrupted, on the next run (when recovering
            # using the pending transaction list) they will just be
            # overwritten/removed.
            previously_installed_files = installed_files
            inpkg.each do |entry| 
                # no conflict check needed here, assume it was done before
                if !entry.is_directory
                    inpkg.extract_entry(@config["prefix"], entry,
                                        meta["md5sums"][entry.full_name])
                else
                    inpkg.extract_entry(@config["prefix"], entry)
                end
            end
            puts "Package #{pkgfile} unpacked." if verbose >= 2
            register_metadata meta
        end
    end

    def uninstall_impl(name, installed_pkgs_meta = nil, handle_rev_deps = true)
        verbose = @config["verbose"]
        meta = retrieve_metadata name
        raise "Package #{name} is not installed." unless meta
        
        infodir = File.join(@config["prefix"], @config["rpa-base"], "info")
        installed_pkgs_meta ||= installed_ports.map{|x| retrieve_metadata x}
        # avoid endless loop
        installed_pkgs_meta.reject!{|x| x["name"] == name}
        
        if handle_rev_deps
            rev_deps = installed_pkgs_meta.select do |pkg|
                (pkg["requires"] || []).include? name
            end
            rev_deps.map!{|x| x["name"] }
        end
        puts "Trying to remove #{name}" if verbose >= 2
        RPA::Uninstaller.new(meta, @config).run
        remove_metadata name
        if handle_rev_deps
            puts "Reverse dependencies: #{rev_deps.inspect}" if verbose >= 2
            rev_deps.each { |x| uninstall(x, installed_pkgs_meta) }
        end
        puts "Removed #{name}" if verbose >= 1
    end

    def mark_ports(all, subset)
        subset ||= []
        subset.each do |port|
            p = all[port]
            p["wanted"] = true
            p["visited"] = true
            mark_ports all, p["requires"]
        end
    end
end

end # RPA namespace

