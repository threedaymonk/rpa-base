#
# Copyright (C) 2004 Mauricio Julio Fernández Pradier
# See LICENSE.txt for additional licensing information.
#

module RPA
    module Classification
        VERSION = "0"
        module TOP
        end
        class Category
            attr_reader :subcategories, :name, :description, :parent

            def initialize(name, parent, desc)
                @parent = parent
                @name = name
                @description = desc
                parent.register_child(name, self) if parent
                @subcategories = []
            end
            
            def register_child(name, child)
                class << self; self end.send(:define_method, name) { child }
                @subcategories << child
            end

            def add(name, desc, &block)
                c = self.class.new name, self, desc
                c.instance_eval(&block) if block
            end
            
            def long_name
                if parent
                    parent.long_name + "." + name
                else
                    name
                end
            end
        end
        
        Top = Category.new("Top", nil, "Top Level")
        def self.add(name, desc, &block)
            c = Category.new(name, RPA::Classification::Top, desc)
            TOP.const_set name, c
            c.instance_eval(&block) if block
        end

        add("Application", "Applications") {
            add "Admin", "Administration tools"
            add "Devel", "Development tools"
            add "Editor", "Editors -- only real ones please"
        }

        add("Documentation", "Documentation (non-Japanese OK too)") {
            add "Reference", "Reference documentation for developers"
        }
        add("Library", "Libraries") {
            add "Development", "Miscellaneous"
        }
    end
end
    
