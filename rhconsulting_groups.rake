require_relative 'rhconsulting_illegal_chars'
require_relative 'rhconsulting_options'

class GroupImportExport
  class ParsedNonDialogYamlError < StandardError; end

  def import(filename)
    raise "Must supply filename or directory" if filename.blank?
    if File.file?(filename)
      groups = YAML.load_file(filename)
      import_groups(groups)
    elsif File.directory?(filename)
      Dir.glob("#{filename}/*.yaml") do |fname|
        groups = YAML.load_file(fname)
        import_groups(groups)
      end
    else
      raise "Argument is not a filename or directory"
    end
  end

  def export(filename, options = {})
    raise "Must supply filename or directory" if filename.blank?
    begin
      file_type = File.ftype(filename)
    rescue
      # If we get an error back assume it is a filename that does not exist
      file_type = 'file'
    end

    groups_array = export_groups(MiqGroup.order(:id).all)

    if file_type == 'file'
      File.write(filename, groups_array.to_yaml)
    elsif file_type == 'directory'
      groups_array.each do |group_hash|
        group_name = group_hash["name"]
        # Replace invalid filename characters
        group_name = MiqIllegalChars.replace(group_name, options)
        fname = "#{filename}/#{group_name}.yaml"
        File.write(fname, [group_hash].to_yaml)
      end
    else
      raise "Argument is not a filename or directory"
    end
  end

private

  def import_groups(groups)
    begin
      groups.each do |r|
        group = MiqGroup.find_or_create_by(description: r['description'])
        tenant_name = r.delete('tenant_name')
        tenant = Tenant.find_by(name:tenant_name)
        if tenant.nil?
          tenant_id = Tenant.first.id
        else
          tenant_id = tenant.id
        end
        group.tenant_id = tenant_id

        miq_user_role_name = r.delete('miq_user_role_name')
        group.miq_user_role = MiqUserRole.find_by(name:miq_user_role_name)

        group.save!
      end
    rescue
      raise ParsedNonDialogYamlError
    end
  end

  #<MiqGroup description: "test-new", group_type: "user", sequence: 25, settings: nil, tenant_id: 1>
  def export_groups(groups)
    groups.collect do |group|
      next unless group.group_type == "user"
      included_attributes(group.attributes, ["created_on", "id", "updated_on","sequence","tenant_id"]).merge('miq_user_role_name' => group.miq_user_role_name, 'tenant_name' => Tenant.find_by_id(group.tenant_id).name)
    end.compact
  end

  def included_attributes(attributes, excluded_attributes)
    attributes.reject { |key, _| excluded_attributes.include?(key) }
  end

end

namespace :rhconsulting do
  namespace :groups do

    desc 'Usage information'
    task :usage => [:environment] do
      puts 'Export - Usage: rake rhconsulting:groups:export[/path/to/export]'
      puts 'Import - Usage: rake rhconsulting:groups:import[/path/to/export]'
    end

    desc 'Import all groups from a YAML file or directory'
    task :import, [:filename] => [:environment] do |_, arguments|
      GroupImportExport.new.import(arguments[:filename])
    end

    desc 'Exports all groups to a YAML file or directory'
    task :export, [:filename] => [:environment] do |_, arguments|
      options = RhconsultingOptions.parse_options(arguments.extras)
      GroupImportExport.new.export(arguments[:filename], options)
    end

  end
end
