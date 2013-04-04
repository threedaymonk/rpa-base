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

def self.fetch_file(config, src, &block)
    len = 0
    display_progress = lambda do |rec|
        done = 40 * rec / len
        bar = "" + "=" * done + " " * (40 - done)
        txt = "%03d%% [%s] #{len} bytes\r" % [100 * rec / len, bar]
        print txt
    end
    if %r{\Afile://}.match(src) || !%r{\A[a-z]+://}.match(src) 
        args = []
        src = src.gsub(%r{\Afile://}, "")
    else # remote
        if config["verbose"] >= 2
            args = [:content_length_proc => lambda{|len|},
                    :progress_proc => display_progress]
        else
            args = [{}]
        end
        if config["proxy"]
            args[-1][:proxy] = config["proxy"] 
        else
            args[-1][:proxy] = nil
        end
    end
    ret = nil
    open(src, "rb", *args) do |is|
        ret = yield is
        if !args.empty? and config["verbose"] >= 2
            puts
        end
    end
    ret
end

def self.mktemp(prefix, mkdir = true)
    prefix = prefix.gsub %r{/}, "_"
    destdir = nil
    loop do
        destdir = File.join(RPA::TEMP_DIR, 
                            "#{prefix}_#{Process.pid}_#{Time.now.to_i}_#{rand(1000000)}")
        #FIXME: naive, should do locking
        break if !File.exist? destdir
    end
    FileUtils.mkdir_p destdir if mkdir
    destdir
end

end # RPA namespace
