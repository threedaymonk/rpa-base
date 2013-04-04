
require 'rpa/base'
require 'test/unit'

module SetMethod
    def set_meth(meth, &block)
        class << self; self end.send(:define_method, meth, &block) 
    end
end

class CheapConf < Hash
    def determinant_values
        self
    end
end

class TestLocalInstallation < RPA::LocalInstallation
    include SetMethod
end

class TC_LocalInstallation < Test::Unit::TestCase

    def setup
        @prefix = Dir.pwd  
        @base = "__test-rpa__#{rand(1000)}" 
        @config = CheapConf.new
        @config["prefix"] =  @prefix
        @config["rpa-base"] = @base
        @config["base-dirs"] = ["#{@base}"]
        @config["verbose"] = 0
        @repos = TestLocalInstallation.instance(@config)
        @metadata = { "name" => "barbar", "foo" => "foo 123", 
                "baz" => "sfaddasd", "blah" => "blah", 
                "files" => ["a", "a/b", "c"] }
        @journal = File.join(@config["prefix"], @config["rpa-base"],
                             "transactions")
    end

    def teardown
        FileUtils.rm_rf @base
    end

    def test_register_metadata
        register_metadata
    end

    def test_retrieve_metadata
        register_metadata
        assert_equal(@metadata, @repos.retrieve_metadata(@metadata["name"]))
    end

    def test_remove_metadata
        register_metadata
        @repos.remove_metadata @metadata["name"]
        assert_equal(nil, @repos.retrieve_metadata(@metadata["name"]))
        dirname = File.join(@prefix, @base, "info")
        fname = File.join dirname, "barbar"
        assert(!File.file?(fname))
        instfile = File.join(@prefix, @base, "installed")
        assert File.file?(instfile)
        assert_equal([], YAML.load(File.read(instfile)))
    end

    def register_metadata
        require 'yaml'
        require 'fileutils'

        @repos.register_metadata(@metadata)
        dirname = File.join(@prefix, @base, "info")
        fname = File.join dirname, "barbar"
        assert(File.dir?(dirname))
        assert(File.file?(fname))
        assert_equal(@metadata, YAML.load(File.read(fname)))
        instfile = File.join(@prefix, @base, "installed")
        assert File.file?(instfile)
        assert_equal(["barbar"], YAML.load(File.read(instfile)))
    end

    def test_installed_files
        @repos.register_metadata @metadata
        result = {}
        @metadata["files"].each{|k| result[k] = "barbar"}
        assert_equal(result, @repos.installed_files)
        @repos.remove_metadata @metadata["name"]
    end
    
    def test_conflicts_files
        @repos.register_metadata @metadata
        assert_equal("barbar", @repos.conflicts?("a"))
        assert_equal("barbar", @repos.conflicts?("a/b"))
        assert(!@repos.conflicts?("aasd"))
        @repos.remove_metadata @metadata["name"]
    end

    def test_installed_ports
        assert_equal [], @repos.installed_ports
        begin
            @repos.register_metadata @metadata
            assert_equal [@metadata["name"]], @repos.installed_ports
        ensure
            @repos.remove_metadata @metadata["name"]
        end
    end

    def test_transaction_uses_journal
        require 'yaml'

        @repos.transaction(@metadata) do 
            assert_equal(true, File.exist?(@journal))
            dat = YAML.load File.read(@journal)
            assert_kind_of Array, dat
            assert_equal 1, dat.size
            assert_kind_of RPA::PackageState, dat[0]
        end
        dat = YAML.load File.read(@journal)
        assert_kind_of Array, dat
        assert_equal 1, dat.size # stays until commit
    end

    class MockPackageState 
        attr_reader :li, :meta
        class << self; attr_accessor :restore_proc end
        def initialize(localinst, meta, lightweight)
            #@li = localinst
            @meta = meta
        end

        def restore(a)
            self.class.restore_proc.call a
        end

        def cleanup
        end
    end

    class TestRollback < TestLocalInstallation
        attr_writer :packagestate_class
        
        def packagestate_class
            MockPackageState
        end
    end

    def test_transaction_rolls_back_on_error
        exception_klass = Class.new(Exception)
        restored = false
        config = @config.clone
        config["bleh"] = true  # just to make it different so instance creates
                               # a new object
        repos = TestRollback.instance config
        MockPackageState.restore_proc = lambda {|li| restored = true}
        assert_raises(exception_klass) do
            repos.transaction(@metadata) do 
                raise exception_klass, "unit testing"
            end
        end
        assert_equal(true, restored)
    end
    
    def test_commit_works_ok
        restored = false
        config = @config.clone
        # just to make it different so instance creates a new object
        config["bleh_commit_works_ok"] = true  
        MockPackageState.restore_proc = lambda {|li| restored = li}
        repos = TestRollback.instance config
        repos.transaction(@metadata) { }
        repos.commit
        assert_equal(false, restored)
        assert_equal(true, File.exist?(@journal))
        dat = YAML.load File.read(@journal)
        assert_kind_of Array, dat
        assert_equal 0, dat.size
    end

    def test_apply_pending_rollback_works
        require 'fileutils'
        restored = false
        config = @config.clone
        # just to make it different so instance creates a new object
        config["bleh_apply_pending_no_journal"] = true  
        MockPackageState.restore_proc = lambda {|li| restored = li}
        FileUtils.rm_rf @journal
        assert_nothing_raised do
            repos = TestRollback.instance config
            repos.apply_pending_rollbacks 
        end
        File.open(@journal, "w") { |f| f.write YAML.dump([]) }
        assert_nothing_raised do
            repos = TestRollback.instance config
            repos.apply_pending_rollbacks 
        end
        repos = TestRollback.instance config
        state = MockPackageState.new(repos, "abcdef", false)
        File.open(@journal, "w") { |f| f.write YAML.dump([state]) }
        assert_nothing_raised { repos.apply_pending_rollbacks }
        assert_equal(restored, repos)
        assert_equal(true, File.exist?(@journal))
        dat = YAML.load File.read(@journal)
        assert_kind_of Array, dat
        assert_equal 0, dat.size
    end
end

class TC_LocalInstallation2 < Test::Unit::TestCase
    require 'timeout'
    if defined? Rcov  # ::COVERAGE__ # would fail on 1.9
        ITERATIONS = 10
    else
        ITERATIONS = 100
    end
    require 'fileutils'
    class CheapConf < Hash
        def determinant_values
            self
        end
    end
    def setup
        @prefix = Dir.pwd  
        @base = "__test-rpa__#{rand(1000)}" 
        @config = CheapConf.new
        @config["prefix"] =  @prefix
        @config["rpa-base"] = @base
        @config["base-dirs"] = ["#{@base}"]
        @config["verbose"] = 0

        @linst = TestLocalInstallation.instance(@config)
        @metadata_pre = {
            "name" => "test", "version" => "0.0-1", "description" => "blah",
                "classification" => "Top", 
                "files" => ["#{@base}/1.8/foo.rb", "#{@base}/1.8/bar.rb"],
                "dirs" => ["#{@base}/1.8", @base],
                "platform" => "i686-linux", "md5sums" => {} }
        @metadata_post = {
            "name" => "test", "version" => "0.0-2", "description" => "blah",
                "classification" => "Top", 
                "files" => ["#{@base}/1.8/foo2.rb", "#{@base}/1.8/bar.rb"],
                "dirs" => ["#{@base}/1.8", @base],
                "platform" => "i686-linux", "md5sums" => {}}
        require 'digest/md5'
        premd5 = Digest::MD5.hexdigest "0.0-1"
        postmd5 = Digest::MD5.hexdigest "0.0-2"
        @metadata_post["md5sums"]["#{@base}/1.8/foo2.rb"] = postmd5
        @metadata_post["md5sums"]["#{@base}/1.8/bar.rb"] = postmd5
        @metadata_pre["md5sums"]["#{@base}/1.8/foo.rb"] = premd5
        @metadata_pre["md5sums"]["#{@base}/1.8/bar.rb"] = premd5

        @flambda = lambda do |*args| 
            fname = File.join(@base, *args)
            FileUtils.mkdir_p File.dirname(fname)
            fname
        end
    end

    def teardown
        FileUtils.rm_rf @base
    end

    def create_initial_state
        # create the 'initial state' with a sample pkg installed
        FileUtils.rm_rf @base
        @linst = TestLocalInstallation.instance(@config)
        begin
            @linst.register_metadata @metadata_pre
        rescue NotImplementedError
            retry
        end
        # file contents, anything will do
        File.open(@flambda["1.8", "foo.rb"], "w") { |f| f.write @metadata_pre["version"] }
        File.open(@flambda["1.8", "bar.rb"], "w") { |f| f.write @metadata_pre["version"] }
    end

    def set_new_state(time, &block)
        Timeout::timeout(2.5 * time * rand) { block.call }
    end

    def assert_init_state_good
        meta = @linst.retrieve_metadata("test") 
        assert_not_nil meta
        @metadata_pre.each {|k,v| assert_equal(v, meta[k]) }
        fname = File.join(@base, "1.8", "foo.rb")
        fname2 = File.join(@base, "1.8", "bar.rb")
        assert File.exist?(fname)
        assert File.exist?(fname2)
        assert_equal(@metadata_pre["version"], File.read(fname))
        assert_equal(@metadata_pre["version"], File.read(fname2))
        assert !File.exist?(File.join(@base, "1.8", "foo2.rb"))
        #print "B"
        #$stdout.flush
    end

    def assert_pkg_upgraded
        meta = @linst.retrieve_metadata("test") 
        @metadata_post.each {|k,v| assert_equal(v, meta[k]) }
        fname = File.join(@base, "1.8", "foo2.rb")
        fname2 = File.join(@base, "1.8", "bar.rb")
        assert File.exist?(fname)
        assert File.exist?(fname2)
        assert_equal(@metadata_post["version"], File.read(fname))
        assert_equal(@metadata_post["version"], File.read(fname2))
        assert !File.exist?(File.join(@base, "1.8", "foo.rb"))
        #print "U"
        #$stdout.flush
    end

    def test_install_transaction
        assert_lambda = lambda do
            oldfname = File.join(@base, "1.8", "foo.rb")
            if File.exist? oldfname
                assert_init_state_good
            else
                assert_pkg_upgraded
            end
        end

        perform_transaction(@metadata_post, assert_lambda) do
            RPA::Uninstaller.new(@metadata_pre, @config).run
            sleep 0.02
            @linst.remove_metadata @metadata_pre["name"]
            sleep 0.02
            File.open(@flambda["1.8", "foo2.rb"], "w") do |f|
                f.write @metadata_post["version"] 
            end
            sleep 0.02
            File.open(@flambda["1.8", "bar.rb"], "w") do |f|
                f.write @metadata_post["version"] 
            end
            sleep 0.02
            @linst.register_metadata @metadata_post
        end
    end

    def assert_nothing_installed
        meta = @linst.retrieve_metadata("test") 
        assert_equal(nil, meta)
        fname = File.join(@base, "1.8", "foo.rb")
        fname2 = File.join(@base, "1.8", "bar.rb")
        assert !File.exist?(fname)
        assert !File.exist?(fname2)
        #print "N"
        #$stdout.flush
    end

    def test_uninstall_transaction
        assert_lambda = lambda do
            oldfname = File.join(@base, "1.8", "foo.rb")
            if File.exist? oldfname
                assert_init_state_good
            else
                assert_nothing_installed
            end
        end

        perform_transaction(@metadata_pre, assert_lambda) do
            RPA::Uninstaller.new(@metadata_pre, @config).run
            sleep 0.02
            @linst.remove_metadata @metadata_pre["name"]
        end
    end

    def perform_transaction(dest_metadata, assert_proc, &block)
        require 'stringio'
        return if ARGV[0] == 'fast'
        # first estimate the time we need
        samples = 10
        total = []
        samples.times do
            create_initial_state
            t = Time.new
            set_new_state(0.0, &block)
            total << Time.new - t
        end
        avg = total.inject{|a,b| a+b} / total.size
        ITERATIONS.times do |i|
            #puts "10 more..." if (i % 10) == 0
            create_initial_state
            # the following will interrupt the mutator while it's doing
            # its job
            begin
                begin
                    dummyio = Class.new do
                        def write(*a); end
                        def puts(*a); end
                        def method_missing(*a); end
                    end.new
                    $stdout = dummyio
                    @linst.transaction(dest_metadata) do 
                        set_new_state(avg, &block)
                    end
                    @linst.commit
                rescue Exception
                ensure
                    $stdout = STDOUT
                end
            end
            @linst.apply_pending_rollbacks
            assert_proc.call
        end
    end
end


# broken test case :(
class TC_LocalInstallation_higher_level_stuff #< Test::Unit::TestCase
    require 'fileutils'

    @count = 0
    def self.count; @count += 1 end
    require 'ostruct'

    def setup
        @prefix = Dir.pwd  
        @base = "__test-rpa__#{rand(1000)}" 
        @config = CheapConf.new
        @config["prefix"] =  @prefix
        @config["rpa-base"] = @base
        @config["base-dirs"] = ["#{@base}"]
        @config["verbose"] = 0
        @config["foo"] = "test_higher_level_stuff"
        # so that each test method gets a new object
        @config["randomizer"] = self.class.count

        @linst = TestLocalInstallation.instance(@config)
        @metadata = { "name" => "test", "version" => "0.0-1" }
    end

    def teardown
        FileUtils.rm_rf @base
    end

    def test_install_port
        fooinfo, portinfo = make_fake_port_info
        @linst.instance_variable_set("@repositoryinfo", fooinfo)
        FileUtils.mkdir portinfo.download
        # just create an empty file
        File.open(File.join(portinfo.download, "install.rb"), "w"){|f| }
        installer = Struct.new(:metadata, :config, :package_file).new({}, nil,
                                                                      "FILE.rpa")
        done = false
        class << installer; self end.send(:define_method, :run){done = true}
        RPA::Install.children << installer
        pkg_cache = Object.new
        pkg_file = nil
        class << pkg_cache; self end.send(:define_method, :store_package) {|pkg_file|}
        class << pkg_cache; def retrieve_package x; end end
        @linst.instance_variable_set("@packagecache", pkg_cache)
        assert_nothing_raised { @linst.install 'test', 'foobarbaz' }
        assert_equal(true, done)
        assert_equal("FILE.rpa", pkg_file)
    ensure
        FileUtils.rm_rf portinfo.download if portinfo.download
    end

    def test_install_port_when_updating
        metadata = @metadata
        @linst.set_meth(:retrieve_metadata){|a| metadata }
        def @linst.transaction(*a, &block); block.call end 
        registered_name = nil
        @linst.set_meth(:register_as_wanted){|name| registered_name = name}
        fooinfo, portinfo = make_fake_port_info
        @linst.instance_variable_set("@repositoryinfo", fooinfo)
        # now w/ revdeps, so the port *won't* be marked as wanted
        assert_nothing_raised { @linst.install @metadata['name'], 'bar' }
        assert_equal(nil, registered_name)
        # now w/o rev deps, so the port will be marked as wanted
        assert_nothing_raised { @linst.install @metadata['name'] }
        assert_equal(@metadata['name'], registered_name)
    end
    
    private
    def make_fake_port_info
        fooinfo = OpenStruct.new
        portinfo = OpenStruct.new
        portinfo.metadata = @metadata
        portinfo.download = "__test_install_port#{rand(1000)}"
        fooinfo.ports = [portinfo]
        return fooinfo, portinfo
    end
end

class TC_Port < Test::Unit::TestCase
    class TestPort < RPA::Port
        include SetMethod
    end

    def setup
        @prefix = Dir.pwd  
        @base = "__test-rpa__#{rand(1000)}" 
        @dldest = "__test-rpa__dl_#{rand(1000)}" 
        @file = File.join(@base, "foo.rps")
        FileUtils.mkdir @base
        File.open(@file, "w") do |f| 
            f.write(('aa'..'zz').to_a.join(''))
        end
        @metadata = {'name' => 'foo'}
        @port = TestPort.new @metadata, @file, {'verbose' => 0}
    end

    def teardown
        FileUtils.rm_rf @base
    end

    def test_initialization
        assert_equal(@metadata, @port.metadata)
        assert_equal(@file, @port.url)
    end

    def test_download
        r_pkg, r_destdir = nil, nil
        @port.set_meth(:extract){|pkg, destdir| r_pkg, r_destdir = pkg, destdir}
        @port.download @dldest
        assert_equal(File.join(@dldest, 'foo'), r_destdir)
    end
end


class TC_RepositoryInfo < Test::Unit::TestCase
    require 'yaml'
    require 'ostruct'

    @count = 0
    def self.count; @count += 1 end

    def setup
        @prefix = Dir.pwd  
        @base = "__test-rpa__#{rand(1000)}" 
        FileUtils.mkdir @base
        @config = CheapConf.new
        @config["prefix"] =  @prefix
        @config["rpa-base"] = @base
        @config["base-dirs"] = ["#{@base}"]
        @config["verbose"] = 0
        @config["foo"] = "test_repository_info"
        # so that each test method gets a new object
        @config["randomizer"] = self.class.count
        @rinfo = RPA::RepositoryInfo.instance @config
    end

    def teardown
        FileUtils.rm_rf @base
    end

    def test_update
        file = File.join(@prefix, @base, "ports.info")
        info = []
        ('a'..'c').each do |x|
            info << {'url' => x, 'metadata' => {'name' => x}}
        end
        File.open(file, "w"){|f| f.puts(info.to_yaml) }
        @rinfo.instance_variable_set "@sources", ["file://#{file}"]
        @rinfo.update
        assert_kind_of(RPA::Port, @rinfo.ports.first)
        assert_kind_of(RPA::Port, @rinfo.ports.last)
    end
end

