#
# Copyright (C) 2004 Mauricio Julio Fernández Pradier
# See LICENSE.txt for additional licensing information.
#

require 'rbconfig'

module RPA
    RPABASE_VERSION = "0.2.0"
    VERSION = "0.0"
    module Defaults

        fix_path = proc do |dname|
            prefix = ::Config::CONFIG["prefix"]
            dname.sub(/\A#{Regexp.escape(prefix)}/o,
                      "").sub(/\A\//, "")
        end

        PREFIX = ::Config::CONFIG["prefix"]
        RPA_BASE = fix_path.call File.join(::Config::CONFIG['libdir'], 'ruby', 
                                               "rpa#{RPA::VERSION}")
        SITELIBDIR = File.join(RPA_BASE, ::Config::CONFIG['ruby_version'])
        SO_DIR = File.join(SITELIBDIR, ::Config::CONFIG["target"])
    end
end
