require 'external_databases/active_record_extensions'
def external_fixtures_for(namespace, fixture_names)
  ActiveRecord::Base.external_configurations(:environment => 'test', :database => ENV['DB']).each_key do |connection|  
    load_all_external_fixtures( connection, namespace, fixture_names ) if namespace.to_s == connection.split("_").last 
  end  
end

def load_all_external_fixtures(connection, namespace, fixture_names)
  fixture_path = File.expand_path File.join(RAILS_ROOT, "spec/fixtures", namespace.to_s)
  ActiveRecord::Base.establish_connection(connection.to_sym)
  fixture_names.each do |class_name, table_name|
    fixtures_name = "#{class_name.to_s.pluralize}"
    model_class = [namespace.to_s.classify, class_name.to_s.classify].join('::').constantize
    instance_variable_set "@#{fixtures_name}",model_class.load_external_fixture( File.join(fixture_path, "#{table_name}.yml") )
    instance_eval("def #{fixtures_name} (fixture); @#{fixtures_name}[fixture]; end")  
  end
  
end