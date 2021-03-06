class MiqActionDecorator < Draper::Decorator
  delegate_all

  def fonticon
    case action_type
    when 'assign_scan_profile'
      'fa fa-list-ul'
    when 'create_snapshot'
      'fa fa-camera'
    when 'custom_automation'
      'fa fa-recycle'
    when 'delete_snapshots_by_age'
      'fa fa-camera'
    when 'email'
      'fa fa-envelope-o'
    when 'evaluate_alerts'
      'pficon pficon-warning-triangle-o'
    when 'inherit_parent_tags'
      'fa fa-tags'
    when 'reconfigure_cpus'
      'fa pficon-cpu'
    when 'reconfigure_memory'
      'pficon pficon-memory'
    when 'remove_tags'
      'fa fa-tags'
    when 'script'
      'fa fa-file-text-o'
    when 'set_custom_attribute'
      'product product-attribute'
    when 'snmp_trap'
      'fa fa fa-envelope-o'
    when 'tag'
      'fa fa-tag'
    when 'vm_collect_running_processes'
      'fa fa-cogs'
    when 'default'
      'product product-action'
    end
  end
end
