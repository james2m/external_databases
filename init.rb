require 'external_databases'
connections = ActiveRecord::Base.configurations.keys.inject({}) do |names, name|
  db_prefix = Regexp.new "^external_#{RAILS_ENV}_"
  db_prefix.match(name) ? names.merge(name => $'.camelize) : names
end

connections.each do |connection_name, namespace| 
  Object.module_eval <<-END
    module #{namespace}
      class Base < ActiveRecord::Base
        self.abstract_class = true      
        establish_connection :#{connection_name}
      end
    end
  END
end