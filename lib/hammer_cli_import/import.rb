require 'hammer_cli'
require 'hammer_cli/exit_codes'

module HammerCLIImport
  class ImportCommand < HammerCLI::AbstractCommand
  end

  HammerCLI::MainCommand.subcommand('import',
                                    'Import data exported from a Red Hat Satellite 5 instance',
                                    HammerCLIImport::ImportCommand)
end
