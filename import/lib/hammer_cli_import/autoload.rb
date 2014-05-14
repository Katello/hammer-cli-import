# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby

# This has to be included after all other subcommands were loaded
# to work properly.
module HammerCLIImport
  class ImportCommand
    autoload_subcommands
  end
end
