#
# Copyright (C) 2004 Mauricio Julio Fernández Pradier
# See LICENSE.txt for additional licensing information.
#

require 'rpa/base'
require 'rpa/classification'
require 'rpa/package'
require 'rbconfig'
require 'fileutils'

module RPA
module Helper
IGNORE_DIRS = %w[CVS SCCS RCS CVS.adm .svn]
# stolen from setup.rb
mapping = { '.' => '\.', '$' => '\$', '#' => '\#', '*' => '.*' }
IGNORE_FILES = %w[core RCSLOG tags TAGS .make.state .nse_depinfo 
        #* .#* cvslog.* ,* .del-* *.olb *~ *.old *.bak *.BAK *.orig *.rej _$* *$
        *.org *.in .* ].map do |x|
            Regexp.new("\A" + x.gsub(/[\.\$\#\*]/){|c| mapping[c]} + "\z")
        end
#end of robbery
        
EXT_SUBDIRS=["ext"]
DLEXT = /\.#{ ::Config::CONFIG['DLEXT'] }\z/

def all_files_in(dirname, dirobject = nil) # from setup.rb
    begin
        (dirobject || dir_class).open(dirname) do |d|
            return d.select {|ent| file_class.file?("#{dirname}/#{ent}") }.
            reject { |ent| IGNORE_FILES.any? { |x| x =~ ent } }
        end
    rescue Errno::ENOENT
        []
    end
end

def all_dirs_in(dirname, dirobject = nil) # from setup.rb
    begin
        (dirobject || dir_class).open(dirname) do |d|
            return d.select{|n| file_class.dir?("#{dirname}/#{n}") } - 
            %w(.  ..) - IGNORE_DIRS
        end
    rescue Errno::ENOENT
        []
    end
end

module_function :all_dirs_in, :all_files_in

class HelperBase

    include FileUtils
    include Helper

    def initialize(logger = nil)
        @dest = RPA::DEFAULT_TEMP
        @fileops = FileOperations.new logger
        @logger = logger
    end

    def make(*args)
        @logger.log("make: " + args.inspect) if @logger
        system "#{@config["make-prog"]} " + args.join(" ")
    end

    def extconf(*args)
        @logger.log("extconf: " + args.inspect) if @logger
        system "#{@config["ruby-prog"]} extconf.rb " + args.join(" ")
    end
    
    def ruby(*args)
        @logger.log("ruby: " + args.inspect) if @logger
        system "#{@config["ruby-prog"]} " + args.join(" ")
    end

    def run(installer)
        @config = installer.config
    end

    private
    
    def dir_class
        Dir
    end

    def file_class
        File
    end

    def find_class
        require 'find'
        Find
    end
end

# Building a binary package from the temporary subdir.
class Buildpkg < HelperBase
    def initialize(tempdirname = nil, logger = nil)
        super logger
        @src = tempdirname || "rpa/#{@dest}"
    end
    
    def run(installer)
        super
        meta = installer.metadata
        destname = Package.normalized_name meta
        puts "Building package in #{destname}." if @config["verbose"] >= 4
        Package.pack(@src, destname)
        installer.package_file = destname
    end
end

class Buildextensions < HelperBase
    def initialize(extconfargs = "", subdir = nil, logger = nil)
        @args = extconfargs
        @subdir = subdir
        super(logger)
    end
    
    def run(installer)
        super
        if @subdir
            build_extension(@subdir)
        else
            EXT_SUBDIRS.each do |dir|
                next unless file_class.dir? dir
                build_extension(dir)
            end
        end
    end

    def build_extension(dname)
        dir_class.chdir(dname) do
            if file_class.file? "Makefile"
                make "distclean"
            end
            if file_class.file? "extconf.rb"
                raise "ruby extconf.rb failed" unless extconf @args 
                raise "make failed" unless make
                puts "Built extension in #{Dir.pwd}." if @config["verbose"] >= 4
            end
        end
        all_dirs_in(dname).each do |extdir| 
            build_extension(dname + '/' + extdir)
        end
    end
end


class Clean < HelperBase
    def initialize(subdirs = "", logger = nil)
        @args = subdirs 
        super(logger)
    end

    def run(installer)
        super
        make "distclean" if file_class.file? "Makefile"
        (@args || EXT_SUBDIRS).each do |dir|
            next unless file_class.dir? dir
            clean_extension(dir)
        end
        @fileops.rm_rf "rpa/#{@dest}"
    end

    def clean_extension(dir)
        dir_class.chdir(dir) do  #FIXME: windows?
            make "distclean" if file_class.file? "Makefile"
        end
        all_dirs_in(dir).each do |extdir|
            clean_extension(dir + '/' + extdir)
        end
    end
end

# compress examples, docs, etc
# according to policy
class Compress < HelperBase
end

class Extractpkg < HelperBase
    def run(installer)
        super
        return if @config["build"]   # build only
        meta = installer.metadata
        pkgfile = meta["name"] + '_' + meta["version"] + '_' +
            meta["platform"] + '.rpa'
        repos = RPA::LocalInstallation.instance(@config)
        puts "Extracting package #{pkgfile}." if @config["verbose"] >= 4
        repos.force_transacted_install_package(pkgfile)
    end
end

class Fixperms < HelperBase
    require 'find'
    def run(installer)
        find_class.find("rpa/#{@dest}") do |f|
            is_bin = /\Arpa\/#{@dest}\/bin\//.match(f)
            is_dir = file_class.dir?(f)
            mode = case
            when is_dir || is_bin
                0755
            else
                0644
            end
            @fileops.chmod mode, f
        end
    end
end

class Fixshebangs < HelperBase
    SHEBANG_RE = /\A\#!\s*\S*ruby\S*/

    # based on setup.rb's
    def fix_shebang(path)
        # modify: #!/usr/bin/ruby
        # modify: #! /usr/bin/ruby
        # modify: #!ruby
        # not modify: #!/usr/bin/env ruby
        tmpfile = path + '.tmp'
        begin
            file_class.open(path) {|r|
                file_class.open(tmpfile, 'w', 0755) {|w|
                    first = r.gets
                    return unless SHEBANG_RE =~ first
                    w.print first.sub(SHEBANG_RE, '#!' +
                                      @config['ruby-prog'])
                    w.write r.read
                }
            }
            @fileops.mv tmpfile, path
            puts "Fixed shebang in #{path}." if @config["verbose"] >= 4
        ensure
            @fileops.rm_f tmpfile if File.exist?(tmpfile)
        end
    end

    def run(installer)
        super
        all_files_in("rpa/#{@dest}/bin").each do |fname|
            fix_shebang "rpa/#{@dest}/bin/#{fname}"
        end
    end

end

class InstallStuffBase < HelperBase
    def initialize(filesordir = nil, dstsubdir = nil, strip = false, recursive = true,
                   logger = nil)
        #TODO: use named params?
        @filesordirs = filesordir
        @dstsubdir = dstsubdir
        @recursive = recursive
        if strip && (!filesordir || !filesordir.kind_of?(Array))
            @strip = filesordir
        else
            @strip = nil
        end
        super(logger)
    end

    def run(installer)
        super
        do_copy(installer)
    end

    def do_copy(installer, base_destdir = nil)
        base_destdir ||= default_base_destdir(@config, installer)
        if @filesordirs && Array === @filesordirs  # ugh
            destdir = File.join(base_destdir, @dstsubdir || "")
            @filesordirs.each do |f|
                install_file(f, destdir)
            end
        else
            dir = @filesordirs || default_srcdir(@config, installer)
            copy_dir(dir, dir, installer, base_destdir) if file_class.dir? dir
        end
    end

    def copy_dir(dname, strip, installer, base_destdir = nil)
        base_destdir ||= default_base_destdir(@config, installer)
        all_files_in(dname).each do |fname|
            if @strip
                dst = dname.sub(/#{Regexp.escape(@strip)}/, "")#.split('/')[1..-1].join('/')
                destdir = File.join(base_destdir, (@dstsubdir || ""), dst)
            else
                destdir = File.join(base_destdir, (@dstsubdir || ""), 
                                    dname.sub(/#{Regexp.escape(strip)}/, ""))
            end
            filename = File.join(dname, fname)
            install_file(filename, destdir) if file_selected? filename
        end
        return unless @recursive
        all_dirs_in(dname).each do |subdname|
            next if dname == "." && subdname == "rpa"
            copy_dir(dname + "/" + subdname, strip, installer, base_destdir)
        end
    end

    def install_file(fname, destdir)
        @fileops.mkdir_p "rpa/#{@dest}/#{destdir}"
        @fileops.install("#{fname}", 
                         "rpa/#{@dest}/#{destdir}", :mode => file_mode(fname))
    end

    def default_srcdir(config, installer)
        self.class.default_srcdir(config, installer) 
    end
    
    def default_base_destdir(config, installer)
        self.class.default_base_destdir(config, installer) 
    end
        
    def self.default_srcdir(config, installer); raise "Redefine me!" end
    def self.default_base_destdir(config, installer); raise "Redefine me!" end
    def file_mode(filename)
        0644
    end

    def file_selected?(fname)
        true
    end

end


class Installchangelogs < HelperBase
end

class Installdata < InstallStuffBase
    def self.default_srcdir(config, installer)
        "data" 
    end
    def self.default_base_destdir(config, installer)
        "share"
    end
end

class Installdependencies < HelperBase
    def run(installer)
        super
        repos = RPA::LocalInstallation.instance(@config)
        RPA::Install.auto_install = false

        meta = installer.metadata
        #puts "Package #{meta["name"]} depends on #{meta["requires"].inspect}"
        name = meta["name"]
        deps = installer.metadata["requires"] || []
        if @config["build"]
            if @config["verbose"] >= 4 && deps.size != 0
                puts "Building dependencies #{deps.join(' ')}."  
            end
            deps.each do |port|
                repos.build(port) 
            end
        else
            if @config["verbose"] >= 4 && deps.size != 0
                puts "Installing dependencies #{deps.join(' ')}." 
            end
            deps.each do |port|
                repos.install(port, name) 
            end
        end
    end
end

#TODO: refactor
class Installpredependencies < HelperBase
    def run(installer)
        super
        repos = RPA::LocalInstallation.instance(@config)
        RPA::Install.auto_install = false

        meta = installer.metadata
        name = meta["name"]
        deps = meta["build_requires"] || []
        if @config["verbose"] >= 4 && deps.size != 0
            puts "Installing pre-dependencies #{deps.join(' ')}." 
        end
        deps.each do |port|
           # we specify a revdep, which it really isn't, but it doesn't
           # matter cause the build_required pkg isn't in the requires so
           # it won't be marked in the GC phase 
           repos.install(port, name) 
        end
    end
end


class Installdocs < InstallStuffBase
    def self.default_srcdir(config, installer)
        "doc" 
    end
    def self.default_base_destdir(config, installer)
        "share/doc/rpa#{RPA::VERSION}/#{installer.metadata["name"]}"
    end
end

class Installexamples < InstallStuffBase
    def self.default_srcdir(config, installer)
        "doc/examples" 
    end

    def self.default_base_destdir(config, installer)
        "share/doc/rpa#{RPA::VERSION}/#{installer.metadata["name"]}/examples"
    end
end

class Installexecutables < InstallStuffBase
    def default_srcdir(config, installer)
        "bin" 
    end
    def default_base_destdir(config, installer)
       "bin"
    end
    require 'rbconfig'
    if ::Config::CONFIG["arch"] =~ /dos|win32|mingw/i
        def install_file(fname, destdir)
            @fileops.mkdir_p "rpa/#{@dest}/#{destdir}"
            @fileops.install("#{fname}", 
                             "rpa/#{@dest}/#{destdir}", :mode => file_mode(fname))
            File.open("rpa/#{@dest}/#{destdir}/#{File.basename(fname)}.bat", "w") do |f|
                ruby = ::Config::CONFIG['ruby_install_name'] + 
                    ::Config::CONFIG['EXEEXT']
                bindir = ::Config::CONFIG["bindir"]
                ruby = File.join(bindir, ruby).gsub(/\//,"\\")
                target = File.join(@config["prefix"], destdir,
                                   File.basename(fname))
                wtarget = target.gsub(/\//,"\\")
                f.puts "@#{ruby} #{wtarget} %1 %2 %3 %4 %5 %6 %7 %8 %9"
            end
        end
    end
end

class Installextensions < InstallStuffBase
    def self.default_srcdir(config, installer)
        "ext" 
    end

    def self.default_base_destdir(config, installer)
        sitearchdir = ::Config::CONFIG["sitearchdir"]
        sitearchdir.gsub(/^#{::Config::CONFIG["prefix"]}/, "")
    end

    def file_selected? name
        DLEXT.match name
    end
end

class Installman < HelperBase
end

class Installmetadata < HelperBase
    def run(installer)
        super
        require 'yaml'
        require 'yaml/syck'
        #TODO: decide on format, maybe remove installmetadata
        #      altogether and use buildpackage
        @fileops.mkdir_p "rpa/#{@dest}/RPA"
        file_class.open("rpa/#{@dest}/RPA/metadata", "w") do |f|
            f.write installer.metadata.to_yaml
        end
    end
end

class Installmodules < InstallStuffBase
    require 'rbconfig'
    def run(installer)
        super
        sitelibdir = ::Config::CONFIG["sitelibdir"]
        sitelibdir.gsub!(/^#{Regexp.escape @config["prefix"]}/, "")
        do_copy(installer, sitelibdir)
    end
    
    def default_srcdir(config, installer)
        "lib" 
    end
    def default_base_destdir(config, installer)
        config["sitelibdir"]
    end
end

class Installrdoc < HelperBase
    require 'rdoc/rdoc'
    require 'stringio'
    require 'rbconfig'
    IS_BROKEN_WINDOWS = ::Config::CONFIG["arch"] =~ /msdos|win32|mingw/i
    
    def initialize(args = nil, logger = nil)
        args = ["lib"] if args == nil || args == []
        @args = args
        super(logger)
    end
    
    def run(installer)
        super
        # non op if none of the specified files exist
        #FIXME: do this properly
        return unless @args.any?{|x| File.dir?(x) || File.file?(x)}

        #FIXME: RDoc's programmatic interface is broken, broken, broken
        #rdoc = RDoc::RDoc.new
        base = Installdocs.default_base_destdir(@config, installer)
        if (system(File.join(::Config::CONFIG["bindir"], "rdoc1.8"), "-v") rescue false)
            rdoc_path = File.join(::Config::CONFIG["bindir"], "rdoc1.8")
        else
            rdoc_path = File.join(::Config::CONFIG["bindir"], "rdoc")
        end

        if IS_BROKEN_WINDOWS
                ruby = ::Config::CONFIG['ruby_install_name'] +
                    ::Config::CONFIG['EXEEXT']
                bindir = ::Config::CONFIG["bindir"]
                ruby = File.join(bindir, ruby).gsub(/\//,"\\")
                rdoc_path.gsub!(/\//, "\\") 
        end
 
        # RDoc doesn't behave properly when we don't pass an absolute path
        # here
        outdir = File.join(Dir.pwd, "rpa", @dest, base, "ri")
        outdir.gsub!(/\//, "\\") if IS_BROKEN_WINDOWS
        args = @args + ["-r", "-q", "-o", outdir]

        puts "Generating RI data files." if @config["verbose"] >= 2
        strio = StringIO.new
        $stderr = strio
        # RDoc shows a lot of crap when an exception is raised
        begin
            if IS_BROKEN_WINDOWS
                unless (system(ruby, rdoc_path, *args) rescue false)
                    puts "WARNING: RI datafile generation failed" if @config["verbose"] >= 2
                end
            else
                unless (system(rdoc_path, *args) rescue false)
                    puts "WARNING: RI datafile generation failed" if @config["verbose"] >= 2
                end
            end
            #rdoc.document(args)
        ensure
            $stderr = STDERR
        end
    
        outdir = File.join("rpa", @dest, base, "rdoc")
        outdir.gsub!(/\//, "\\") if IS_BROKEN_WINDOWS
        args = @args + ["-q", "-o", outdir]

        puts "Generating RDoc HTML documentation." if @config["verbose"] >= 2
        #rdoc = RDoc::RDoc.new
        strio = StringIO.new
        $stderr = strio
        # RDoc shows a lot of crap when an exception is raised
        begin
            if IS_BROKEN_WINDOWS
                unless (system(ruby, rdoc_path, *args) rescue false)
                    puts "WARNING: RDoc datafile generation failed" if @config["verbose"] >= 2
                end
            else
                unless (system(rdoc_path, *args) rescue false)
                    puts "WARNING: RDoc datafile generation failed" if @config["verbose"] >= 2
                end
            end
            #rdoc.document(args)
        ensure
            $stderr = STDERR
        end
    end
end

class Installtests < InstallStuffBase
    def self.default_srcdir(config, installer)
        "test"
    end

    def self.default_base_destdir(config, installer)
        File.join(config["rpa-base"], "tests", installer.metadata["name"])
    end
end

class Md5sums < HelperBase
    def run(installer)
        super
        require 'digest/md5'
        @md5 = installer.metadata["md5sums"] = {}
        @files = installer.metadata["files"] = []
        @dirs = installer.metadata["dirs"] = []
        puts "Calculating MD5 digests." if @config["verbose"] >= 4
        all_dirs_in("rpa/" + @dest).each do |dname|
            process_dir(dname)
        end
    end

    def process_dir(dname)
        @dirs << dname
        all_files_in("rpa/#{@dest}/#{dname}").each do |fname|
            md5 = Digest::MD5.new
            file_class.open("rpa/#{@dest}/#{dname}/#{fname}", "rb") do |f|
                md5 << f.read(4096) until f.eof?
            end     
            storedname = "#{dname}/#{fname}"
            @md5[storedname] = md5.hexdigest
            @files << storedname
        end
        all_dirs_in("rpa/#{@dest}/#{dname}").each do |subdirname|
            process_dir("#{dname}/#{subdirname}")
        end
    end
end

class Moduledeps < HelperBase
end

class RunUnitTests < HelperBase
    class UnitTestFailure < StandardError; end
    def run(installer)
        super
        unless @config["no-tests"] #FIXME: "negative logic" sucks
            puts "WARNING: skipping unit tests." if @config["verbose"] >= 4
            return
        end
        return if @config["build"]
        @meta = installer.metadata
        reldir = Installtests.default_base_destdir(@config, installer)
        dir = File.join(@config["prefix"], reldir)
        return unless File.dir? dir
        puts "Running unit tests for #{@meta["name"]}." if @config["verbose"] >= 2
        Dir.chdir(dir) do 
            if @meta["test_suite"]
                begin
                    oldverbose = $VERBOSE
                    $VERBOSE = nil
                    #FIXME: kludge
                    suite = @meta["test_suite"]
                    if File.exist? suite
                        run_testfile(suite)
                    else
                        run_testfile(File.basename(suite))
                    end
                ensure
                    $VERBOSE = oldverbose
                end
            else
                Dir["*.rb"].sort.each do |fname|
                    begin
                        oldverbose = $VERBOSE
                        $VERBOSE = nil
                        run_testfile(fname)
                    ensure
                        $VERBOSE = oldverbose
                    end
                end
            end
        end
    end
    
    def run_testfile(fname)
        require 'test/unit/ui/console/testrunner'
        require 'test/unit/ui/testrunnerutilities'
        old = get_testcases
        load fname
        testcases = get_testcases - old
        testcases.each do |testcase| 
            ret = Test::Unit::UI::Console::TestRunner.run testcase, 
                Test::Unit::UI::SILENT
            unless ret.passed?
                raise UnitTestFailure, "Testcase #{testcase} in #{fname} failed. " +
                    "#{ret.error_count} errors, #{ret.failure_count} failures."
            end
        end
    end

    def get_testcases
        testcases = []
        ObjectSpace.each_object(Class) do |x|
            testcases << x if x.ancestors.include? Test::Unit::TestCase
        end
        testcases
    end
end

class Task < HelperBase
    def initialize(logger = nil, &block)
        super
        @block = block
    end

    def run(installer)
        super
        @installer = installer
        instance_eval(&@block)
    end
end

class Testversion < HelperBase
end

# convenience
helpers = self.constants.map{|x| const_get x}.
    select{|x| Class === x}
(helpers - [HelperBase, InstallStuffBase]).each do |klass|
    mname = klass.to_s.downcase.split(/::/).last
    # what we really want is 
    # define_method(mname) { |*args| klass.new(*args) }
    # but blocks don't accept blocks (yet), so we have to make it dirty
    module_eval <<-EOF
        def #{mname}(*args, &block)
            #{klass.to_s}.new(*args, &block)
        end
    EOF

end
end # Helper
end # RPA
