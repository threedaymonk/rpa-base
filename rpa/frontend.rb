#
# Copyright (C) 2004 Zachary P. Landau
# See LICENSE.txt for additional licensing information.
#

require 'rpa/base'
require 'rpa/install'
require 'rpa/package'
require 'optparse'
require 'ostruct'
require 'yaml'

module RPA

class Frontend

    def initialize(commands)
        @commands = commands

        begin
            @options = parse
        rescue OptionParser::InvalidOption => msg
            $stderr.puts "Error: #{msg}"
            exit 1
        end

        do_cmd(ARGV)
    end

    def parse(args=ARGV)
    end

    def do_cmd(cmd)
    end

    def command_output
        @commands.each do |c|
            yield "    %-32s %s" % [ "#{c[0]} #{c[1]}", c[2] ]
        end
    end

end

end


