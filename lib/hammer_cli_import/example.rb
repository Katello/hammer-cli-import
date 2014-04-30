# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
require 'hammer_cli'
require 'apipie-bindings'

module HammerCLIImport
  class ExampleCommand < HammerCLI::Apipie::Command

    def execute
      puts 'Hello Hammer'
      @api = ApipieBindings::API.new({
        :uri => HammerCLI::Settings.get(:foreman, :host),
        :username => HammerCLI::Settings.get(:foreman, :username),
        :password => HammerCLI::Settings.get(:foreman, :password),
        :api_version => 2
      })
      puts @api.resource(:organizations).call(:index)['results'].length
      HammerCLI::EX_OK
    end
  end
  HammerCLI::MainCommand.subcommand('zzz:example', 'Example command', HammerCLIImport::ExampleCommand)
end

