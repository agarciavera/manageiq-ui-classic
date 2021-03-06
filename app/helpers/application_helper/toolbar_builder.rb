class ApplicationHelper::ToolbarBuilder
  include MiqAeClassHelper
  include RestfulControllerMixin

  def call(toolbar_name)
    build_toolbar(toolbar_name)
  end

  # Loads the toolbar sent in parameter `toolbar_name`, and builds the buttons
  # in the toolbar, unless the group of buttons is meant to be skipped.
  #
  # Returns built toolbar loaded in instance variable `@toolbar`, or `nil`, if
  # no buttons should be in the toolbar.
  def build_toolbar(toolbar_name)
    build_toolbar_setup

    toolbar_class = toolbar_class(toolbar_name)
    build_toolbar_from_class(toolbar_class)
  end

  def build_toolbar_by_class(toolbar_class)
    build_toolbar_setup
    build_toolbar_from_class(toolbar_class)
  end

  private

  delegate :request, :current_user, :to => :@view_context
  delegate :role_allows?, :model_for_vm, :rbac_common_feature_for_buttons, :to => :@view_context
  delegate :x_tree_history, :x_node, :x_active_tree, :to => :@view_context
  delegate :is_browser?, :is_browser_os?, :to => :@view_context

  def initialize(view_context, view_binding, instance_data)
    @view_context = view_context
    @view_binding = view_binding
    @instance_data = instance_data

    instance_data.each do |name, value|
      instance_variable_set(:"@#{name}", value)
    end
  end

  def eval(code)
    @view_binding.eval(code)
  end

  def safer_eval(code)
    code.to_s =~ /\#{/ ? eval("\"#{code}\"") : code
  end

  # Parses the generic toolbars name and returns his class
  def predefined_toolbar_class(tb_name)
    class_name = 'ApplicationHelper::Toolbar::' + ActiveSupport::Inflector.camelize(tb_name.sub(/_tb$/, ''))
    class_name.constantize
  end

  # According to toolbar name in parameter `toolbar_name` either returns class
  # for generic toolbar, or starts building custom toolbar
  def toolbar_class(toolbar_name)
    if toolbar_name == "custom_buttons_tb"
      custom_toolbar_class(@record)
    else
      predefined_toolbar_class(toolbar_name)
    end
  end

  # Creates a button and sets it's properties
  def toolbar_button(inputs, props)
    button_class = inputs[:klass] || ApplicationHelper::Button::Basic
    props[:options] = inputs[:options] if inputs[:options]
    button = button_class.new(@view_context, @view_binding, @instance_data, props)
    button.skipped? ? nil : apply_common_props(button, inputs)
  end

  # Build select button and its child buttons
  def build_select_button(bgi, index)
    bs_children = false
    props = toolbar_button(
      bgi,
      :id     => bgi[:id],
      :type   => :buttonSelect,
      :img    => img = img_value(bgi),
      :imgdis => img,
    )
    return nil if props.nil?

    current_item = props
    current_item[:items] ||= []
    any_visible = false
    bgi[:items].each_with_index do |bsi, bsi_idx|
      if bsi.key?(:separator)
        props = ApplicationHelper::Button::Separator.new(:id => "sep_#{index}_#{bsi_idx}", :hidden => !any_visible)
      else
        next if hide_button?(bsi[:pressed] || bsi[:id]) # Use pressed, else button id
        bs_children = true
        props = toolbar_button(
          bsi,
          :child_id => bsi[:id],
          :id       => bgi[:id] + "__" + bsi[:id],
          :type     => :button,
          :img      => img = img_value(bsi),
          :img_url  => ActionController::Base.helpers.image_path("toolbars/#{img}"),
          :imgdis   => img,
        )
        next if props.nil?
      end
      update_common_props(bsi, props) unless bsi.key?(:separator)
      current_item[:items] << props

      any_visible ||= !props[:hidden] && props[:type] != :separator
    end
    current_item[:items].reverse_each do |item|
      break if !item[:hidden] && item[:type] != :separator
      item[:hidden] = true if item[:type] == :separator
    end
    current_item[:hidden] = !any_visible

    if bs_children
      @sep_added = true # Separator has officially been added
      @sep_needed = true # Need a separator from now on
    end
    current_item
  end

  # Set properties for button
  def apply_common_props(button, input)
    button.update(
      :icon    => input[:icon],
      :name    => button[:id],
      :hidden  => button[:hidden] || !!input[:hidden],
      :pressed => input[:pressed],
      :onwhen  => input[:onwhen],
      :data    => input[:data]
    )

    button[:enabled] = input[:enabled]
    %i(title text confirm).each do |key|
      unless input[key].blank?
        button[key] = button.localized(key, input[key])
      end
    end
    button[:url_parms] = update_url_parms(safer_eval(input[:url_parms])) unless input[:url_parms].blank?

    if input[:popup] # special behavior: button opens window_url in a new window
      button[:popup] = true
      button[:window_url] = "/#{request.parameters["controller"]}#{input[:url]}"
    end

    if input[:association_id] # special behavior to pass in id of association
      button[:url_parms] = "?show=#{request.parameters[:show]}"
    end

    dis_title = disable_button(button[:child_id] || button[:id])
    if dis_title
      button[:enabled] = false
      if dis_title.kind_of? String
        button[:title] = button.localized(:title, dis_title)
      end
    end
    button.calculate_properties
    button
  end

  # Build single button
  def build_normal_button(bgi, index)
    button_hide = hide_button?(bgi[:id])
    if button_hide
      # These buttons need to be present even if hidden as we show/hide them dynamically
      return nil unless %w(timeline_txt timeline_csv timeline_pdf).include?(bgi[:id])
    end

    @sep_needed = true unless button_hide
    props = toolbar_button(
      bgi,
      :id      => bgi[:id],
      :type    => :button,
      :img     => img = "#{get_image(bgi[:image], bgi[:id]) ? get_image(bgi[:image], bgi[:id]) : bgi[:id]}.png",
      :img_url => ActionController::Base.helpers.image_path("toolbars/#{img}"),
      :imgdis  => "#{bgi[:image] || bgi[:id]}.png",
    )
    return nil if props.nil?

    # set pdf button to be hidden if graphical summary screen is set by default
    props[:hidden] = %w(download_view vm_download_pdf).include?(bgi[:id]) && button_hide

    _add_separator(index)
    props
  end

  def _add_separator(index)
    # Add a separator, if needed, before this button
    if !@sep_added && @sep_needed
      if @groups_added.include?(index) && @groups_added.length > 1
        @toolbar << ApplicationHelper::Button::Separator.new(:id => "sep_#{index}")
        @sep_added = true
      end
    end
    @sep_needed = true # Button was added, need separators from now on
  end

  def img_value(button)
    "#{button[:image] || button[:id]}.png"
  end

  # Build button with more states
  def build_twostate_button(bgi, index)
    return nil if hide_button?(bgi[:id])

    props = toolbar_button(
      bgi,
      :id     => bgi[:id],
      :type   => :buttonTwoState,
      :img    => img = img_value(bgi),
      :imgdis => img,
    )
    return nil if props.nil?

    props[:selected] = twostate_button_selected(bgi[:id])

    _add_separator(index)
    props
  end

  # According to button type in toolbar definition calls appropriate method
  def build_button(bgi, index)
    props = case bgi[:type]
            when :buttonSelect   then build_select_button(bgi, index)
            when :button         then build_normal_button(bgi, index)
            when :buttonTwoState then build_twostate_button(bgi, index)
            end

    unless props.nil?
      @toolbar << update_common_props(bgi, props)
    end
  end

  # @button_group is set in a controller
  #
  def group_skipped?(name)
    @button_group && (!name.starts_with?(@button_group + "_") &&
      !name.starts_with?("custom") && !name.starts_with?("dialog") &&
      !name.starts_with?("miq_dialog") && !name.starts_with?("custom_button") &&
      !name.starts_with?("instance_") && !name.starts_with?("image_")) &&
       !%w(record_summary summary_main summary_download tree_main
           x_edit_view_tb history_main ems_container_dashboard ems_infra_dashboard).include?(name)
  end

  def create_custom_button_hash(input, record, options = {})
    options[:enabled] = true unless options.key?(:enabled)
    button_id = input[:id]
    button_name = input[:name].to_s
    button = {
      :id        => "custom__custom_#{button_id}",
      :type      => :button,
      :icon      => "product product-custom-#{input[:image]} fa-lg",
      :title     => input[:description].to_s,
      :enabled   => options[:enabled],
      :klass     => ApplicationHelper::Button::ButtonWithoutRbacCheck,
      :url       => "button",
      :url_parms => "?id=#{record.id}&button_id=#{button_id}&cls=#{record.class}&pressed=custom_button&desc=#{button_name}"
    }
    button[:text] = button_name if input[:text_display]
    button
  end

  def create_raw_custom_button_hash(cb, record)
    {
      :id            => cb.id,
      :class         => cb.applies_to_class,
      :description   => cb.description,
      :name          => cb.name,
      :image         => cb.options[:button_image],
      :text_display  => cb.options.key?(:display) ? cb.options[:display] : true,
      :target_object => record.id.to_i
    }
  end

  def custom_buttons_hash(record)
    get_custom_buttons(record).collect do |group|
      props = {
        :id      => "custom_#{group[:id]}",
        :type    => :buttonSelect,
        :icon    => "product product-custom-#{group[:image]} fa-lg",
        :title   => group[:description],
        :enabled => true,
        :items   => group[:buttons].collect { |b| create_custom_button_hash(b, record) }
      }
      props[:text] = group[:text] if group[:text_display]

      {:name => "custom_buttons_#{group[:text]}", :items => [props]}
    end
  end

  def custom_toolbar_class(record)
    # each custom toolbar is an anonymous subclass of this class
    toolbar = Class.new(ApplicationHelper::Toolbar::Basic)
    custom_buttons_hash(record).each do |button_group|
      toolbar.button_group(button_group[:name], button_group[:items])
    end

    service_buttons = record_to_service_buttons(record)
    unless service_buttons.empty?
      buttons = service_buttons.collect { |b| create_custom_button_hash(b, record, :enabled => nil) }
      toolbar.button_group("custom_buttons_", buttons)
    end

    toolbar
  end

  def button_class_name(record)
    case record
    when Service then      "ServiceTemplate"            # Service Buttons are defined in the ServiceTemplate class
    when VmOrTemplate then record.class.base_model.name
    else               record.class.base_class.name
    end
  end

  def service_template_id(record)
    case record
    when Service then         record.service_template_id
    when ServiceTemplate then record.id
    end
  end

  def record_to_service_buttons(record)
    return [] unless record.kind_of?(Service)
    return [] if record.service_template.nil?
    record.service_template.custom_buttons.collect { |cb| create_raw_custom_button_hash(cb, record) }
  end

  def get_custom_buttons(record)
    cbses = CustomButtonSet.find_all_by_class_name(button_class_name(record), service_template_id(record))
    cbses.sort_by { |cbs| cbs[:set_data][:group_index] }.collect do |cbs|
      group = {
        :id           => cbs.id,
        :text         => cbs.name.split("|").first,
        :description  => cbs.description,
        :image        => cbs.set_data[:button_image],
        :text_display => cbs.set_data.key?(:display) ? cbs.set_data[:display] : true
      }

      available = CustomButton.available_for_user(current_user, cbs.name) # get all uri records for this user for specified uri set
      available = available.select { |b| cbs.members.include?(b) }            # making sure available_for_user uri is one of the members
      group[:buttons] = available.collect { |cb| create_raw_custom_button_hash(cb, record) }.uniq
      if cbs[:set_data][:button_order] # Show custom buttons in the order they were saved
        ordered_buttons = []
        cbs[:set_data][:button_order].each do |bidx|
          group[:buttons].each do |b|
            if bidx == b[:id] && !ordered_buttons.include?(b)
              ordered_buttons.push(b)
              break
            end
          end
        end
        group[:buttons] = ordered_buttons
      end
      group
    end
  end

  def get_image(img, b_name)
    # to change summary screen button to green image
    return "summary-green" if b_name == "show_summary" && %w(miq_schedule miq_task scan_profile).include?(@layout)
    img
  end

  def hide_button_ops(id)
    case x_active_tree
    when :settings_tree
      return ["schedule_run_now"].include?(id)
    when :diagnostics_tree
      case @sb[:active_tab]
      when "diagnostics_audit_log"
        return !["fetch_audit_log", "refresh_audit_log"].include?(id)
      when "diagnostics_collect_logs"
        return !%w(collect_current_logs collect_logs log_depot_edit
                  zone_collect_current_logs zone_collect_logs
                  zone_log_depot_edit).include?(id)
      when "diagnostics_evm_log"
        return !["fetch_log", "refresh_log"].include?(id)
      when "diagnostics_production_log"
        return !["fetch_production_log", "refresh_production_log"].include?(id)
      when "diagnostics_roles_servers", "diagnostics_servers_roles"
        case id
        when "reload_server_tree"
          return false
        when "zone_collect_current_logs", "zone_collect_logs", "zone_log_depot_edit"
          return true
        end
        return false
      when "diagnostics_summary"
        return !["refresh_server_summary", "restart_server"].include?(id)
      when "diagnostics_workers"
        return !%w(restart_workers refresh_workers).include?(id)
      else
        return true
      end
    when :rbac_tree
      return true unless role_allows?(:feature => rbac_common_feature_for_buttons(id))
      return true if %w(rbac_project_add rbac_tenant_add).include?(id) && @record.project?
      return false
    when :vmdb_tree
      return !["db_connections", "db_details", "db_indexes", "db_settings"].include?(@sb[:active_tab])
    else
      return true
    end
  end

  # Determine if a button should be hidden
  def hide_button?(id)
    # need to hide add buttons when on sub-list view screen of a CI.
    return true if id.ends_with?("_new", "_discover") &&
                   @lastaction == "show" && !%w(main vms instances all_vms).include?(@display)

    # user can see the buttons if they can get to Policy RSOP/Automate Simulate screen
    return false if ["miq_ae_tools"].include?(@layout)

    # buttons on compare/drift screen are allowed if user has access to compare/drift
    return false if id.starts_with?("compare_", "drift_", "comparemode_", "driftmode_")

    # Allow custom buttons on CI show screen, user can see custom button if they can get to show screen
    return false if id.starts_with?("custom_")

    return false if id == "miq_request_reload" && # Show the request reload button
                    (@lastaction == "show_list" || @showtype == "miq_provisions")

    if @layout == "ops"
      res = hide_button_ops(id)
      return res
    end

    return false if id.starts_with?("miq_capacity_") && @sb[:active_tab] == "report"

    # don't check for feature RBAC if id is miq_request_approve/deny
    unless %w(miq_policy catalogs).include?(@layout)
      return true if !role_allows?(:feature => id) && !["miq_request_approve", "miq_request_deny"].include?(id) &&
                     id !~ /^history_\d*/ &&
                     !id.starts_with?("dialog_") && !id.starts_with?("miq_task_") &&
                     !(id == "show_summary" && !@explorer) && id != "summary_reload"
    end

    # Check buttons with other restriction logic
    case id
    when "miq_task_canceljob"
      return true unless ["all_tasks", "all_ui_tasks"].include?(@layout)
    end

    false  # No reason to hide, allow the button to show
  end

  # Determine if a button should be disabled. Returns either boolean or
  # string message with explanation of reason for disabling
  def disable_button(id)
    return true if id.starts_with?("view_") && id.ends_with?("textual")  # Summary view buttons
    return true if @gtl_type && id.starts_with?("view_") && id.ends_with?(@gtl_type)  # GTL view buttons
    return true if id == "view_dashboard" && (@showtype == "dashboard")
    return true if id == "view_summary" && (@showtype != "dashboard")

    # need to add this here, since this button is on list view screen
    if disable_new_iso_datastore?(id)
      return N_("No %{providers} are available to create an ISO Datastore on") %
        {:providers => ui_lookup(:tables => "ext_management_system")}
    end

    case get_record_cls(@record)
    when "Host"
      case id
      when "host_analyze_check_compliance", "host_check_compliance"
        return N_("No Compliance Policies assigned to this Host") unless @record.has_compliance_policies?
      when "host_perf"
        return N_("No Capacity & Utilization data has been collected for this Host") unless @record.has_perf_data?
      when "host_miq_request_new"
        return N_("This Host can not be provisioned because the MAC address is not known") unless @record.mac_address
        count = PxeServer.all.size
        return N_("No PXE Servers are available for Host provisioning") if count <= 0
      when "host_timeline"
        unless @record.has_events? || @record.has_events?(:policy_events)
          return N_("No Timeline data has been collected for this Host")
        end
      end
    when "MiqAction"
      case id
      when "action_edit"
        return N_("Default actions can not be changed.") if @record.action_type == "default"
      when "action_delete"
        return N_("Default actions can not be deleted.") if @record.action_type == "default"
        return N_("Actions assigned to Policies can not be deleted") unless @record.miq_policies.empty?
      end
    when "MiqGroup"
      case id
      when "rbac_group_delete"
        return N_("This Group is Read Only and can not be deleted") if @record.read_only
      when "rbac_group_edit"
        return N_("This Group is Read Only and can not be edited") if @record.read_only
      end
    when "MiqServer"
      case id
      when "collect_logs", "collect_current_logs"
        unless @record.started?
          return N_("Cannot collect current logs unless the %{server} is started") %
            {:server => ui_lookup(:table => "miq_server")}
        end
        if @record.log_collection_active_recently?
          return N_("Log collection is already in progress for this %{server}") %
            {:server => ui_lookup(:table => "miq_server")}
        end
        unless @record.log_file_depot
          return N_("Log collection requires the Log Depot settings to be configured")
        end
      when "restart_workers"
        return N_("Select a worker to restart") if @sb[:selected_worker_id].nil?
      end
    when "MiqWidgetSet"
      case id
      when "db_delete"
        return N_("Default Dashboard cannot be deleted") if @db.read_only
      end
    when "OrchestrationStack"
      case id
      when "orchestration_stack_retire_now"
        return N_("Orchestration Stack is already retired") if @record.retired == true
      end
    when "Service"
      case id
      when "service_retire_now"
        return N_("Service is already retired") if @record.retired == true
      end
    when "ScanItemSet"
      case id
      when "ap_delete"
        return N_("Sample Analysis Profile cannot be deleted") if @record.read_only
      when "ap_edit"
        return N_("Sample Analysis Profile cannot be edited") if @record.read_only
      end
    when "ServiceTemplate"
      case id
      when "svc_catalog_provision"
        d = nil
        @record.resource_actions.each do |ra|
          d = Dialog.find_by_id(ra.dialog_id.to_i) if ra.action.downcase == "provision"
        end
        return N_("No Ordering Dialog is available") if d.nil?
      end
    when "Storage"
      case id
      when "storage_perf"
        unless @record.has_perf_data?
          return N_("No Capacity & Utilization data has been collected for this %{storage}") %
            {:storage => ui_lookup(:table => "storage")}
        end
      when "storage_delete"
        unless @record.vms_and_templates.empty? && @record.hosts.empty?
          return N_("Only %{storage} without VMs and Hosts can be removed") %
            {:storage => ui_lookup(:table => "storage")}
        end
      when "storage_scan"
        return @record.unsupported_reason(:smartstate_analysis) unless @record.supports_smartstate_analysis?
      end
    when "Tenant"
      return N_("Default Tenant can not be deleted") if @record.parent.nil? && id == "rbac_tenant_delete"
    when "User"
      case id
      when "rbac_user_copy"
        return N_("User [Administrator] can not be copied") if @record.super_admin_user?
      when "rbac_user_delete"
        return N_("User [Administrator] can not be deleted") if @record.super_admin_user?
      end
    when "UserRole"
      case id
      when "rbac_role_delete"
        return N_("This Role is Read Only and can not be deleted") if @record.read_only
        return N_("This Role is in use by one or more Groups and can not be deleted") if @record.group_count > 0
      when "rbac_role_edit"
        return N_("This Role is Read Only and can not be edited") if @record.read_only
      end
    when "Vm"
      case id
      when "instance_perf", "vm_perf", "container_perf"
        return N_("No Capacity & Utilization data has been collected for this VM") unless @record.has_perf_data?
      end
    when "MiqTemplate"
      case id
      when "image_check_compliance", "miq_template_check_compliance"
        unless @record.has_compliance_policies?
          return N_("No Compliance Policies assigned to this %{vm}") %
            {:vm => ui_lookup(:model => model_for_vm(@record).to_s)}
        end
      when "miq_template_perf"
        return N_("No Capacity & Utilization data has been collected for this Template") unless @record.has_perf_data?
      when "miq_template_scan", "image_scan"
        return @record.unsupported_reason(:smartstate_analysis) unless @record.supports_smartstate_analysis?
        return @record.active_proxy_error_message unless @record.has_active_proxy?
      when "miq_template_timeline"
        unless @record.has_events? || @record.has_events?(:policy_events)
          return N_("No Timeline data has been collected for this Template")
        end
      end
    when "Zone"
      case id
      when "zone_collect_logs", "zone_collect_current_logs"
        unless @record.any_started_miq_servers?
          return N_("Cannot collect current logs unless there are started %{servers} in the Zone") %
            {:servers => ui_lookup(:tables => "miq_servers")}
        end
        unless @record.log_file_depot
          return N_("This Zone do not have Log Depot settings configured, collection not allowed")
        end
        if @record.log_collection_active_recently?
          return N_("Log collection is already in progress for one or more %{servers} in this Zone") %
            {:servers => ui_lookup(:tables => "miq_servers")}
        end
      when "zone_delete"
        if @selected_zone.name.downcase == "default"
          return N_("'Default' zone cannot be deleted")
        elsif @selected_zone.ext_management_systems.count > 0 ||
              @selected_zone.storage_managers.count > 0 ||
              @selected_zone.miq_schedules.count > 0 ||
              @selected_zone.miq_servers.count > 0
          return N_("Cannot delete a Zone that has Relationships")
        end
      end
    when nil, "NilClass"
      case id
      when "ae_copy_simulate"
        if @resolve[:button_class].blank?
          return N_("Object attribute must be specified to copy object details for use in a Button")
        end
      when "customization_template_new"
        if @pxe_image_types_count <= 0
          return N_("No System Image Types available, Customization Template cannot be added")
        end
      # following 2 are checks for buttons in Reports/Dashboard accordion
      when "db_new"
        if @widgetsets.length >= MAX_DASHBOARD_COUNT
          return N_("Only %{dashboard_count} Dashboards are allowed for a group") %
            {:dashboard_count => MAX_DASHBOARD_COUNT}
        end
      when "db_seq_edit"
        return N_("There should be atleast 2 Dashboards to Edit Sequence") if @widgetsets.length <= 1
      when "render_report_csv", "render_report_pdf",
          "render_report_txt", "report_only"
        if (@html || @zgraph) && (!@report.extras[:grouping] || (@report.extras[:grouping] && @report.extras[:grouping][:_total_][:count] > 0))
          return false
        else
          return N_("No records found for this report")
        end
      end
    when 'MiqReportResult'
      if id == 'report_only'
        return @report.present? && @report_result_id.present? &&
          MiqReportResult.find(@report_result_id).try(:miq_report_result_details).try(:length).to_i > 0 ? false : N_("No records found for this report")
      end
    when "ExtManagementSystem"
      case id
      when "ems_storage_monitoring_choice"
        unless @record.has_events? || @record.has_events?(:policy_events)
          return N_("No Timeline data has been collected for Policy or Management Events")
        end
      end
    end
    false
  end

  def get_record_cls(record)
    if record.kind_of?(AvailabilityZone)
      record.class.base_class.name
    elsif MiqRequest.descendants.include?(record.class)
      record.class.base_class.name
    else
      klass = case record
              when ContainerNode, ContainerGroup, Container then record.class.base_class
              when Host, ExtManagementSystem                then record.class.base_class
              when VmOrTemplate                             then record.class.base_model
              else                                               record.class
              end
      klass.name
    end
  end

  # Determine if a button should be selected for buttonTwoState
  def twostate_button_selected(id)
    return true if id.starts_with?("view_") && id.ends_with?("textual")  # Summary view buttons
    return true if @gtl_type && id.starts_with?("view_") && id.ends_with?(@gtl_type)  # GTL view buttons
    return true if @ght_type && id.starts_with?("view_") && id.ends_with?(@ght_type)  # GHT view buttons on report show
    return true if id.starts_with?("tree_") && id.ends_with?(@settings[:views][:treesize].to_i == 32 ? "large" : "small")
    return true if id.starts_with?("compare_") && id.ends_with?(@settings[:views][:compare])
    return true if id.starts_with?("drift_") && id.ends_with?(@settings[:views][:drift])
    return true if id == "compare_all"
    return true if id == "drift_all"
    return true if id.starts_with?("comparemode_") && id.ends_with?(@settings[:views][:compare_mode])
    return true if id.starts_with?("driftmode_") && id.ends_with?(@settings[:views][:drift_mode])
    return true if id == "view_dashboard" && @showtype == "dashboard"
    return true if id == "view_topology" && @showtype == "topology"
    return true if id == "view_summary" && @showtype == "main"
    false
  end

  def url_for_button(name, url_tpl, controller_restful)
    url = safer_eval(url_tpl)

    if %w(view_grid view_tile view_list).include?(name) && controller_restful && url =~ %r{^\/(\d+|\d+r\d+)\?$}
      # handle restful routes - we want just / if the url is just an id
      url = '/'
    end

    url
  end

  def update_common_props(item, props)
    props[:url] = url_for_button(props[:id], item[:url], controller_restful?) if item[:url]
    props[:explorer] = true if @explorer && !item[:url] # Add explorer = true if ajax button
    props
  end

  def update_url_parms(url_parm)
    return url_parm unless url_parm =~ /=/

    keep_parms = %w(bc escape menu_click sb_controller)
    query_string = Rack::Utils.parse_query URI("?#{request.query_string}").query
    query_string.delete_if { |k, _v| !keep_parms.include? k }

    url_parm_hash = preprocess_url_param(url_parm)
    query_string.merge!(url_parm_hash)
    URI.decode("?#{query_string.to_query}")
  end

  def preprocess_url_param(url_parm)
    parse_questionmark = /^\?/.match(url_parm)
    parse_ampersand = /^&/.match(url_parm)
    url_parm = parse_questionmark.post_match if parse_questionmark.present?
    url_parm = parse_ampersand.post_match if parse_ampersand.present?
    encoded_url = URI.encode(url_parm)
    Rack::Utils.parse_query URI("?#{encoded_url}").query
  end

  def disable_new_iso_datastore?(item_id)
    @layout == "pxe" &&
      item_id == "iso_datastore_new" &&
      !ManageIQ::Providers::Redhat::InfraManager.any_without_iso_datastores?
  end

  def build_toolbar_setup
    @toolbar = []
    @groups_added = []
    @sep_needed = false
    @sep_added = false
  end

  def build_toolbar_from_class(toolbar_class)
    toolbar_class.definition.each_with_index do |(name, group), group_index|
      next if group_skipped?(name)

      @sep_added = false
      @groups_added.push(group_index)
      case group
      when ApplicationHelper::Toolbar::Group
        group.buttons.each do |bgi|
          build_button(bgi, group_index)
        end
      when ApplicationHelper::Toolbar::Custom
        rendered_html = group.render(@view_context).tr('\'', '"')
        group[:args][:html] = ERB::Util.html_escape(rendered_html).html_safe
        @toolbar << group
      end
    end

    @toolbar = nil if @toolbar.empty?
    @toolbar
  end
end
