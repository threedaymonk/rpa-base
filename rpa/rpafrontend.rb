#
# Copyright (C) 2004 Zachary P. Landau
# See LICENSE.txt for additional licensing information.
#

require 'rpa/frontend'
require 'rpa/defaults'

module RPA

# TODO (besides ones marked in code): 
#	* generalize searches criteria style?  
class RPAFrontend < Frontend

    COMMANDS = [
        ['install', '[port]...', 'Installs the given ports'],
        ['remove', '[port]...', 'Removes the given ports'],
        ['query', '[port]...', 'Query the repository'],
        ['list', '', 'List currently installed ports'],
        ['info', '[port]...', 'Gives info on installed ports'],
        ['update', '', 'Update repository data'],
        ['rollback', '', 'Recover from previous abort'],
        ['check', '[port]...', 'Check status of the given ports'],
        ['help', '', 'Displays help for commands']
    ]

    def initialize
        Install.auto_install = false

	super(COMMANDS)
    end

    def parse(args=ARGV)
        options = OpenStruct.new
        options.name = nil
        options.description = nil
        options.simple = false
        options.requires = []
        options.classification = []
        options.eval = nil
        options.eval_display = '__default__'
        # if not specified, __default__ will be replaced by the appropriate
        # expression (x minus md5sums, files, dirs, etc)

        config_args = []
        opts = OptionParser.new do |opts|
            opts.banner = "Usage: rpa [options] [command]"
            opts.separator ""

	    # XXX: optparse adjusts padding length depending on size of options
	    # It shouldn't happen often, so we can adjust this manually, if
	    # need be
            opts.separator "Commands:"
            command_output do |c|
                opts.separator c
            end

            opts.separator "General options:"
            opts.on("-h", "--help", "Display usage") do
                puts opts
                exit 0
            end

            opts.on("-q", "--quiet", "Only output errors") do 
                options.quiet = true
            end
            
            opts.on("-f", "--force", "Force installation despite file conflicts") do |o|
                config_args << "--force" 
            end

            opts.on("-s", "--simple", "Simple port display") do
                options.simple = true
            end
            opts.on("--verbose LEVEL", "Verbosity level (4)") do |o|
                config_args << "--verbose" 
                config_args << o
            end
            opts.on("--debug", "Debug mode") do |o|
                config_args << "--debug" 
            end
            opts.on("-v", "--version", "Version info") do |o|
                puts "rpa (rpa-base #{RPA::RPABASE_VERSION}) RPA #{RPA::VERSION}"
            end

            opts.separator "Query/info commands:"

            opts.on("-n", "--name NAME", "Port name") do |name|
                options.name = name
            end

            opts.on("-d", "--description DESC", "Port description") do |desc|
                options.description = desc
            end

            opts.on("-r", "--requires PORT[, ...]", Array, "Port dependency") do |req|
                options.requires = req
            end

            opts.on("-c", "--classification TYPE[, ...]", Array, "Port classification") do |c|
                options.classification = c
            end

            opts.on("-e", "--eval CODE", "Eval query") do |e|
                options.eval = e
            end

            opts.on("-D", "--eval-display CODE", "Eval display") do |e|
                options.eval_display = e
            end

            # FIXME: decide whether to keep this or dump it altogether
            #opts.separator "Local installation options:"
            #RPA::Config.parameters.each do |param|
            #    if param.param
            #        opts.on("#{param.exported_name} #{param.param}",
            #                "#{param.desc}", "#{param.value}") do |o|
            #                    config_args << "--#{param.name}"
            #                    config_args << o
            #                end
            #    else
            #        opts.on("#{param.exported_name}", 
            #                "#{param.desc}") do |optvalue|
            #            config_args << "--#{param.name}"
            #        end
            #    end
            #end
        end

        opts.parse!(args)
        @config = RPA::Config.new(config_args)
        @repository = RepositoryInfo.instance @config

        options.text = opts
        options
    end

    def do_cmd(cmd)
        if cmd.empty?
            puts @options.text
            exit 2
        end

        RPA.do_cleanup = false if @options.debug

        case cmd[0]
        when 'install'
            cmd.shift
            if cmd.empty?
                $stderr.puts "Must specify ports to install."
                exit 4
            end

            @localinst = LocalInstallation.instance @config
            install(cmd)
        when 'remove'
            cmd.shift
            if cmd.empty?
                $stderr.puts "Must specify ports to remove."
                exit 5
            end

            @localinst = LocalInstallation.instance @config
            remove(cmd)
        when 'query'
            cmd.shift

            unless cmd.empty?
                @options.name ||= cmd[0]
            end

            ports = @repository.ports.map{|p| p.metadata.clone.update({"url" => p.url}) }

            ports = query(cmd, ports).sort_by{|p| p["name"]}
            
            if @options.eval
                ports = eval_query(cmd, ports)
            end

            puts "Matches: "
            display_ports(ports)
        when 'list'
            puts "Installed ports:"
            @localinst = LocalInstallation.instance @config
            @localinst.installed_ports.sort.each{|x| puts x}
        when 'info'
            cmd.shift

            unless cmd.empty?
                @options.name ||= cmd[0]
            end

            @localinst = LocalInstallation.instance @config
            ports = @localinst.installed_ports.map do |pname| 
                @localinst.retrieve_metadata(pname).clone
            end

            ports = info(cmd, ports).sort_by{|p| p["name"]}
            
            if @options.eval
                ports = eval_query(cmd, ports)
            end

            puts "Matches: "
            display_ports(ports)
        when 'update'
            update(cmd)
        when 'check'
            cmd.shift
            if cmd.empty?
                $stderr.puts "Must specify ports to verify."
                exit 5
            end
            @localinst = LocalInstallation.instance @config
            check(cmd)
        when 'rollback'
            @localinst = LocalInstallation.instance @config
            rollback(cmd)
        when 'help'
            puts "Command Help:"
            puts ""
            command_output do |c|
                puts c
            end
            puts
            puts "Examples: "
            puts "  rpa install ri-rpa --verbose 5"
            puts "  rpa remove types"
            puts "  rpa query ri-rpa"
            puts "  rpa query -e 'requires && requires.include?(\"types\")' -D name,url,requires"
            puts "  rpa info types -D md5sums"
            puts "  rpa info ri-rpa"
        else
            $stderr.puts "Invalid command. See usage."
            exit 3
        end
    end

    def install(cmd)
        warn_if_no_port_info
        puts "Installing ports" unless @options.quiet

        previous_ports = @localinst.installed_ports
        begin
            cmd.each do |port|
                puts "  Installing #{port}" unless @options.quiet
                @localinst.install(port)
            end
        rescue => e
            $stderr.puts "Error: #{e} aborting"
            installed = @localinst.installed_ports
            installed = (installed - previous_ports)
            unless installed.empty?
                puts "Installed the following ports:"
                installed.sort.each{|pname| puts pname}
            end
            @localinst.apply_pending_rollbacks
            raise if @options.debug
            exit 6
        end
        @localinst.commit
    end

    def remove(cmd)
        puts "Removing packages" unless @options.quiet

        cmd.each do |pkg|
            unless @localinst.installed?(pkg)
                $stderr.puts "Error: #{pkg} is not installed"
                exit 7
            end
        end

        begin
            cmd.each do |pkg|
                next unless @localinst.installed?(pkg)
                puts "  Removing #{pkg}" unless @options.quiet
                @localinst.uninstall(pkg)
            end
        rescue Exception => e
            $stderr.puts "Error: #{e} aborting"
            raise if @options.debug
            @localinst.apply_pending_rollbacks
            exit 6
        end
        #TODO: should we commit here or only after removing the unneeded
        #      ports? Both lead to clean states anyway.
        @localinst.commit 
        @localinst.gc_unneeded_ports
        @localinst.commit
    end

    def query(cmd, ports)
        warn_if_no_port_info
        select_port_info ports
    end

    def info(cmd, ports)
        select_port_info ports
    end
    
    def select_port_info(ports)
        matches = ports

        if @options.name
            matches = matches.select { |p| p['name'] =~ /#{@options.name}/ }
        end
        if @options.description
            matches = matches.select { |p| p['description'] =~ /#{@options.description}/ }
        end

        unless @options.requires.empty?
            ma = []
            matches.each do |p|
                catch :next_pkg do
                    next unless p['requires']
                    @options.requires.each do |r|
                        throw :next_pkg unless p['requires'].include?(r)
                        ma << p unless ma.include? p
                    end
                end
            end
            matches = ma
        end

        unless @options.classification.empty?
            ma = []
            matches.each do |p|
                catch :next_pkg do
                    next unless p['classification']
                    @options.classification.each do |r|
                            throw :next_pkg unless p['classification'].include?(r)
                            ma << p unless ma.include? p
                    end
                end
            end

            matches = ma
        end

        matches
    end

    def eval_query(cmd, ports)
        ports.each do |x|
            # allow x.name in addition to x["name"]
            class << x
                def method_missing(meth, *a)
                    raise "Error near #{meth}" if meth.to_s[-1] == ?=
                    self[meth.to_s]
                end
            end
            x.freeze 
        end
        eval_wrapper('query') do
            ports.select { |x| x.instance_eval(@options.eval) }
        end
    end

    def eval_wrapper(name)
        begin
            yield
        rescue SyntaxError => e
            $stderr.puts "Invalid #{name} (Syntax Error): #{e.message}"
            exit 10
        rescue Exception => e
            $stderr.puts "Invalid #{name} (Exception Raised): #{e.message}"
            exit 11
        end
    end

    def update(cmd)
        @repository.update
    end

    def check(cmd)
        cmd.each do |port|
            begin
                status = @localinst.modified_files(port)
            rescue 
                puts "Port #{port} is not installed."
            end
            if status
                puts "=" * 40
                puts "#{port} was modified locally after install:"
                status.each do |k,v|
                    puts "File #{k} was #{v.to_s}."
                end
            else
                puts "All requested installed ports are in the same state as when unpacked."
            end
        end
    end

    def rollback(cmd)
        # this is a non-op since LocalInstallation.instance would have ran it
        @localinst.apply_pending_rollbacks 
    end

    def display_ports(ports)
        unless @options.simple
            use_pp = false
            if @options.eval_display == "__default__"
                @options.eval_display = <<-EOF
                name,version,classification,requires,description
                EOF
            else
                use_pp = true
            end
            # TODO: try to make display results look better (and ignore some fields)
            firstport = true
            ports.each do |x|
                eval_wrapper('eval-display') do 
                    firstfield = true
                    arr = (@options.eval_display||"").split(/,/).map do |_field|
                        {_field.strip => x[_field.strip] }
                    end
                    # TODO: this is ugly. refactor
		    arr.each do |y| 
                        2.times{puts} if firstfield && !firstport
                        firstfield = false
                        if Hash === y && !use_pp
                            sort_fields(y.keys).each do |k|
                                out = case y[k]
                                when Array
                                    y[k].map{|item| item.to_s}.join(" ") 
                                else
                                    y[k]
                                end
                                puts "#{k}: #{out}"
                            end
                        else
                            require 'pp'
                            pp y
                        end
                    end
                    firstport = false
                end
            end
        else
            ports.each do |p|
                puts "\t- %-35s %s" % [p['name'], p['description'].gsub("\n", ' ')[0..40]]
            end
        end
    end

    def sort_fields(fields)
        default_order = %w[name classification version requires wanted url
                platform rpaversion description]
        fields = fields.sort
        fields.sort_by do |x|
            if idx = default_order.index(x)
                idx
            else
                0
            end
        end
    end

    def warn_if_no_port_info
        if @repository.ports.size == 0
            puts <<-EOF
There is no port information in the cache. Please run
    rpa update
EOF
            exit 12
        end
    end
end
end
