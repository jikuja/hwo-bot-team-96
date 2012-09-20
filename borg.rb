#!/usb/bin/ruby
require 'getoptlong'

# With this test program we know where our library is located
# Add libry location into ruby's library path

$: << File.dirname(__FILE__) + "/lib"
require 'pongclient'

def print_usage
puts "
#{$0} [OPTION] ... NAME HOST PORT
-h,  --help:
    show  help
-a x, --ai x:
    select x.rb as and AI class
-v, --version:
    print version information
-V x, --verbose x
    0 debug
    1 info
    2 warn
    3 error
    4 fatal
"
end

if __FILE__ == $0
    # default values for arguments
    ai = "ai2.rb"
    dump_file = "log/client-dump.log"
    request = nil
    logger_level = 3

    #use getoptlong to parse command line arguments
    opts = GetoptLong.new(
        [ '--help', '-h', GetoptLong::NO_ARGUMENT ],
        [ '--ai', '-a', GetoptLong::REQUIRED_ARGUMENT],
        [ '--version', '-v', GetoptLong::NO_ARGUMENT],
        [ '--verbose', '-V', GetoptLong::REQUIRED_ARGUMENT],
        [ '--no-dump', '-n', GetoptLong::NO_ARGUMENT],
        [ '--request', '-r', GetoptLong::REQUIRED_ARGUMENT]
    )

    begin
        opts.each do |opt, arg|
            case opt
            when '--help'
                print_usage
                exit 0
            when '--ai'
                ai = arg
            when '--verbose'
                if arg[/\d+/]
                    puts "a"
                    logger_level = arg.to_i
                else
                    print_usage
                    exit 0
                end
            when '--version'
                puts "versio: rikki"
                exit 0
            when '--no-dump'
                dump_file = "/dev/null"
            when '--request'
                request = arg
            end

        end

    #handle exceptions raised by getoptlong library
    rescue StandardError => e
        print_usage
        exit 0
    end

    #finally check last arguments and create new client
    if ARGV.length < 3
        puts "Missing arguments after getoptlong (try #{$0} --help)"
        exit 0
    end

    player_name = ARGV[0]
    server_host = ARGV[1]
    server_port = ARGV[2]
    client = PongClient.new(player_name, server_host, server_port, dump_file, logger_level, ai ,request)
end
