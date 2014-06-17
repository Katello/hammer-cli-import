# hammer-cli-import

Tool for importing data from an existing Spacewalk/Satellite system.

THIS TOOL IS WORK IN PROGRESS.

## Setup info

To enable modules do the following:

    mkdir -p ~/.hammer
    cat >> ~/.hammer/cli_config.yml << EOF
    :modules:
      - hammer_cli_import
    EOF

And running with

    # env RUBYOPT=-Ilib hammer import

To build/install as a gem:

    # gem build hammer_cli_import.gemspec
    # gem install hammer_cli_import-0.0.1.gem
    # hammer import

## RuboCop

[RuboCop][rubocop] requires at least Ruby 1.9.2. That is available in SCL.

    # yum install -y ruby193-ruby-devel
    # scl enable ruby193 "gem install rubocop"

It needs to be run with newer Ruby too (it will pick up its configuration
automatically when run from the root of repository).

    # scl enable ruby193 "/opt/rh/ruby193/root/usr/local/share/gems/gems/*/bin/rubocop"

## Development

You can add to your `~/.irbrc`:

    class Object
      def imethods
        methods - Object.instance_methods
      end
    end

    def methods_re(re)
      methods.find do |m|
        re.match m
      end
    end

[rubocop]: http://batsov.com/rubocop/ "Ruby code analyzer"
