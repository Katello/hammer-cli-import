require 'hammer_cli'
# require 'hammer_cli/exit_codes'

module HammerCLIImport
  # def self.exception_handler_class
  #   HammerCLIImport::ExceptionHandler
  # end

  require 'hammer_cli_import/csvhelper'
  require 'hammer_cli_import/deltahash'
  require 'hammer_cli_import/fixtime'
  require 'hammer_cli_import/importtools'
  require 'hammer_cli_import/persistentmap'

  require 'hammer_cli_import/base'
  require 'hammer_cli_import/import'

  require 'hammer_cli_import/all'
  require 'hammer_cli_import/activationkey'
  require 'hammer_cli_import/contentview'
  require 'hammer_cli_import/hostcollection'
  require 'hammer_cli_import/organization'
  require 'hammer_cli_import/repository'
  require 'hammer_cli_import/repositorydiscovery'
  require 'hammer_cli_import/templatesnippet.rb'
  require 'hammer_cli_import/user'
  require 'hammer_cli_import/version'

  # This has to be after all subcommands
  require 'hammer_cli_import/autoload'
end
