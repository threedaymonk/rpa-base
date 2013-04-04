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
tmpbase = ENV['TMPDIR']||ENV['TMP']||ENV['TEMP']

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

# Main class representing the local RPA installation.
class LocalInstallation
    class LockError < StandardError; end

    @@instances = {}
    attr_reader :config

    class << self
        private :new
        def instance(config, logger = nil)
            @@instances[Marshal.dump(config.determinant_values)] ||= 
                new config, logger
        end
    end

    def initialize(config, logger = nil)
        @config = config
        @fileops = fileoperations_class.new logger
        @logger = logger
        @repositoryinfo = RepositoryInfo.instance(@config, logger)
        @lock = nil
        @locklevel = 0
        apply_pending_rollbacks
    end

    # Registers the given metadata (associated to the package
    # <tt>metadata["name"]</tt>).
    def register_metadata(metadata)
        infodir = File.join(@config["prefix"], @config["rpa-base"], "info")
        unless File.dir? infodir
            @fileops.mkdir_p(infodir, :mode => 0755)
        end
        file_class.open(File.join(infodir, metadata["name"]), "wb") do |f|
            f.write metadata.to_yaml
        end
        instfile = File.join(@config["prefix"], @config["rpa-base"],
                             "installed")
        installed = YAML.load(file_class.read(instfile)) rescue []
        installed << metadata["name"]
        installed = installed.uniq
        Transaction::atomic_write(instfile, installed.to_yaml)
    end

    # Retrieves the metadata corresponding to +pkgname+.
    def retrieve_metadata(pkgname)
        infofile = File.join(@config["prefix"], @config["rpa-base"], "info",
                             pkgname)
        instfile = File.join(@config["prefix"], @config["rpa-base"],
                             "installed")
        installed = YAML.load(file_class.read(instfile)) rescue []
        if installed.include? pkgname
            YAML.load(file_class.read(infofile))
        else
            nil
        end
    end

    # Removes the metadata corresponding to +pkgname+.
    def remove_metadata(pkgname)
        instfile = File.join(@config["prefix"], @config["rpa-base"],
                             "installed")
        installed = YAML.load(file_class.read(instfile)) rescue []
        installed.delete pkgname
        Transaction::atomic_write(instfile, installed.to_yaml)
        infofile = File.join(@config["prefix"], @config["rpa-base"], "info",
                             pkgname)
        @fileops.rm_f(infofile) rescue nil
    end

    def installed_ports
        instfile = File.join(@config["prefix"], @config["rpa-base"],
                             "installed")
        YAML.load(file_class.read(instfile)) rescue []
    end

    def installed_files
        #TODO: cache
        infodir = File.join(@config["prefix"], @config["rpa-base"],
                            "info")
        instfile = File.join(@config["prefix"], @config["rpa-base"],
                             "installed")
        installed = YAML.load(file_class.read(instfile)) rescue []
        files = {}
        installed.map{|x| File.join(infodir, x)}.each do |fname|
            pkgfiles = YAML.load(file_class.read(fname))
            pkgfiles["files"].each {|f| files[f] = pkgfiles["name"]}
        end
        files
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
        # we don't mind being interrupted now cause the rollback info would be
        # removed in apply_pending_rollbacks anyway
        pending.each{|x| x.cleanup}
    ensure
        release_lock
    end

    # Restores a clean state using the information saved in the permanent
    # store during a transaction.
    def apply_pending_rollbacks
        acquire_lock
        verbose = @config["verbose"]

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
        release_lock
    end

    # Install the port specified in +name+.
    # It is downloaded and built; in the process, its dependencies will be
    # installed first.
    def install(name, revdep = nil)
        acquire_lock
        verbose = @config["verbose"]

        port = @repositoryinfo.ports.find{|x| x.metadata["name"] == name}
        raise RuntimeError, "Couldn't find port #{name}." unless port
        # don't download if it's the same version we have
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
        destdir = port.download
        begin
            load File.join(destdir, "install.rb")
        rescue Exception
            RPA::Install::AtExitHandler.cancel
            raise
        end
        run_installer_on_dir(destdir, revdep)
    ensure
        release_lock
    end

    # Non-transacted install of the +pkgfile+.
    # It will replace the package already installed if need be.
    def force_install_package(pkgfile)
        acquire_lock
        Package.open(pkgfile, "r") do |inpkg|
            force_install_pkg_impl(inpkg, pkgfile)
        end # package
    ensure
        release_lock
    end

    # Transacted install of the specified <tt>.rpa</tt> file (+pkgfile+).
    # It will replace the package already installed if need be.
    def force_transacted_install_package(pkgfile)
        acquire_lock
        Package.open(pkgfile, "r") do |inpkg|
            transaction(inpkg.metadata) { force_install_pkg_impl(inpkg, pkgfile) }
        end # package
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
        puts "Installed #{installer.metadata["name"]}" if @config['verbose'] >= 1
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
    ensure
        release_lock
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

    def acquire_lock
        if @lock
            @locklevel += 1
            return
        end
        lockfile = File.join(@config["prefix"], @config["rpa-base"],
                             "lock")
        begin
            @lock = File.open(lockfile, "w")
            raise "bad" unless @lock.flock File::LOCK_EX|File::LOCK_NB 
        rescue Exception
            @lock = nil
            raise LockError
        end
        @locklevel = 1
    end

    def release_lock
        return unless @lock #FIXME: should never happen
        @locklevel -= 1
        if @locklevel == 0
            @lock.flock File::LOCK_UN
            @lock.close
            @lock = nil
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
    def run_installer_on_dir(destdir, revdep)
        Dir.chdir(destdir) do 
            c = RPA::Install.children.last
            c.metadata["wanted"] = true unless revdep
            run_installer(c) if c
        end
    end

    def force_install_pkg_impl(inpkg, pkgfile)
        verbose = @config["verbose"]

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
        cachedinfo = YAML.load(File.read_b(@cachefile)) rescue []
        @ports = cachedinfo.map{|x| Port.new(x["metadata"], x["url"], @config) }
    end

    # Add a source of port information. 
    def add_source(url)
        @sources << url
    end

    require 'open-uri'
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
            # FIXME: not all at once in mem
                src = src.gsub(%r{\Afile://}, "")
                open(src) {|is| newinfo = newinfo + YAML.load(is.read)} 
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
        localinst.release_lock
    end

    # Returns an array of Port objects corresponding to the available ports.
    def ports
        @ports
    end
end

# Reponsible for taking a snapshot of a given package. It can be restored
# later with #restore. This class is designed to allow the corresponding
# objects to be serialized to disk, so that the state is saved across program
# invocations in case of crash, SIGKILL, etc...
class PackageState
    require 'digest/md5'
    @counter = 0
    class << self; attr_accessor :counter end
    attr_reader :id

    attr_reader :name, :new_metadata, :pkgfile, :lightweight
    def initialize(localinstallation, new_metadata, lightweight = false)
        @id = #{Time.new.to_i}#{self.class.counter}#{rand(1000000)}"
        self.class.counter += 1
        @name = new_metadata["name"]
        @installed = localinstallation.installed? @name
        @config = localinstallation.config
        @new_metadata = new_metadata
        @pkgfile = nil
        @lightweight = lightweight
        if @lightweight
            @old_metadata = localinstallation.retrieve_metadata(@name)
        elsif @installed
            # repack
            repack localinstallation, new_metadata, lightweight
        end
    end

    def repack(localinstallation, new_metadata, lightweight)
        meta = localinstallation.retrieve_metadata @name
        fileops = FileOperations.new nil
        tmpdir = File.join(RPA::TEMP_DIR, "saved_#{rand(10000)}")
        while File.exist? tmpdir
            tmpdir = File.join(RPA::TEMP_DIR, "saved_#{rand(10000)}")
        end 
        fileops.mkdir_p(tmpdir)
        fileops.mkdir_p File.join(tmpdir, "RPA")
        meta["md5sums"] = {}
        files2 = []
        meta["files"].each do |fname|
            md5 = Digest::MD5.new
            fileops.mkdir_p(File.dirname(File.join(tmpdir, fname)))
            srcfile = File.join(@config["prefix"], fname)
            File.open(srcfile, "rb") do |is|
                dstfile = File.join(tmpdir, fname)
                File.open(dstfile, "wb") do |os|
                    loop do
                        read = is.read(4096)
                        break if !read || read.size == 0
                        os.write read
                        md5 << read
                    end
                end
                File.chmod(File.stat(srcfile).mode, dstfile)
                files2 << fname
                meta["md5sums"][fname] = md5.hexdigest
            end rescue nil
        end
        meta["files"] = files2
        File.open(File.join(tmpdir, "RPA", "metadata"), "wb") do |f|
            f.write meta.to_yaml
        end
        meta["dirs"].each do |dname|
            fileops.mkdir_p(File.join(tmpdir, dname))
        end

        pkgfile = meta["name"] + '_' + meta["version"] + '_' +
            meta["platform"] + "#{Time.new.to_i}-#{rand(100000)}" + '.rpa'
        while File.file?(File.join(storage_dir, pkgfile))
            pkgfile = meta["name"] + '_' + meta["version"] + '_' +
                meta["platform"] + "#{Time.new.to_i}-#{rand(100000)}" + '.rpa'
        end 

        fileops.mkdir_p(storage_dir)
        Package.pack(tmpdir, File.join(storage_dir, pkgfile))
        fileops.rm_rf tmpdir
        @pkgfile = File.join(storage_dir, pkgfile)
            # fsync the file and its parent dir
        File.open(@pkgfile) { |f| f.sync rescue nil  }
        File.open(File.dirname(@pkgfile)) {|d| d.fsync } rescue nil
    end

    # Restore the saved state.
    def restore(installation)
        verbose = @config["verbose"]

        puts "Restoring state..." if verbose >= 1
        if @lightweight
            if @installed
                puts "Recovering old metadata..." if verbose >= 2
                installation.register_metadata @old_metadata
            else
                installation.remove_metadata @name
            end
            return
        end
        unless @installed 
            # we remove the files from the new version that have been
            # installed
            RPA::Uninstaller.new(@new_metadata,
                                 @config).run(installation.installed_files)
            # remove the files indicated by the current metadata, just in case 
            # @new_metadata didn't contain all the info (files, dirs)
            meta = installation.retrieve_metadata @name
            if meta
                RPA::Uninstaller.new(meta,
                                     @config).run(installation.installed_files)
            end

            installation.remove_metadata @name
            return
        end

        RPA::Uninstaller.new(@new_metadata,
                             @config).run(installation.installed_files)
        # we care to remove the files from the "previous" (currently
        # installed) version because the package could have been unpacked
        # correctly, the only problem being that tests didn't pass, so we
        # remove the files indicated by the current metadata, just in case 
        # @new_metadata didn't contain all the info (files, dirs)
        meta = installation.retrieve_metadata @name
        if meta
            RPA::Uninstaller.new(meta,
                                 @config).run(installation.installed_files)
        end
        
        puts "Installing previous version from #{@pkgfile}" if verbose >= 2
        # was installed before so attempt to upgrade it...
        installation.force_install_package @pkgfile
        # we must *not* cleanup here cause the rollback process could fail
        # just when rewriting the journal
    end

    # Remove the associated data in the permanent storage.
    def cleanup
        FileUtils.rm_f @pkgfile if @pkgfile
    end

    private
    def storage_dir
        File.join(@config["prefix"], @config["rpa-base"], "rollback")
    end
end

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

    require 'open-uri'
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
        if BROKEN_WINDOWS && @url =~ %r{http://}
            fetch_win(@url, dest)
        else
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
        end
        extract dest, destdir
        @fileops.rm_f(dest)
        destdir
    end

    private
    require 'net/http'
    require 'uri'
    def fetch_win(src, dest, limit = 10)
        raise ArgumentError, 'http redirect too deep' if limit == 0

        puts "Getting #{src}." if @config["verbose"] >= 2
        response = Net::HTTP.get_response(URI.parse(src))
        case response
        when Net::HTTPSuccess     
            File.open(dest, "wb") {|f| f.write response.body }
        when Net::HTTPRedirection then fetch_win(response['location'], dest, limit-1)
        else
            response.error!
        end
    end
    
    def extract(pkg, destdir)
        Package.open(pkg) do |port|
            port.each { |entry| port.extract_entry(destdir, entry) }
        end
    end
end

# Wrapper for FileUtils meant to provide logging and additional operations if
# needed.
class FileOperations
    require 'fileutils'
    extend FileUtils
    class << self
            # additional methods not implemented in FileUtils
    end
    def initialize(logger = nil)
        @logger = logger
    end

    def method_missing(meth, *args, &block)
        case
        when FileUtils.respond_to?(meth)
            @logger.log "#{meth}: #{args}" if @logger
            FileUtils.send meth, *args, &block
        when FileOperations.respond_to?(meth)
            @logger.log "#{meth}: #{args}" if @logger
            FileOperations.send meth, *args, &block
        else
            super
        end
    end
end


end # RPA namespace

class File
    # straight from setup.rb
    def File.dir?(path)
        # for corrupted windows stat()
        File.directory?((path[-1,1] == '/') ? path : path + '/')
    end

    def File.read_b(name)
        File.open(name, "rb"){|f| f.read}
    end
end

