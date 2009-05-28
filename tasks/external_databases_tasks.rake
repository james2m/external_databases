require 'pp'
namespace :db do
  namespace :external do

    namespace :create do
      desc 'Create all the local external databases defined in config/database.yml'
      task :all => :environment do
        external_configurations.each_value do |config|
          next unless config['database']
          # Only connect to local databases
          if %w( 127.0.0.1 localhost ).include?(config['host']) || config['host'].blank?
            create_database(config)
          else
            p "This task only creates local databases. #{config['database']} is on a remote host."
          end
        end
      end
    end

    desc "Create the external databases defined in config/database.yml for the current RAILS_ENV. /
    Specify DB=db_name to create only that database, otherwise all the environments external databases are created."
    task :create => :environment do
      external_configurations(:environment => ENV['RAILS_ENV'], :database => ENV['DB']).each_value do |config|
        create_database(config)
      end
    end

    def create_database(config)
      begin
        ActiveRecord::Base.establish_connection(config)
        ActiveRecord::Base.connection
      rescue
        case config['adapter']
        when 'mysql'
          @charset   = ENV['CHARSET']   || 'utf8'
          @collation = ENV['COLLATION'] || 'utf8_general_ci'
          begin
            ActiveRecord::Base.establish_connection(config.merge({'database' => nil}))
            ActiveRecord::Base.connection.create_database(config['database'], {:charset => @charset, :collation => @collation})
            ActiveRecord::Base.establish_connection(config)
          rescue
            $stderr.puts "Couldn't create database for #{config.inspect}"
          end
        when 'postgresql'
          `createdb "#{config['database']}" -E utf8`
        when 'sqlite'
          `sqlite "#{config['database']}"`
        when 'sqlite3'
          `sqlite3 "#{config['database']}"`
        else
          raise "Database adapter #{config['adapter']} not supported, feel free to submit a patch!"
        end
        p "Database #{config['database']} created."
      else
        p "#{config['database']} already exists"
      end
    end

    namespace :drop do
      desc 'Drops all the local external databases defined in config/database.yml'
      task :all => :environment do
        external_configurations.each_value do |config|
          # Skip entries that don't have a database key
          next unless config['database']
          # Only connect to local databases
          if config['host'] == 'localhost' || config['host'].blank?
            drop_database(config)
          else
            p "This task only drops local databases. #{config['database']} is on a remote host."
          end
        end
      end
    end

    desc "Drops the external databases for the current RAILS_ENV. /
    Specify DB=db_name to only drop that database, otherwise all the environments external databases are dropped."
    
    task :drop => :environment do
      external_configurations(:environment => ENV['RAILS_ENV'] || 'development', :database => ENV['DB']).each_value do |config|
        drop_database(config)
      end
    end
    desc "Drops and recreates the database from db/db_name/schema.rb for the current environment. /
    Specify DB=db_name to limit reset to that database."
    task :reset => ['db:external:drop', 'db:external:create', 'db:external:schema:load']

    desc "Retrieves the charset for the current environment's external database /
    Specify DB=db_name to retrieve the charset for only that external databases are dropped."
    task :charset => :environment do
      external_configurations(:environment => ENV['RAILS_ENV'] || 'development', :database => ENV['DB']).each do |config|
        case config['adapter']
        when 'mysql'
          ActiveRecord::Base.establish_connection(config)
          puts ActiveRecord::Base.connection.charset
        else
          puts "Database adapter #{config['adapter']} is not supported yet, feel free to submit a patch!"
        end
      end
    end

    desc "Retrieves the collation for the current environment's database"
    task :collation => :environment do
      external_configurations(:environment => ENV['RAILS_ENV'] || 'development', :database => ENV['DB']).each do |config|
        case config['adapter']
        when 'mysql'
          ActiveRecord::Base.establish_connection(config)
          puts ActiveRecord::Base.connection.collation
        else
          puts 'sorry, your database adapter is not supported yet, feel free to submit a patch'
        end
      end
    end

    namespace :fixtures do
      desc "Load fixtures into the current environment's external databases. /
      Load fixtures for specific database using DB=db_name. /
      Load specific fixtures using FIXTURES=fixture_x,fixture_y."
      task :load => :environment do
        require 'active_record/fixtures'
        external_configurations(:environment => ENV['RAILS_ENV'] || 'development', :database => ENV['DB']).each_key do |connection|
          namespace = connection.split("_").last
          load_fixtures connection, namespace
        end
        def load_fixtures(connection, db)
          ActiveRecord::Base.establish_connection(connection.to_sym)
          fixtures = ENV['FIXTURES'] ? ENV['FIXTURES'].split(/,/) : Dir.glob(File.join(RAILS_ROOT, 'test', 'fixtures', namespace, '*.{yml,csv}'))
          fixtures.each do |fixture_file|
            Fixtures.create_fixtures("test/fixtures/#{namespace}", File.basename(fixture_file, '.*'))
          end
        end
      end
    end

    namespace :schema do
      desc "Create a db/db_name/schema.rb file that can be portably used against any DB supported by AR. /
      Use DB=db_name to limit to just the one external database. Dumps schema file in a db/db_name sub directory."
      task :dump => :environment do
        require 'active_record/schema_dumper'
        external_configurations(:database => ENV['DB']).each_key do |connection|
          dir = File.join(RAILS_ROOT, 'db', connection.split('_').last)
          Dir.mkdir(dir) unless File.exists?(dir)
          File.open(ENV['SCHEMA'] || File.join(dir, "schema.rb"), "w") do |file|
            ActiveRecord::SchemaDumper.dump(external_connection_base_class(connection).connection, file)
          end
        end
      end

      desc "Load a schema.rb file into the external database. Use RAILS_ENV= & DB= to limit /
       the loading to a specific environment or db."
      task :load => :environment do
        external_configurations(:database => ENV['DB'], :environment => ENV['RAILS_ENV'] || 'development').each do |connection, config|
          ActiveRecord::Base.establish_connection(config)        
          file = File.join(RAILS_ROOT, 'db', connection.split('_').last, "schema.rb")
          load(file)
        end
      end
    end

    namespace :structure do
      desc "Dump the external database structure to a SQL file. Use RAILS_ENV= & DB= to limit /
       the dump to a specific environment or db."
      task :dump => :environment do
        external_configurations(:database => ENV['DB'], :environment => ENV['RAILS_ENV'] || 'development').each do |connection, config|
          namespace = connection.split("_").last
          case config["adapter"]
          when "mysql", "oci", "oracle"
            ActiveRecord::Base.establish_connection(connection)
            File.open("db/#{namespace}/#{RAILS_ENV}_structure.sql", "w+") { |f| f << ActiveRecord::Base.connection.structure_dump }
          when "postgresql"
            ENV['PGHOST']     = config["host"] if config["host"]
            ENV['PGPORT']     = config["port"].to_s if config["port"]
            ENV['PGPASSWORD'] = config["password"].to_s if config["password"]
            search_path = config["schema_search_path"]
            search_path = "--schema=#{search_path}" if search_path
            `pg_dump -i -U "#{config["username"]}" -s -x -O -f db/#{namespace}/#{RAILS_ENV}_structure.sql #{search_path} #{config["database"]}`
            raise "Error dumping database" if $?.exitstatus == 1
          when "sqlite", "sqlite3"
            dbfile = config["database"] || config["dbfile"]
            `#{config["adapter"]} #{dbfile} .schema > db/#{namespace}/#{RAILS_ENV}_structure.sql`
          when "sqlserver"
            `scptxfr /s #{config["host"]} /d #{config["database"]} /I /f db\\#{namespace}\\#{RAILS_ENV}_structure.sql /q /A /r`
            `scptxfr /s #{config["host"]} /d #{config["database"]} /I /F db\ /q /A /r`
          when "firebird"
            set_firebird_env(config)
            db_string = firebird_db_string(config)
            sh "isql -a #{db_string} > db/#{namespace}/#{RAILS_ENV}_structure.sql"
          else
            raise "Task not supported by '#{config["adapter"]}'"
          end

          if ActiveRecord::Base.connection.supports_migrations?
            File.open("db/#{namespace}/#{RAILS_ENV}_structure.sql", "a") { |f| f << ActiveRecord::Base.connection.dump_schema_information }
          end
        end
      end
    end

    namespace :test do
      desc "Recreate the external test databases from the current environment's database schema. /
      Use DB=db_name to limit the loading to a specific database."
      task :clone => %w(db:external:schema:dump db:external:test:purge) do
        ActiveRecord::Base.establish_connection(ActiveRecord::Base.configurations['test'])
        ActiveRecord::Schema.verbose = false
        Rake::Task["db:external:schema:load"].invoke
      end

      desc "Recreate the test databases from the development structure"
      task :clone_structure => [ "db:external:structure:dump", "db:external:test:purge" ] do
        external_configurations(:database => ENV['DB'], :environment => 'test').each do |connection, config|
          namespace = connection.split("_").last
          case config["adapter"]
          when "mysql"
            ActiveRecord::Base.establish_connection(connection)
            ActiveRecord::Base.connection.execute('SET foreign_key_checks = 0')
            IO.readlines("db/#{namespace}/#{RAILS_ENV}_structure.sql").join.split("\n\n").each do |table|
              ActiveRecord::Base.connection.execute(table)
            end
          when "postgresql"
            ENV['PGHOST']     = config["host"] if config["host"]
            ENV['PGPORT']     = config["port"].to_s if config["port"]
            ENV['PGPASSWORD'] = config["password"].to_s if config["password"]
            `psql -U "#{config["username"]}" -f db/#{namespace}/#{RAILS_ENV}_structure.sql #{config["database"]}`
          when "sqlite", "sqlite3"
            dbfile = config["database"] || config["dbfile"]
            `#{config["adapter"]} #{dbfile} < db/#{namespace}/#{RAILS_ENV}_structure.sql`
          when "sqlserver"
            `osql -E -S #{config["host"]} -d #{config["database"]} -i db\\#{namespace}\\#{RAILS_ENV}_structure.sql`
          when "oci", "oracle"
            ActiveRecord::Base.establish_connection(config)
            IO.readlines("db/#{namespace}/#{RAILS_ENV}_structure.sql").join.split(";\n\n").each do |ddl|
              ActiveRecord::Base.connection.execute(ddl)
            end
          when "firebird"
            set_firebird_env(config)
            db_string = firebird_db_string(config)
            sh "isql -i db/#{namespace}/#{RAILS_ENV}_structure.sql #{db_string}"
          else
            raise "Task not supported by '#{config["adapter"]}'"
          end
        end
      end

      desc "Empty the test database"
      task :purge => :environment do
        external_configurations(:database => ENV['DB'], :environment => 'test').each do |connection, config|
          namespace = connection.split("_").last
          case config["adapter"]
          when "mysql"
            ActiveRecord::Base.establish_connection(connection)
            ActiveRecord::Base.connection.recreate_database(config["database"])
          when "postgresql"
            ENV['PGHOST']     = config["host"] if config["host"]
            ENV['PGPORT']     = config["port"].to_s if config["port"]
            ENV['PGPASSWORD'] = config["password"].to_s if config["password"]
            enc_option = "-E #{config["encoding"]}" if config["encoding"]

            ActiveRecord::Base.clear_active_connections!
            `dropdb -U "#{config["username"]}" #{config["database"]}`
            `createdb #{enc_option} -U "#{config["username"]}" #{config["database"]}`
          when "sqlite","sqlite3"
            dbfile = config["database"] || config["dbfile"]
            File.delete(dbfile) if File.exist?(dbfile)
          when "sqlserver"
            dropfkscript = "#{config["host"]}.#{config["database"]}.DP1".gsub(/\\/,'-')
            `osql -E -S #{config["host"]} -d #{config["database"]} -i db\\#{dropfkscript}`
            `osql -E -S #{config["host"]} -d #{config["database"]} -i db\\#{namespace}\\#{RAILS_ENV}_structure.sql`
          when "oci", "oracle"
            ActiveRecord::Base.establish_connection(connection)
            ActiveRecord::Base.connection.structure_drop.split(";\n\n").each do |ddl|
              ActiveRecord::Base.connection.execute(ddl)
            end
          when "firebird"
            ActiveRecord::Base.establish_connection(connection)
            ActiveRecord::Base.connection.recreate_database!
          else
            raise "Task not supported by '#{config["adapter"]}'"
          end
        end
      end

      desc 'Prepare the test database and load the schema'
      task :prepare => %w(environment db:abort_if_pending_migrations) do
        if defined?(ActiveRecord) && !ActiveRecord::Base.configurations.blank?
          Rake::Task[{ :sql  => "db:external:test:clone_structure", :ruby => "db:external:test:clone" }[ActiveRecord::Base.schema_format]].invoke
        end
      end
    end
  end
end

def external_connection_base_class(connection)
  namespace = connection.split('_').last
  [namespace.classify, 'Base'].join('::').constantize
end

def external_configurations(scope = {})
  scope.symbolize_keys
  ActiveRecord::Base.configurations.inject({}) do |configs, config|
    config.extend(ConfigurationFilters)    
    if config.external? && config.environment(scope[:environment]) && config.database(scope[:database]) then
      configs.merge(config.first => config.last)
    else
      configs
    end
  end
end

module ConfigurationFilters
  def environment(env)
    env.nil? || Regexp.new("^external_#{env}_").match(self.first)
  end
  def database(db)
    db.nil? || Regexp.new("_#{db}$").match(self.first)
  end
  def external?
    self.first =~ /^external_/
  end
end

def drop_database(config)
  case config['adapter']
  when 'mysql'
    ActiveRecord::Base.connection.drop_database config['database']
  when /^sqlite/
    FileUtils.rm_f(File.join(RAILS_ROOT, config['database']))
  when 'postgresql'
    `dropdb "#{config['database']}"`
  else
    raise "Database adapter #{config['adapter']} not supported, feel free to submit a patch!"
  end
  p "Database #{config['database']} dropped."
end

def set_firebird_env(config)
  ENV["ISC_USER"]     = config["username"].to_s if config["username"]
  ENV["ISC_PASSWORD"] = config["password"].to_s if config["password"]
end

def firebird_db_string(config)
  FireRuby::Database.db_string_for(config.symbolize_keys)
end
