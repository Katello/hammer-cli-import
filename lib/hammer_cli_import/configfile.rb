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
      desc "Create puppet-modules from Configuration Channel content (from spacewalk-report #{reportname})."

      option ['--generate-only'], :flag,
             'Create and fill puppet-modules, but DO NOT upload anything',
             :default => false

      option ['--macro-mapping'], 'FILE_NAME',
             'Mapping of Satellite-5 config-file-macros to puppet facts',
             :default => '/etc/hammer/cli.modules.d/import/config_macros.yml'

      option ['--working-directory'], 'FILE_NAME',
             'Location for building puppet modules (will be created if it doesn\'t exist',
             :default => File.join(File.expand_path('~'), 'puppet_work_dir')

      option ['--answers-file'], 'FILE_NAME',
             'Answers to the puppet-generate-module interview questions',
             :default => '/etc/hammer/cli.modules.d/import/interview_answers.yml' \
             do |answers_file|
               raise ArgumentError, "File #{answers_file} does not exist" unless !option_delete? && File.exist?(answers_file)
               answers_file
             end

      csv_columns 'org_id', 'channel', 'channel_id', 'channel_type', 'path', 'file_type', 'file_id',
                  'revision', 'is_binary', 'contents', 'delim_start', 'delim_end', 'username',
                  'groupname', 'filemode', 'symbolic_link', 'selinux_ctx'

      persistent_maps :organizations, :products, :puppet_repositories

      class << self; attr_accessor :interview_questions end
      @interview_questions = %w(version author license summary srcrepo learnmore fileissues Y)

      # Load the macro-mapping and interview-answers ONLY once-per-run
      def first_time_only
        unless option_delete?
          # Load interview-answers
          @interview_answers = YAML.load_file(option_answers_file)
          @interview_answers['Y'] = 'Y'

          # Load macro-mappings
          if File.exist? option_macro_mapping
            @macros = YAML.load_file(option_macro_mapping)
          else
            @macros = {}
            warn "Macro-mapping file #{option_macro_mapping} not found, no puppet-facts will be assigned"
          end

          # Create the puppet-working-directory
          Dir.mkdir option_working_directory unless File.directory? option_working_directory
        end
        return 'loaded'
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
        module_name = name
        Dir.chdir(option_working_directory)
        gen_cmd = "puppet module generate #{name}"
        Open3.popen3(gen_cmd) do |stdin, stdout, _stderr|
          stdout.sync = true
          ConfigFileImportCommand.interview_questions.each do |q|
            rd = ''
            until rd.include? '?'
              rd = stdout.readline
              #debug "Read #{rd}"
            end
            answer = @interview_answers[q].gsub('#{module_name}', module_name)
            stdin.puts(answer)
          end
          rd = ''
          begin
            rd = stdout.readline while rd
          rescue EOFError
            debug 'Done reading'
          end
        end

        # Now that we have generated the module, add a 'description' to the
        # metadata.json file found at option_working_dir/<name>/metadata.json
        metadata_path = File.join(File.join(option_working_directory, name), 'metadata.json')
        answer = @interview_answers['description'].gsub('#{module_name}', module_name)
        sed_cmd = "sed -i '\/\"summary\":\/a \\ \\ \"description\": \"#{answer}\",' #{metadata_path}"
        debug "About to issue #{sed_cmd}"
        system sed_cmd
        report_summary :created, :puppet_modules
      end

      def build_puppet_module(module_name)
        module_dir = File.join(option_working_directory, module_name)
        Dir.chdir(module_dir)
        gen_cmd = 'puppet module build'
        Open3.popen3(gen_cmd) do |_stdin, stdout, _stderr|
          rd = ''
          begin
            rd = stdout.readline while rd
            debug rd
          rescue EOFError
            debug 'Done reading'
          end
        end
        return module_dir
      end

      # If we haven't seen this module-name before,
      # arrange to do 'puppet generate module' for it
      def generate_module(module_name)
        return if @modules.key? module_name

        @modules[module_name] = []
        clean_module(module_name)
        generate_module_template_for(module_name)
      end

      def file_data(data)
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
          end if cstr
          # If we replaced any macros, we're now type='template'
          data['file_type'] = 'template' if matched
        else
          # If we're binary, base64-decode contents
          debug 'decoding'
          data['contents'] = data['contents'].unpack('m')
        end

        return data
      end

      def mk_product_hash(data, product_name)
        {
          :name => product_name,
          :organization_id => get_translated_id(:organizations, data['org_id'].to_i)
        }
      end

      def mk_repo_hash(data, product_id)
        {
          :name => data['channel'],
          :product_id => product_id,
          :content_type => 'puppet'
        }
      end

      # Store all files into a hash keyed by module-name
      def import_single_row(data)
        @first_time ||= first_time_only
        @modules ||= {}

        mname = build_module_name(data)
        generate_module(mname)
        file_hash = file_data(data)
        debug "name #{data['name']}, path #{file_hash['path']}, type #{file_hash['file_type']}"
        @modules[mname] << file_hash
      end

      def delete_single_row(data)
        # repo maps to channel_id
        composite_id = [data['org_id'].to_i, data['channel_id'].to_i]
        unless @pm[:puppet_repositories][composite_id]
          info "#{to_singular(:puppet_repositories).capitalize} with id #{composite_id} wasn't imported. Skipping deletion."
          return
        end

        # find out product id
        repo_id = get_translated_id(:puppet_repositories, composite_id)
        product_id = lookup_entity(:puppet_repositories, repo_id)['product']['id']
        # delete repo
        delete_entity(:puppet_repositories, composite_id)
        # delete its product, if it's not associated with any other repositories
        product = lookup_entity(:products, product_id, true)

        delete_entity_by_import_id(:products, product_id) if product['repository_count'] == 0
      end

      def write_file(dir, name, content)
        File.open(File.join(dir, name), 'w') do |f|
          f.syswrite(content)
        end
      end

      # For each module, write file-content to <module>/files or <module>/templates,
      # and fill <module>/manifests/init.pp with appropriate metadata
      def export_files
        progress 'Writing converted files'
        @modules.each do |mname, files|
          info "Found module #{mname}"
          dsl = ''

          module_dir = File.join(option_working_directory, mname)
          fdir = File.join(module_dir, 'files')
          Dir.mkdir(fdir)
          tdir = File.join(module_dir, 'templates')
          Dir.mkdir(tdir)
          class_name = mname.partition('-').last

          files.each do |a_file|
            debug "...file #{a_file['name']}"

            dsl += "file { '#{a_file['name']}':\n"
            dsl += "  path => '#{a_file['path']}',\n"

            case a_file['file_type']
            when 'file'
              write_file(fdir, a_file['name'], a_file['contents'])
              dsl += "  source => 'puppet:///modules/#{mname}/#{a_file['name']}',\n"
              dsl += "  group => '#{a_file['groupname']}',\n"
              dsl += "  owner => '#{a_file['username']}',\n"
              dsl += "  ensure => 'file',\n"
              dsl += "  mode => '#{a_file['filemode']}',\n"
              dsl += "}\n\n"
            when 'template'
              write_file(tdir, a_file['name'] + '.erb', a_file['contents'])
              dsl += "  group => '#{a_file['groupname']}',\n"
              dsl += "  owner => '#{a_file['username']}',\n"
              dsl += "  ensure => 'file',\n"
              dsl += "  mode => '#{a_file['filemode']}',\n"
              dsl += "  content => template('#{mname}/#{a_file['name']}.erb'),\n"
              dsl += "}\n\n"
            when 'directory'
              dsl += "  group => '#{a_file['groupname']}',\n"
              dsl += "  owner => '#{a_file['username']}',\n"
              dsl += "  ensure => 'directory',\n"
              dsl += "  mode => '#{a_file['filemode']}',\n"
              dsl += "}\n\n"
            when'symlink'
              dsl += "  target => '#{a_file['symbolic_link']}',\n"
              dsl += "  ensure => 'link',\n"
              dsl += "}\n\n"
            else
            end
            report_summary :created, :puppet_files
          end
          export_manifest(mname, class_name, dsl)
        end
      end

      def export_manifest(mname, channel_name, dsl)
        debug "Exporting manifest #{option_working_directory}/#{mname}/manifests/init.pp"
        module_dir = File.join(option_working_directory, mname)
        mdir = File.join(module_dir, 'manifests')
        File.open(File.join(mdir, 'init.pp'), 'w') do |f|
          f.puts "class #{channel_name} {"
          f.puts dsl
          f.puts '}'
        end
      end

      # We're going to build a product-per-org, with a repo-per-channel
      # and upload the built-puppet-module, one-per-repo
      #
      # We're using the hammer-repository-upload subcommand to do this,
      # because the direct-API-route is 'touchy' and repo-upload already
      # does all the Right Stuff
      def build_and_upload
        progress 'Building and uploading puppet modules'
        prod_name = 'Imported Satellite5 Configuration Files'
        @modules.each do |mname, files|
          data = files[0]

          # Build the puppet-module for upload
          module_dir = build_puppet_module(mname)

          # Build/find the product
          product_hash = mk_product_hash(data, prod_name)
          composite_id = [data['org_id'].to_i, prod_name]
          product_id = create_entity(:products, product_hash, composite_id)['id']
          debug product_id

          # Build the repo
          repo_hash = mk_repo_hash data, product_id
          repo = create_entity(:puppet_repositories, repo_hash,
                               [data['org_id'].to_i, data['channel_id'].to_i])

          # Find the built-module .tar.gz
          built_module_path = File.join(File.join(module_dir, 'pkg'),
                                        "#{mname}-#{@interview_answers['version']}.tar.gz")
          info "Uploading #{built_module_path}"
          # Ask hammer repository upload to Do Its Thing
          system "hammer --username #{api_usr} --password #{api_pwd} " \
                 "repository upload-content --id #{repo['id']} --path #{built_module_path}"
          report_summary :uploaded, :puppet_modules
        end
      end

      def post_import(_csv)
        return unless @modules
        export_files
        build_and_upload unless option_generate_only?
      end
    end
  end
end
# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
