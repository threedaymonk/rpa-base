#
# Copyright (C) 2004 Mauricio Julio Fernández Pradier
# See LICENSE.txt for additional licensing information.
#

module RPA
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

end # namespace RPA
