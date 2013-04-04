#
# Copyright (C) 2004 Mauricio Julio Fernández Pradier
# See LICENSE.txt for additional licensing information.
#

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

module RPA
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
