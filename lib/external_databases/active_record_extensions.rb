module ActiveRecord
  class Base
    
    class << self
      
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
      
      # Delete existing data in database and load fresh from file in db/table_name.yml
      def load_external_fixture(path=nil)
        self.destroy_all
        path ||= File.expand_path("spec/fixtures/#{table_name}.yml", RAILS_ROOT)
        records_hash = {}
        records = YAML::load( File.open( path ) )
        records.each do |key, attributes|
          new_record = self.new(attributes)
          new_record.send("#{primary_key}=".to_sym, attributes[primary_key].to_i)
          keys = { primary_key => attributes[primary_key].to_i }
          reflect_on_all_associations.each do |association|
            if association.macro == :belongs_to
              foreign_key = association.options[:foreign_key]
              keys[foreign_key] = attributes[foreign_key].to_i
              new_record.send("#{foreign_key}=".to_sym, keys[foreign_key])
            end
          end       
          records_hash[key.to_sym] = new_record.attributes.merge(keys) 
          new_record.save   
        end
        records_hash
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
      
    end
    
  end
end
