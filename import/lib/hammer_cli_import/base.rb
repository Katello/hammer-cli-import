# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
require 'hammer_cli'
require 'apipie-bindings'

module HammerCLIImport
  class BaseCommand < HammerCLI::Apipie::Command

    option %w(-h --help), :flag, 'Get usage'

    def usage
      puts "Usage: Import Sat5-exported entities into Sat6"
      puts " Implemented commands:"
      puts "   zzz:example            : Sample to show we know how to write a command"
      puts "   zzz:orgsusers          : Import Users and Orgs"
      puts "   zzz:systemgroups       : Import System-Groups"
      puts " Unimplemented commands:"
      puts "   zzz:repositories       : Import Repositories"
      puts "   zzz:customchannels     : Import Custom Channels "
      puts "   zzz:clonedchannels     : Import Cloned Channels"
      puts "   zzz:activationkeys     : Import Activation Keys"
      puts "   zzz:kickstartprofiles  : Import Kickstart Profiles"
      puts "   zzz:serverprofiles     : Import Server Profiles"
      puts "   zzz:configchannels     : Import COnfig Channels/Files"
    end

    def execute
      if option_help?
        usage
        HammerCLI::EX_OK
      else
        @api = ApipieBindings::API.new({
          :uri => HammerCLI::Settings.get(:foreman, :host),
          :username => HammerCLI::Settings.get(:foreman, :username),
          :password => HammerCLI::Settings.get(:foreman, :password),
          :api_version => 2
        })
        run_command
      end
    end
  end
  HammerCLI::MainCommand.subcommand("zzz:base", "Top-level Sat5-Import", HammerCLIImport::BaseCommand)
end

