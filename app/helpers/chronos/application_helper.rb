module Chronos
  module ApplicationHelper
    def authorize_globally_for(controller, action)
      User.current.allowed_to_globally? controller: controller, action: action
    end

    def issue_label_for(issue)
      "##{issue.id} #{issue.subject}" if issue
    end

    def projects_for_project_select(selected = nil)
      projects = User.current.projects.has_module('redmine_chronos')
      project_tree_options_for_select projects, selected: selected
    end

    def activity_collection(project = nil)
      project.present? ? project.activities : TimeEntryActivity.shared.active
    end

    def grouped_entry_list(entries, query, count_by_group)
      previous_group, first = false, true
      entries.each do |entry|
        group_name = group_count = nil
        if query.grouped?
          column = query.group_by_column
          group = column.value entry
          group = group.to_date if column.groupable.include? 'DATE'
          totals_by_group = query.totalable_columns.inject({}) do |totals, column|
            totals[column] = query.total_by_group_for(column)
            totals
          end
          if group != previous_group || first
            if group.blank? && group != false
              group_name = "(#{l(:label_blank_value)})"
            else
              group_name = column_content(query.group_by_column, entry)
              group_name = format_object(group) if column.groupable.include? 'DATE'
            end
            group_name ||= ''
            group_count = count_by_group[group] ||
                count_by_group[group.to_s] ||
                (group.respond_to?(:id) && count_by_group[group.id])
            group_totals = totals_by_group.map { |column, t| total_tag(column, t[group] || t[group.to_s] || (group.respond_to?(:id) && t[group.id])) }.join(' ').html_safe
          end
        end
        yield entry, group_name, group_count, group_totals
        previous_group, first = group, false
      end
    end

    def sidebar_queries
      @sidebar_queries ||= query_class.where(project: [nil, @project]).order(name: :asc)
    end

    def localized_hours_in_units(hours)
      h, min = Chronos::DateTimeCalculations.hours_in_units hours || 0
      "#{h}#{t('chronos.ui.chart.hour_sign')} #{min}#{t('chronos.ui.chart.minute_sign')}"
    end

    def chart_data
      data = Array.new
      ticks = Array.new
      tooltips = Array.new

      if @chart_query.valid?
        hours_per_date = @chart_query.hours_by_group
        dates = hours_per_date.keys.sort
        unless dates.empty?
          date_range = (dates.first..dates.last)
          gap = (date_range.count / 8).ceil
          date_range.each do |date_string|
            hours = hours_per_date[date_string]
            data.push hours
            tooltips.push "#{date_string}, #{localized_hours_in_units hours}"
            # to get readable labels, we have to blank out some of them if there are to many
            # only set 8 labels and set the other blank
            ticks.push (data.length - 1) % gap == 0 ? date_string : ''
          end
        end
      end
      [data, ticks, tooltips]
    end

    def report_column_map
      @report_column_map ||= {
          date: [:start, :stop],
          description: [:activity, :issue, :comments, :project, :fixed_version],
          duration: [:hours, :start, :stop]
      }
    end

    def combined_column_names(column)
      report_column_map.select { |key, array| array.include? column.name }.keys
    end

    def combined_columns
      columns = []
      @query.columns.each do |column|
        combined_names = combined_column_names(column)
        columns.push column if combined_names.empty?
        combined_names.reject { |name| columns.find { |col| col.name == name } }.each do |name|
          columns.push QueryColumn.new name
        end
      end
      columns.sort_by! do |column|
        report_column_map.keys.index(column.name) || Float::INFINITY
      end
    end

    def date_content(entry)
      format_date entry.start
    end

    def description_content(entry)
      output = ActiveSupport::SafeBuffer.new
      if entry.issue.present?
        output.concat entry.activity
        output.concat entry.issue
      else
        output.concat [entry.activity, entry.comments].compact.join(': ')
      end
      output.concat (content_tag :div, class: 'project' do
        [entry.project, entry.fixed_version].compact.join(' / ')
      end)
      output
    end

    def duration_content(entry)
      output = ActiveSupport::SafeBuffer.new
      output.concat localized_hours_in_units entry.hours
      output.concat (content_tag :div, class: 'start-stop' do
        [format_time(entry.start, false), format_time(entry.stop, false)].compact.join('-')
      end)
      output
    end
  end
end
