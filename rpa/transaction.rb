#
# Copyright (C) 2004 Mauricio Julio Fernández Pradier
# See LICENSE.txt for additional licensing information.
#

module RPA

module Transaction
    require 'rbconfig'
    
    if /dos|win32/i.match ::Config::CONFIG["arch"]
        def self.atomic_write(destfile, data)
            # no file locking, fstat is bogus
            tmpname = "#{destfile}.#{Time.new.to_i}.#{rand(10000)}"
            File.open(tmpname, "wb") { |f| f.write data; f.fsync }
            #FIXME: we're leaving garbage around if we're interrupted before
            # the rename happens; remove it somewhere
            File.rename(tmpname, destfile)
            # we cannot open a dir on win32 :-(
            #dir = File.open(File.dirname(destfile), "r")
            #dir.fsync rescue nil # only after matz commits our patch
            #dir.close
        end
    else
    def self.atomic_write(destfile, data)
        dest = nil
            # Loop until we get a lock on the file *presently* located at 
            # destfile
        loop do
            dest.close if dest             # And unlock
            dest = File.open(destfile, "ab")
            dest.flock(File::LOCK_EX)
            old_stat = dest.stat
            new_stat = File::stat(destfile)
            break if old_stat.dev == new_stat.dev && 
            old_stat.ino == new_stat.ino
        end
            # at this point, we have an exclusive lock on destfile
        tmpname = "#{destfile}.#{Time.new.to_i}.#{rand(10000)}"
        File.open(tmpname, "wb") { |f| f.write data; f.fsync }
            #FIXME: we're leaving garbage around if we're interrupted before
            # the rename happens; remove it somewhere
        File.rename(tmpname, destfile)
        dir = open(File.dirname(destfile), "r")
        dir.fsync rescue nil # only after matz commits our patch
        dir.close
    ensure
        dest.flock(File::LOCK_UN) rescue nil
        dest.close rescue nil
    end
    end
end
end
