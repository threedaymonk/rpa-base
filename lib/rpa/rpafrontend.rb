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
        ['install', '[port|port.rps]...', 'Installs the given ports'],
        ['remove', '[port]...', 'Removes the given ports'],
        ['dist-upgrade', '', 'Upgrades all ports'],
        ['build', '[port]...', 'Builds the given ports'],
        ['source', '[port]...', 'Download the specified ports'],
        ['query|search', '[port]...', 'Query the repository'],
        ['list', '', 'List currently installed ports'],
        ['info', '[port]...', 'Gives info on installed ports'],
        ['update', '', 'Update repository data'],
        ['rollback', '', 'Recover from previous abort'],
        ['check', '[port]...', 'Check status of the given ports'],
        ['clean', '', 'Purges package and port caches.'],
        ['help', '', 'Displays help for commands']
    ]

    def initialize
        Install.auto_install = false

	super(COMMANDS)
    end

    def parse(args=ARGV)
        options = OpenStruct.new
        options.searchstr = nil
        options.extended = false
        options.requires = []
        options.classification = []
        options.eval = nil
        options.show_version = false
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

            opts.on("--[no-]proxy [PROXY]", "HTTP proxy to use") do |o|
                if o
                    config_args << "--proxy"
                    config_args << o
                else
                    config_args << "--no-proxy"
                end
            end

            opts.on("-q", "--quiet", "Only output errors") do 
                options.quiet = true
            end

            opts.on("-x", "--extended", "Extended port display") do
                options.extended = true
            end
            opts.on("--verbose LEVEL", "Verbosity level (4)") do |o|
                config_args << "--verbose" 
                config_args << o
            end
            opts.on("--debug", "Debug mode") do |o|
                config_args << "--debug" 
            end
            opts.on("-v", "--version", "Version info") do |o|
                options.show_version = true
            end

            opts.separator "Install options:"

            opts.on("-f", "--force", "Force installation despite file conflicts") do |o|
                config_args << "--force" 
            end
            
            opts.on("-p", "--parallelize", "Parallelize operations") do |o|
                config_args << "--parallelize" 
            end
            
            
            opts.on("--no-tests", "Don't run unit tests on install") do |o|
                config_args << "--no-tests" 
            end


            opts.separator "Query/info commands:"

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
        if @options.show_version
            @localinst = LocalInstallation.instance @config, false
            version = @localinst.retrieve_metadata("rpa-base")["version"]
            puts "rpa (rpa-base #{version}) RPA #{RPA::VERSION}"
        end
        if cmd.empty?
            puts @options.text unless @options.show_version
            exit 2
        end

        RPA.do_cleanup = false if @options.debug

        case cmd[0]
        when 'build'
            cmd.shift
            if cmd.empty?
                $stderr.puts "Must specify ports to build."
                exit 4
            end

            # 2nd arg: don't return to clean state (not needed), so parallel
            # builds work
            @localinst = LocalInstallation.instance @config, false
            build(cmd)
        when 'install'
            cmd.shift
            if cmd.empty?
                $stderr.puts "Must specify ports to install."
                exit 4
            end

            @localinst = LocalInstallation.instance @config, false
            install(cmd)
        when 'dist-upgrade'
            @localinst = LocalInstallation.instance @config, false
            dist_upgrade(cmd)
        when 'source'
            cmd.shift
            if cmd.empty?
                $stderr.puts "Must specify ports to install."
                exit 4
            end

            @localinst = LocalInstallation.instance @config
            cmd.each do |port|
                @localinst.get_port port, "."
            end
        when 'remove'
            cmd.shift
            if cmd.empty?
                $stderr.puts "Must specify ports to remove."
                exit 5
            end

            @localinst = LocalInstallation.instance @config
            remove(cmd)
        when 'query', 'search'
            cmd.shift

            unless cmd.empty?
                @options.searchstr ||= cmd[0]
            end

            ports = @repository.ports.map{|p| p.metadata.clone.update({"url" => p.url}) }

            ports = query(cmd, ports).sort_by{|p| p["name"]}
            
            if @options.eval
                ports = eval_query(cmd, ports)
            end

            puts "Matching available ports: "
            display_ports(ports)
        when 'list'
            puts "Installed ports:"
            @localinst = LocalInstallation.instance @config
            list_installed_ports
        when 'info'
            cmd.shift

            unless cmd.empty?
                @options.searchstr ||= cmd[0]
            end

            @localinst = LocalInstallation.instance @config
            ports = @localinst.installed_ports.map do |pname| 
                @localinst.retrieve_metadata(pname).clone
            end

            ports = info(cmd, ports).sort_by{|p| p["name"]}
            
            if @options.eval
                ports = eval_query(cmd, ports)
            end

            puts "Matching installed ports: "
            display_ports(ports, true)
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
        when 'clean'
            @localinst = LocalInstallation.instance @config
            @localinst.clean_caches
        when 'rollback'
            @localinst = LocalInstallation.instance @config
            rollback(cmd)
        when 'help', 'usage'
            puts "Command Help:"
            puts ""
            command_output do |c|
                puts c
            end
            puts
            puts "Examples: "
            puts "  rpa install ri-rpa --verbose 5"
            puts "  rpa remove types"
            puts "  rpa query -x ri-rpa"
            puts "  rpa query -e 'requires && requires.include?(\"types\")' -D name,url,requires"
            puts "  rpa info types -D md5sums"
            puts "  rpa info -x ri-rpa"
        else
            $stderr.puts "Invalid command. See usage."
            exit 3
        end
    end
 
    def list_installed_ports
        @localinst.installed_ports.sort.each do |pname|
            meta = @localinst.retrieve_metadata pname
            name, version, desc = %w[name version description].map{|x| meta[x] }
            short_desc = desc.split(/\n/).first.chomp
            puts "%-13s %10s  %s" % [name, version, short_desc]
        end
    end

    def build(cmd)
        warn_if_no_port_info
        puts "Building ports" unless @options.quiet

        begin
            cmd.each do |port|
                puts "  Installing #{port}" unless @options.quiet
                @localinst.build(port, true)
            end
        rescue => e
            $stderr.puts "Error: #{e} aborting"
            raise if @options.debug
            exit 6
        end
    end

    def install(cmd)
        warn_if_no_port_info
        puts "Installing ports" unless @options.quiet

        @localinst ||= LocalInstallation.instance @config, false
        previous_ports = @localinst.installed_ports
        begin
            cmd.each do |port| 
                next if /\.rps\z/.match port
                @localinst.build port
            end
            @localinst.acquire_lock
            # we must make sure we're in a clean state cause it was not done
            # when initialing the LocalInstallation
            @localinst.apply_pending_rollbacks
            cmd.each do |port|
                if port =~ /\.rps\z/
                    # it's a .rps file
                    puts "  Installing from #{port}" unless @options.quiet
                    @localinst.install_from_port port
                else
                    puts "  Installing #{port}" unless @options.quiet
                    @localinst.install(port)
                end
            end
        rescue => e
            $stderr.puts "Error: #{e} aborting"
            @localinst.apply_pending_rollbacks
            raise if @options.debug
            exit 6
        end
        @localinst.commit
    end
    
    def dist_upgrade(cmd)
        warn_if_no_port_info
        puts "Upgrading the whole distribution" unless @options.quiet

        previous_ports = @localinst.installed_ports
        begin
            # we must make sure we're in a clean state cause it was not done
            # when initialing the LocalInstallation
            @localinst.apply_pending_rollbacks
            availports = @localinst.repository_info.ports
            previous_ports.sort.each do |port| 
                next unless @localinst.retrieve_metadata(port)["wanted"]
                unless availports.find{|x| x.metadata["name"] == port}
                    puts "WARNING: skipping #{port}" unless @options.quiet
                    next
                end
                @localinst.install port
                @localinst.commit
            end
        rescue => e
            $stderr.puts "Error: #{e} aborting"
            @localinst.apply_pending_rollbacks
            raise if @options.debug
            exit 6
        end
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
        #@localinst.commit 
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

        if @options.searchstr
            matches = matches.select do |p| 
                p['name'] =~ /#{@options.searchstr}/i or
                p['description'] =~  /#{@options.searchstr}/i
            end
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
        require 'time'
        days = 3653 # 10 years :P
        since = Time.new - 24*3600*days
        newports, modports = @repository.update(since)
        puts
        unless @options.quiet
            if newports.size > 0
                plen = newports.inject(0){|s,x| (l=x["name"].size)>s ? l : s} 
                vlen = newports.inject(0){|s,x| (l=x["version"].size)>s ? l : s} 
                puts "Ports added since the last 'rpa update'" # (in the last #{days} days):"
                newports.each do |p|
                    desc = p["description"].split(/\n/).first.chomp
                    puts(" %#{plen}s  %#{vlen}s   #{desc}" % 
                         [p["name"], p["version"]])
                end
                puts
            end
            if modports.size > 0
                plen = modports.inject(0){|s,x| (l=x[0]["name"].size)>s ? l: s} 
                puts "Ports updated since the last 'rpa update'" # (in the last #{days} days):" 
                modports.each do |p|
                    desc = p[1]["description"].split(/\n/).first.chomp
                    puts(" %#{plen}s  #{p[0]["version"]} -> #{p[1]["version"]}" %
                           p[1]["name"])
                end
                puts
            end
        end
        if modports.any?{|x| x[1]["name"] == "rpa-base"}
            puts
            puts " ** New version of rpa-base available, will install it. ** "
            puts
            install "rpa-base"
        end
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

    def display_ports(ports, fancy_colors = false)
        case RUBY_PLATFORM
        when /cygwin/i  # keep the value
        when /dos|win/i
            fancy_colors = false
        end
        temp = @repository.ports.map{|p| p.metadata}
        versions = {}
        temp.each{|meta| versions[meta["name"]] = meta["version"]}
        
        if @options.extended
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
            namelen = ports.inject(0){|s,x| (l=x["name"].size) > s ? l : s}
            versionlen = ports.inject(0){|s,x| (l=x["version"].size) > s ? l : s}
            versionlen += 9 if fancy_colors
            ports.each do |p|
                name, version, desc = %w[name version description].map{|x| p[x] }
                short_desc = desc.split(/\n/).first.chomp
                if fancy_colors
                    #FIXME: robustify the version comparison below (factor it out)
                    v1 = version.split(/\.|-/).map{|x| /([0-9]+)/ =~ x ? x.to_i: x}
                    if versions[name]
                        v2 = versions[name].split(/\.|-/).map{|x| /([0-9]+)/ =~ x ? x.to_i: x}
                        color = (v1 <=> v2) == -1 ? 31 : 32
                    else
                        color = 36
                    end
                    version = "\x1b[#{color}m#{version}\x1b[0m"
                end
                puts "%-#{namelen}s  %#{versionlen}s  %s" % [name, version, short_desc]
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
