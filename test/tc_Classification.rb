
require 'rpa/classification'
require 'test/unit'

class TC_Classification < Test::Unit::TestCase
    def setup
        oldverbose = $VERBOSE
        $VERBOSE = nil
        RPA::Classification.add("Test1", "simple test")
        RPA::Classification.add("Test2", "simple test") do
            add "Sub1", "sub1"
        end
        RPA::Classification.add("Test3", "simple test") do
            add("Sub1", "sub1") {
                add("Sub1a", "sub1a")
            }
        end
        RPA::Classification.add("Test4", "simple test") do
            add("Sub1", "sub1") {
                add "Sub1a", "sub1a"
                add "Sub1b", "sub1b"
            }
            add("Sub2", "sub2")
        end
    ensure
        $VERBOSE = oldverbose
    end
    
    def test_add_categories
        assert_kind_of(RPA::Classification::Category,
                       RPA::Classification::Top.Test1)
        assert_kind_of(RPA::Classification::Category,
                       RPA::Classification::Top.Test2.Sub1)
        assert_kind_of(RPA::Classification::Category,
                       RPA::Classification::Top.Test3.Sub1)
        assert_kind_of(RPA::Classification::Category,
                       RPA::Classification::Top.Test3.Sub1.Sub1a)
        assert_kind_of(RPA::Classification::Category,
                       RPA::Classification::Top.Test4.Sub1)
        assert_kind_of(RPA::Classification::Category,
                       RPA::Classification::Top.Test4.Sub1.Sub1a)
        assert_kind_of(RPA::Classification::Category,
                       RPA::Classification::Top.Test4.Sub1.Sub1b)
        assert_kind_of(RPA::Classification::Category,
                       RPA::Classification::Top.Test4.Sub2)
    end

    def test_subcategories_work
        assert_equal(RPA::Classification::Top.Test2.Sub1, 
                     RPA::Classification::Top.Test2.subcategories.last)
        assert_equal(RPA::Classification::Top.Test4.Sub1, 
                     RPA::Classification::Top.Test4.subcategories[0])
        assert_equal(RPA::Classification::Top.Test4.Sub2, 
                     RPA::Classification::Top.Test4.subcategories[1])
        assert_equal(RPA::Classification::Top.Test4.Sub1.Sub1a, 
                     RPA::Classification::Top.Test4.Sub1.subcategories[0])
        assert_equal(RPA::Classification::Top.Test4.Sub1.Sub1b, 
                     RPA::Classification::Top.Test4.Sub1.subcategories[1])
    end

    def test_metadata_is_registered_correctly
        assert_equal "simple test", RPA::Classification::Top.Test1.description
        assert_equal "simple test", RPA::Classification::Top.Test2.description
        assert_equal "simple test", RPA::Classification::Top.Test3.description
        assert_equal "simple test", RPA::Classification::Top.Test4.description
        assert_equal "sub1", RPA::Classification::Top.Test3.Sub1.description
        assert_equal "sub1a", RPA::Classification::Top.Test3.Sub1.Sub1a.description
        assert_equal "sub1", RPA::Classification::Top.Test4.Sub1.description
        assert_equal "sub1a", RPA::Classification::Top.Test4.Sub1.Sub1a.description
        assert_equal "sub1b", RPA::Classification::Top.Test4.Sub1.Sub1b.description
        assert_equal "sub2", RPA::Classification::Top.Test4.Sub2.description

        assert_equal "Test1", RPA::Classification::Top.Test1.name
        assert_equal "Test2", RPA::Classification::Top.Test2.name
        assert_equal "Test3", RPA::Classification::Top.Test3.name
        assert_equal "Test4", RPA::Classification::Top.Test4.name
        assert_equal "Sub1", RPA::Classification::Top.Test3.Sub1.name
        assert_equal "Sub1a", RPA::Classification::Top.Test3.Sub1.Sub1a.name
        assert_equal "Sub1", RPA::Classification::Top.Test4.Sub1.name
        assert_equal "Sub1a", RPA::Classification::Top.Test4.Sub1.Sub1a.name
        assert_equal "Sub1b", RPA::Classification::Top.Test4.Sub1.Sub1b.name
        assert_equal "Sub2", RPA::Classification::Top.Test4.Sub2.name
        
        assert_equal("Top.Test3.Sub1", 
                     RPA::Classification::Top.Test3.Sub1.long_name)
        assert_equal("Top.Test3.Sub1.Sub1a", 
                     RPA::Classification::Top.Test3.Sub1.Sub1a.long_name)
        assert_equal("Top.Test4.Sub1",
                     RPA::Classification::Top.Test4.Sub1.long_name)
        assert_equal("Top.Test4.Sub1.Sub1a",
                     RPA::Classification::Top.Test4.Sub1.Sub1a.long_name)
        assert_equal("Top.Test4.Sub1.Sub1b",
                     RPA::Classification::Top.Test4.Sub1.Sub1b.long_name)
        assert_equal("Top.Test4.Sub2",
                     RPA::Classification::Top.Test4.Sub2.long_name)
    end

    def test_parent
        assert_equal(RPA::Classification::Top,
                     RPA::Classification::Top.Test1.parent)
        assert_equal(RPA::Classification::Top,
                     RPA::Classification::Top.Test2.parent)
        assert_equal(RPA::Classification::Top,
                     RPA::Classification::Top.Test3.parent)
        assert_equal(RPA::Classification::Top,
                     RPA::Classification::Top.Test4.parent)
        assert_equal(RPA::Classification::Top.Test3, 
                     RPA::Classification::Top.Test3.Sub1.parent)
        assert_equal(RPA::Classification::Top.Test3.Sub1, 
                     RPA::Classification::Top.Test3.Sub1.Sub1a.parent)
        assert_equal(RPA::Classification::Top.Test4,
                     RPA::Classification::Top.Test4.Sub1.parent)
        assert_equal(RPA::Classification::Top.Test4.Sub1,
                     RPA::Classification::Top.Test4.Sub1.Sub1a.parent)
        assert_equal(RPA::Classification::Top.Test4.Sub1,
                     RPA::Classification::Top.Test4.Sub1.Sub1b.parent)
        assert_equal(RPA::Classification::Top.Test4,
                     RPA::Classification::Top.Test4.Sub2.parent)
    end
    
    def test_TOP_module
        %w{Test1 Test2 Test3 Test4}.each do |category|
            assert RPA::Classification::TOP.constants.include?(category)
        end
    end

end
