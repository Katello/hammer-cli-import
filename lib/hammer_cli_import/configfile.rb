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
require 'apipie-bindings'
require 'open3'

module HammerCLIImport
  class ImportCommand
    class ConfigFileImportCommand < BaseCommand
      command_name 'config-file'
      reportname = 'config-files-latest'
      desc "Import Host Collections (from spacewalk-report #{reportname})."

      option ['--macro-mapping'], 'FILE_NAME',
             'Mapping of Satellite-5 config-file-macros to puppet facts',
             :default => '/etc/hammer/cli.modules.d/config_macros.yml'

      option ['--working-directory'], 'FILE_NAME',
             'Location for building puppet modules (will be created if it doesn\'t exist',
             :default => File.join(File.expand_path('~'), 'puppet_work_dir')

      csv_columns 'org_id', 'channel', 'channel_type', 'path', 'file_type', 'file_id',
                  'revision', 'is_binary', 'contents', 'delim_start', 'delim_end', 'username',
                  'groupname', 'filemode', 'symbolic_link', 'selinux_ctx'

      persistent_maps :organizations

      # Load the macro-mapping once-per-run
      def execute
        if File.exist? option_macro_mapping
          @macros = YAML.load_file(option_macro_mapping)
        else
          @macros = {}
          warn "Macro-mapping file #{option_macro_mapping} not found, no puppet-facts will be assigned"
        end
        Dir.mkdir option_working_directory unless File.directory? option_working_directory
        super()
      end

      def puppet_interview_answers(module_name)
        return ['0.1.0', 'Red Hat', 'GPLv2',
                "Module created from org-cfgchannel #{module_name}",
                'sat5_url', 'sat5_url', 'sat5_url', 'Y']
      end

      # puppet-module-names are username-classname
      # usernames can only be alphanumeric
      # classnames can only be alphanumeric and '_'
      def build_module_name(data)
        owning_org = lookup_entity_in_cache(:organizations,
                                            {'id' => get_translated_id(:organizations, data['org_id'].to_i)})
        org_name = owning_org['name'].gsub(/[^0-9a-zA-Z]*/, '').downcase
        chan_name = data['channel'].gsub(/[^0-9a-zA-Z_]/, '_').downcase
        return org_name + '-' + chan_name
      end

      # Return a mapped puppet-fact for a macro, if there is one
      # Otherwise, leave the macro in place
      def map_macro(macro)
        if @macros.key? macro
          return @macros[macro]
        else
          return macro
        end
      end

      def mk_sg_hash(data)
        {
          :name => data['name'],
          :organization_id => get_translated_id(:organizations, data['org_id'].to_i)
        }
      end

      # If module 'name' has been generated,
      # throw away it filesystem existence
      def clean_module(name)
        path = File.join(option_working_directory, name)
        debug "Removing #{path}"
        system("rm -rf #{path}")
      end

      include Open3
      # Create a puppet module-template on the filesystem,
      # inside of working-directory
      def generate_module_template_for(name)
        debug 'In gen-module'
        Dir.chdir(option_working_directory)
        gen_cmd = "puppet module --verbose --debug generate #{name}"
        debug "About to issue cmd #{gen_cmd}"
        Open3.popen3(gen_cmd) do |stdin, stdout, _stderr|
          stdout.sync = true
          puppet_interview_answers(name).each do |a|
            rd = ''
            until rd.include? '?'
              rd = stdout.readline
              debug "Read #{rd}"
            end
            debug "Answering #{a}"
            stdin.puts(a)
          end
          rd = ''
          begin
            while rd
              rd = stdout.readline
              debug "Read #{rd}"
            end
          rescue EOFError
            debug 'Done reading'
          end
        end
      end

      # If we haven't seen this module-name before,
      # arrange to do 'puppet generate module' for it
      def generate_module(module_name)
        return if @modules.key? module_name
        @modules[module_name] = []
        clean_module(module_name)
        generate_module_template_for(module_name)
      end

      def mk_hash(data)
        # Everybody gets a name, which is 'path' with '/' chgd to '_'
        data['name'] = data['path'].gsub('/', '_')
        # If we're not type='file', done - return data
        return data unless data['file_type'] == 'file'
        # If we're not a binary-file, check for macros
        if data['is_binary'] == 'N'
          sdelim = data['delim_start']
          edelim = data['delim_end']
          cstr = data['contents']
          matched = false
          data['contents'] = cstr.gsub(/(#{Regexp.escape(sdelim)})(.*)(#{Regexp.escape(edelim)})/) do |_match|
            matched = true
            "<%= #{map_macro Regexp.last_match[2].strip!} %>"
          end
          # If we replaced any macros, we're now type='template'
          data['file_type'] = 'template' if matched
        else
          # If we're binary, base64-decode contents
          debug 'decoding'
          data['contents'] = data['contents'].unpack('m')
        end
        return data
      end

      def import_single_row(data)
        @modules ||= {}
        #create_entity(:host_collections, sg, data['group_id'].to_i)
        mname = build_module_name(data)
        generate_module(mname)
        file_hash = mk_hash(data)
        debug "name #{data['name']}, path #{file_hash['path']}, type #{file_hash['file_type']}"
        @modules[mname] << file_hash
      end

      def delete_single_row(_data)
        #delete_entity(:host_collections, data['group_id'].to_i)
      end

      def post_import(_csv)
        @modules.each do |mname, files|
          debug "MODULE #{mname}"
          module_dir = File.join(option_working_directory, mname)
          fdir = File.join(module_dir, 'files')
          Dir.mkdir(fdir)
          tdir = File.join(module_dir, 'templates')
          Dir.mkdir(tdir)
          files.each do |a_file|
            debug "...file #{a_file['name']}"
            case a_file['file_type']
            when 'file'
              File.open(File.join(fdir, a_file['name']), 'w') do |f|
                f.syswrite(a_file['contents'])
              end
            when 'template'
              File.open(File.join(tdir, a_file['name']), 'w') do |f|
                f.syswrite(a_file['contents'])
              end
            when 'directory'
            when'symlink'
            else
            end
          end
        end
      end
    end
  end
end
# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
