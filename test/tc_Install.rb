
require 'test/unit'
require 'rpa/install'

class TC_StandaloneInheritanceMagic < Test::Unit::TestCase
    def setup
        RPA::Install.children = []
        RPA::Install.auto_install = false
    end

    def test_inherited_magic
        assert_equal([], RPA::Install.children)
        a = Class.new(RPA::Install::PureRubyLibrary)
        assert_equal([a], RPA::Install.children)
    end

    def test_run
        record = ""
        tasks = (0..9).map do |i| 
            o = ""; class << o; self end.send(:define_method, :run) { record << "#{i}"}
            o
        end
        kl = Class.new(RPA::Install::PureRubyLibrary)
        kl.instance_eval do 
            @tasks = [tasks]
            @metadata = {'version' => '0.0-1', 'description' => '', 
                'classification' => ''}
        end
        c = RPA::Install.children.last
        c.config = {"debug" => false, "verbose" => 0}
        c.run
        assert_equal("0123456789", record)
    end

    def test_validation
        methods = %w{name version requires suggests classification description}
        class_maker = lambda do
            k = class << self; self end
            methods.each do |meth|
                k.send(:define_method, "validate_#{meth}") { throw meth.intern }
            end
        end
        kl = Class.new(RPA::Install::PureRubyLibrary, &class_maker) 
        tester = lambda do |name, param|
            kl.module_eval "#{name}(#{param.inspect})" 
        end
        methods.each { |m| assert_throws(m.intern){ tester[m, 'bar'] } }

        kl = Class.new(RPA::Install::PureRubyLibrary)
        %w{1bla Blah bla/bla}.each do |name|
            assert_raises(RuntimeError) { tester["name", name] }
        end
        %w{asda foo 0.1 0.1_12-1 0.a 0.a-1}.each do |name|
            assert_raises(RuntimeError) { tester["version", name] }
        end
        assert_raises(RuntimeError) { tester["classification", "bad"] }
        kl2 = Class.new(RPA::Install::PureRubyLibrary, &class_maker)
        assert_raises(RuntimeError) { kl2.run }
    end
    
    def test_inherited_hook_is_called
        called = false
        testPureRubyLibrary = Class.new(RPA::Install::Application) do
            class << self; self end.send(:define_method, :inherited_hook) do 
                called = true 
            end
        end
        assert_equal(true, called)
    end
end

class TC_InstallerClasses < Test::Unit::TestCase
    include RPA::Install
    def setup
        RPA::Install.children = []
        RPA::Install.auto_install = false
    end

    def test_tasks_array_looks_good
        [PureRubyLibrary, Application, FullInstaller].each do |klass|
            kl = Class.new(klass) { }
            tasks = kl.instance_variable_get "@tasks"
            tasks.each do |x|
                assert_kind_of(Array, x)
                x.each{|helper| assert_kind_of(RPA::Helper::HelperBase, helper)}
            end
        end
        assert true
    end

    def test_helper_collector
        [PureRubyLibrary, Application, FullInstaller].each do |klass|
            tester = self
            kl = Class.new(klass) do
                #TODO: fill me
            end
        end
    end
end
