#
# Copyright (C) 2004 Zachary P. Landau
# See LICENSE.txt for additional licensing information.
#

require 'rpa/frontend'
require 'yaml'

module RPA

class AdminFrontend < Frontend

    COMMANDS = [
        ['buildrepos', '<info file> <base url> <ports dir>', 'Build a repository'],
        ['packport', '<dir>', 'Build a package']
    ]

    def initialize
        super(COMMANDS)
    end

    def parse(args=ARGV)
        options = OpenStruct.new
        options.verbose = false

        opts = OptionParser.new do |opts|
            opts.banner = "Usage: rpaadmin [options] [command]"
            opts.separator ""

            opts.separator "Commands:"
            command_output do |c|
                opts.separator c
            end

            opts.separator "General options:"
            opts.on("-h", "--help", "Display usage") do
                puts opts
                exit 0
            end

            opts.on("-v", "--verbose", "Be verbose (default is off)") do
                #XXX: use.
                options.verbose = true
            end

        end

        opts.parse!(args)

        options.text = opts
        options
    end

    def do_cmd(cmd)
        if cmd.empty?
            puts @options.text
            exit 2
        end

        case cmd[0]
        when 'buildrepos'
            cmd.shift
            if cmd.length != 3
                $stderr.puts "Invalid parameters. See usage."
                exit 6
            end

            puts "Not implemented yet."
        when 'packport'
            cmd.shift
            if cmd.empty?
                $stderr.puts "Must specify directory."
                exit 5
            end

            file = File.basename(File.expand_path(cmd[0]))
            puts "Packaging #{file}..."
            RPA::Package.pack(cmd[0], "#{file}.rps")

        when 'help'
            puts "Command Help:"
            puts ""
            command_output do |c|
                puts c
            end
        else
            $stderr.puts "Invalid command. See usage."
            exit 3
        end

    end
end

end
