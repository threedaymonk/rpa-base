#
# Copyright (C) 2004 Mauricio Julio Fernández Pradier
# See LICENSE.txt for additional licensing information.
#

require 'yaml'
require 'yaml/syck'
require 'fileutils'
require 'rpa/base'
require 'rpa/open-uri'

module RPA

module Package

class NonSeekableIO < StandardError; end
class ArgumentError < ::ArgumentError; end
class ClosedIO < StandardError; end
class BadCheckSum < StandardError; end
class TooLongFileName < StandardError; end

module FSyncDir
    private
    def fsync_dir(dirname)
            # make sure this hits the disc
        begin
            dir = open(dirname, "r")
            dir.fsync
        rescue # ignore IOError if it's an unpatched (old) Ruby
        ensure
            dir.close if dir rescue nil 
        end
    end
end

class TarHeader
    FIELDS = [:name, :mode, :uid, :gid, :size, :mtime, :checksum, :typeflag,
            :linkname, :magic, :version, :uname, :gname, :devmajor, 
            :devminor, :prefix]
    FIELDS.each {|x| attr_reader x}

    def self.new_from_stream(stream)
        data = stream.read(512)
        fields = data.unpack( "Z100" + # record name
                             "A8A8A8" +        # mode, uid, gid
                             "A12A12" +        # size, mtime
                             "A8a" +           # checksum, typeflag
                             "Z100" +          # linkname
                             "A6A2" +          # magic, version
                             "Z32" +           # uname
                             "Z32" +           # gname
                             "A8A8" +          # devmajor, devminor
                             "Z155"            # prefix
                            )
        name = fields.shift
        mode = fields.shift.oct
        uid = fields.shift.oct
        gid = fields.shift.oct
        size = fields.shift.oct
        mtime = fields.shift.oct
        checksum = fields.shift.oct
        typeflag = fields.shift
        linkname = fields.shift
        magic = fields.shift
        version = fields.shift.oct
        uname = fields.shift
        gname = fields.shift
        devmajor = fields.shift.oct
        devminor = fields.shift.oct
        prefix = fields.shift

        empty = (data == "\0" * 512)
        
        new(:name=>name, :mode=>mode, :uid=>uid, :gid=>gid, :size=>size, 
            :mtime=>mtime, :checksum=>checksum, :typeflag=>typeflag, :magic=>magic,
            :version=>version, :uname=>uname, :gname=>gname, :devmajor=>devmajor,
            :devminor=>devminor, :prefix=>prefix, :empty => empty )
    end
    
    def initialize(vals)
        unless vals[:name] && vals[:size] && vals[:prefix] && vals[:mode]
            raise Package::ArgumentError
        end
        vals[:uid] ||= 0
        vals[:gid] ||= 0
        vals[:mtime] ||= 0
        vals[:checksum] ||= ""
        vals[:typeflag] ||= "0"
        vals[:magic] ||= "ustar"
        vals[:version] ||= "00"
        vals[:uname] ||= "wheel"
        vals[:gname] ||= "wheel"
        vals[:devmajor] ||= 0
        vals[:devminor] ||= 0
        FIELDS.each {|x| instance_variable_set "@#{x.to_s}", vals[x]}
        @empty = vals[:empty]
    end

    def empty?
        @empty
    end

    def to_s
        update_checksum
        header(checksum)
    end

    def update_checksum
        h = header(" " * 8)
        @checksum = oct(calculate_checksum(h), 6)
    end

    private
    def oct(num, len)
        "%0#{len}o" % num
    end

    def calculate_checksum(hdr)
        hdr.unpack("C*").inject{|a,b| a+b}
    end

    def header(chksum)
#           struct tarfile_entry_posix {
#             char name[100];   # ASCII + (Z unless filled)
#             char mode[8];     # 0 padded, octal, null
#             char uid[8];      # ditto
#             char gid[8];      # ditto
#             char size[12];    # 0 padded, octal, null
#             char mtime[12];   # 0 padded, octal, null
#             char checksum[8]; # 0 padded, octal, null, space
#             char typeflag[1]; # file: "0"  dir: "5" 
#             char linkname[100]; # ASCII + (Z unless filled)
#             char magic[6];      # "ustar\0"
#             char version[2];    # "00"
#             char uname[32];     # ASCIIZ
#             char gname[32];     # ASCIIZ
#             char devmajor[8];   # 0 padded, octal, null
#             char devminor[8];   # o padded, octal, null
#             char prefix[155];   # ASCII + (Z unless filled)
#           };
        arr = [name, oct(mode, 7), oct(uid, 7), oct(gid, 7), oct(size, 11),
                oct(mtime, 11), chksum, " ", typeflag, linkname, magic, version,
                uname, gname, oct(devmajor, 7), oct(devminor, 7), prefix]
        str = arr.pack("a100a8a8a8a12a12" + # name, mode, uid, gid, size, mtime
                       "a7aaa100a6a2" + # chksum, typeflag, linkname, magic, version
                       "a32a32a8a8a155") # uname, gname, devmajor, devminor, prefix
        str + "\0" * ((512 - str.size) % 512)
    end
end

class TarWriter
    class FileOverflow < StandardError; end
    class BlockNeeded < StandardError; end

    class BoundedStream
        attr_reader :limit, :written
        def initialize(io, limit)
            @io = io
            @limit = limit
            @written = 0
        end

        def write(data)
            if data.size + @written > @limit
                raise FileOverflow, 
                    "You tried to feed more data than fits in the file." 
            end
            @io.write data
            @written += data.size
            data.size
        end
    end
    class RestrictedStream
        def initialize(anIO)
            @io = anIO
        end

        def write(data)
            @io.write data
        end
    end

    def self.new(anIO)
        writer = super(anIO)
        return writer unless block_given?
        begin
            yield writer
        ensure
            writer.close
        end
        nil
    end

    def initialize(anIO)
        @io = anIO
        @closed = false
    end

    def add_file_simple(name, mode, size)
        raise BlockNeeded unless block_given?
        raise ClosedIO if @closed
        name, prefix = split_name(name)
        header = TarHeader.new(:name => name, :mode => mode, 
                               :size => size, :prefix => prefix).to_s
        @io.write header
        os = BoundedStream.new(@io, size)
        yield os
        #FIXME: what if an exception is raised in the block?
        min_padding = size - os.written 
        @io.write("\0" * min_padding)
        remainder = (512 - (size % 512)) % 512
        @io.write("\0" * remainder)
    end

    def add_file(name, mode)
        raise BlockNeeded unless block_given?
        raise ClosedIO if @closed
        raise NonSeekableIO unless @io.respond_to? :pos=
        name, prefix = split_name(name)
        init_pos = @io.pos
        @io.write "\0" * 512 # placeholder for the header
        yield RestrictedStream.new(@io)
        #FIXME: what if an exception is raised in the block?
        #FIXME: what if an exception is raised in the block?
        size = @io.pos - init_pos - 512
        remainder = (512 - (size % 512)) % 512
        @io.write("\0" * remainder)
        final_pos = @io.pos
        @io.pos = init_pos
        header = TarHeader.new(:name => name, :mode => mode, 
                               :size => size, :prefix => prefix).to_s
        @io.write header
        @io.pos = final_pos
     end

    def mkdir(name, mode)
        raise ClosedIO if @closed
        name, prefix = split_name(name)
        header = TarHeader.new(:name => name, :mode => mode, :typeflag => "5",
                               :size => 0, :prefix => prefix).to_s
        @io.write header
        nil
    end

    def flush
        raise ClosedIO if @closed
        @io.flush if @io.respond_to? :flush
    end

    def close
        #raise ClosedIO if @closed
        return if @closed
        @io.write "\0" * 1024
        @closed = true
    end

    private
    def split_name name
        raise TooLongFileName if name.size > 256 
        if name.size <= 100
            prefix = ""
        else
            parts = name.split(/\//)
            newname = parts.pop
            nxt = ""
            loop do
                nxt = parts.pop
                break if newname.size + 1 + nxt.size > 100
                newname = nxt + "/" + newname
            end
            prefix = (parts + [nxt]).join "/"
            name = newname
            raise TooLongFileName if name.size > 100 || prefix.size > 155
        end
        return name, prefix
    end
end 

class TarReader
    include RPA::Package
    class UnexpectedEOF < StandardError; end
    module InvalidEntry
        def read(len=nil); raise ClosedIO; end
        def getc; raise ClosedIO;  end
        def rewind; raise ClosedIO;  end
    end
    class Entry
        TarHeader::FIELDS.each{|x| attr_reader x}

        def initialize(header, anIO)
            @io = anIO
            @name = header.name
            @mode = header.mode
            @uid = header.uid
            @gid = header.gid
            @size = header.size
            @mtime = header.mtime
            @checksum = header.checksum
            @typeflag = header.typeflag
            @linkname = header.linkname
            @magic = header.magic
            @version = header.version
            @uname = header.uname
            @gname = header.gname
            @devmajor = header.devmajor
            @devminor = header.devminor
            @prefix = header.prefix
            @read = 0
            @orig_pos = @io.pos
        end

        def read(len = nil)
            return nil if @read >= @size
            len ||= @size - @read
            max_read = [len, @size - @read].min
            ret = @io.read(max_read)
            @read += ret.size
            ret
        end

        def getc
            return nil if @read >= @size
            ret = @io.getc
            @read += 1 if ret
            ret
        end

        def is_directory?
            @typeflag == "5"
        end

        def is_file?
            @typeflag == "0"
        end

        def eof?
            @read >= @size
        end

        def pos
            @read
        end

        def rewind
            raise NonSeekableIO unless @io.respond_to? :pos=
            @io.pos = @orig_pos
            @read = 0
        end

        alias_method :is_directory, :is_directory?
        alias_method :is_file, :is_file

        def bytes_read
            @read
        end

        def full_name
            if @prefix != ""
                File.join(@prefix, @name)
            else
                @name
            end
        end

        def close
            invalidate
        end

        private
        def invalidate
            extend InvalidEntry
        end
    end

    def self.new(anIO)
        reader = super(anIO)
        return reader unless block_given?
        begin
            yield reader
        ensure
            reader.close
        end
        nil
    end

    def initialize(anIO)
        @io = anIO
        @init_pos = anIO.pos
    end

    def each(&block)
        each_entry(&block)
    end

    # do not call this during a #each or #each_entry iteration
    def rewind
        if @init_pos == 0
            raise NonSeekableIO unless @io.respond_to? :rewind
            @io.rewind
        else
            raise NonSeekableIO unless @io.respond_to? :pos=
            @io.pos = @init_pos
        end
    end

    def each_entry
        loop do
            return if @io.eof?
            header = TarHeader.new_from_stream(@io)
            return if header.empty?
            entry = Entry.new header, @io
            size = entry.size
            yield entry
            skip = (512 - (size % 512)) % 512
            if @io.respond_to? :seek
                # avoid reading...
                @io.seek(size - entry.bytes_read, IO::SEEK_CUR)
            else
                pending = size - entry.bytes_read
                while pending > 0
                    bread = @io.read([pending, 4096].min).size
                    raise UnexpectedEOF if @io.eof?
                    pending -= bread
                end
            end
            @io.read(skip) # discard trailing zeros
            # make sure nobody can use #read, #getc or #rewind anymore
            entry.close
        end
    end

    def close
    end
end

class TarInput
    include FSyncDir
    include Enumerable
    attr_reader :metadata
    require 'zlib'
    require 'digest/md5'
    class << self; private :new end

    def initialize(filename)
        @io = open(filename, "rb")
        @tarreader = TarReader.new @io
        has_meta = false
        @tarreader.each do |entry|
            case entry.full_name 
            when "metadata"
                @metadata = YAML.load(entry.read) rescue nil
                @metadata ||= nil # convert false into nil
                has_meta = true
                break
            when "metadata.gz"
                begin
                    gzis = Zlib::GzipReader.new entry
                    # YAML wants an instance of IO 
                    @metadata = YAML.load(gzis) rescue nil
                    @metadata ||= nil # convert false into nil
                    has_meta = true
                ensure
                    gzis.close
                end
            end
        end
        @tarreader.rewind
        @fileops = FileOperations.new
        raise RuntimeError, "No metadata found!" unless has_meta
    end

    def self.open(filename)
        raise "Want a block" unless block_given?
        begin
            is = new(filename)
            yield is
        ensure
            is.close if is
        end
    end

    def each(&block)
        @tarreader.each do |entry|
            next unless entry.full_name == "data.tar.gz"
            begin
                is = Zlib::GzipReader.new entry
                TarReader.new(is) do |inner|
                    inner.each(&block)
                end
            ensure
                is.finish
            end
        end
        @tarreader.rewind
    end

    def extract_entry(destdir, entry, expected_md5sum = nil)
        if entry.is_directory?
            dest = File.join(destdir, entry.full_name)
            if file_class.dir? dest
                begin
                    @fileops.chmod entry.mode, dest
                rescue Exception
                end
            else
                @fileops.mkdir_p(dest, :mode => entry.mode)
                #FIXME: redundant but somehow needed sometimes for
                #       ruby 2004-08-26 (didn't happen with 2004-07-30)
                @fileops.chmod entry.mode, dest
            end
            fsync_dir dest 
            fsync_dir File.join(dest, "..")
            return
        end
        # it's a file
        md5 = Digest::MD5.new if expected_md5sum
        destdir = File.join(destdir, File.dirname(entry.full_name))
        @fileops.mkdir_p(destdir, :mode => 0755)
        destfile = File.join(destdir, File.basename(entry.full_name))
        @fileops.chmod 0600, destfile rescue nil  # Errno::ENOENT
        file_class.open(destfile, "wb", entry.mode) do |os|
            loop do 
                data = entry.read(4096)
                break unless data
                md5 << data if expected_md5sum
                os.write(data)
            end
            os.fsync
        end
        @fileops.chmod(entry.mode, destfile)
        fsync_dir File.dirname(destfile)
        fsync_dir File.join(File.dirname(destfile), "..")
        if expected_md5sum && expected_md5sum != md5.hexdigest
            raise BadCheckSum
        end
    end

    def close
        @io.close
        @tarreader.close
    end
    
    private
    
    def file_class
        File
    end
end

class TarOutput
    require 'zlib'
    require 'yaml'
    
    class << self; private :new end

    def initialize(filename)
        @io = File.open(filename, "wb")
        @external = TarWriter.new @io
    end

    def external_handle
        @external
    end

    def self.open(filename, &block)
        outputter = new(filename)
        metadata = nil
        set_meta = lambda{|x| metadata = x}
        raise "Want a block" unless block_given?
        begin
            outputter.external_handle.add_file("data.tar.gz", 0644) do |inner|
                begin
                    os = Zlib::GzipWriter.new inner
                    TarWriter.new(os) do |inner_tar_stream| 
                        klass = class <<inner_tar_stream; self end
                        klass.send(:define_method, :metadata=, &set_meta) 
                        block.call inner_tar_stream
                    end
                ensure
                    os.flush
                    os.finish
                    #os.close
                end
            end
            outputter.external_handle.add_file("metadata.gz", 0644) do |os|
                begin
                    gzos = Zlib::GzipWriter.new os
                    gzos.write metadata
                ensure
                    gzos.flush
                    gzos.finish
                end
            end
        ensure
            outputter.close
        end
        nil
    end
    
    def close
        @external.close
        @io.close
    end
end
end # module Package


module Package    
    def self.open(dest, mode = "r", &block)
        raise "Block needed" unless block_given?

        case mode
        when "r"
            TarInput.open(dest, &block)
        when "w"
            TarOutput.open(dest, &block)
        else
            raise "Unknown Package open mode"
        end
    end

    def self.pack(src, destname)
        TarOutput.open(destname) do |outp|
            dir_class.chdir(src) do 
                outp.metadata = (file_class.read("RPA/metadata") rescue nil)
                find_class.find('.') do |entry|
                    case 
                    when file_class.file?(entry)
                        entry.sub!(%r{\./}, "")
                        next if entry =~ /\ARPA\//
                        stat = File.stat(entry)
                        outp.add_file_simple(entry, stat.mode, stat.size) do |os|
                            file_class.open(entry, "rb") do |f| 
                                os.write(f.read(4096)) until f.eof? 
                            end
                        end
                    when file_class.dir?(entry)
                        entry.sub!(%r{\./}, "")
                        next if entry == "RPA"
                        outp.mkdir(entry, file_class.stat(entry).mode)
                    else
                        raise "Don't know how to pack this yet!"
                    end
                end
            end
        end
    end

    def normalized_name(metadata)
        metadata["name"] + "_" + metadata["version"] + '_' +
            metadata["platform"] + '.rpa'
    end

    def name_matcher(name, version = nil, platform = nil)
        s = "#{name}_"
        s << [version, platform].map{|x| (x || "*")}.join("_")
        s << ".rpa"
        s
    end

    module_function :normalized_name, :name_matcher

    class << self
        def file_class
            File
        end

        def dir_class
            Dir
        end

        def find_class
            require 'find'
            Find
        end
    end
end
    
end

