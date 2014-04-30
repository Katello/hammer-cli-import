$:.unshift(File.expand_path('../lib', __FILE__))

require 'lib/hammer_cli_import/version'

Gem::Specification.new do |spec|
  spec.name = 'hammer_cli_import'
  spec.version = HammerCLIImport.version
  spec.authors = ['@mkollar', '@tlestach']
  spec.email = ['mkollar@redhat.com', 'tlestach@redhat.com']

  spec.platform = Gem::Platform::RUBY
  spec.summary = 'Red Hat Satellite 5 data Importer commands for Hammer'
  spec.description = 'Hammer-CLI-Importer is a plugin for Hammer to import Red Hat Satellite 5 data.'
  spec.require_paths = ['lib']

  spec.files = Dir['lib/**/*.rb']
  spec.test_files = []

  spec.add_dependency('hammer_cli')
end
