#
# Copyright (c) 2014 Red Hat Inc.
#
# This file is part of hammer-cli-import.
#
# hammer-cli-import is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# hammer-cli-import is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with hammer-cli-import.  If not, see <http://www.gnu.org/licenses/>.
#

require 'hammer_cli'

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
  require 'hammer_cli_import/contenthost'
  require 'hammer_cli_import/hostcollection'
  require 'hammer_cli_import/organization'
  require 'hammer_cli_import/repository'
  require 'hammer_cli_import/repositoryenable'
  require 'hammer_cli_import/templatesnippet.rb'
  require 'hammer_cli_import/user'
  require 'hammer_cli_import/version'

  # This has to be after all subcommands
  require 'hammer_cli_import/autoload'
end
# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
