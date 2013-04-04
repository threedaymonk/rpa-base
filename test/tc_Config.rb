
require 'rpa/config'
require 'test/unit'

class TC_Config < Test::Unit::TestCase
    include RPA

    def setup
        @argv = %w[--verbose 2 --prefix foobar --so-dir bla --sitelibdir foo
                  --make-prog mymake --ruby-prog myruby]
        @vals = %w[2 foobar bla foo mymake myruby]
        @vals2 = [2] + %w[foobar bla foo mymake myruby]
        @names = %w{verbose prefix so-dir sitelibdir make-prog ruby-prog}
    end

    def test_parse
        options = Config.parse(@argv)
        i = 0
        @vals.each_with_index do |val, i|
            assert_equal val, options["#{@names[i]}"] 
        end
        assert_equal 5, i
    end

    def test_new
        config = Config.new(@argv)
        i = 0
        @vals2.each_with_index do |val, i|
            assert_equal val, config["#{@names[i]}"] 
        end
        assert_equal 5, i
    end

    def test_ref
        config = Config.new(@argv)
        %w{sdf sf foo bar}.each{|bog| assert_raises(RuntimeError){config[bog]} }
    end

    def test_configfile_raises_exception_if_not_found
        argv = %w{--configfile badbadbad}
        assert_raises(RuntimeError) { Config.new(argv) }
        argv = %w{--configfile badbadbad}
        assert_raises(RuntimeError) { Config.parse(argv) }
    end

    def test_determinant_values
        c = Config.new @argv
        assert_kind_of Array, c.determinant_values
    end
end

