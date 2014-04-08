require 'hammer_cli'
require 'hammer_cli/exit_codes'

module HammerCLIImport
  class Sat5Command < HammerCLI::AbstractCommand
  end

  HammerCLI::MainCommand.subcommand('sat5',
                                    'Import data exported from a Satellite5 instance',
                                    HammerCLIImport::Sat5Command)
end
