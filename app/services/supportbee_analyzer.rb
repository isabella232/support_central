class SupportbeeAnalyzer < Analyzer
  DataSource = Struct.new(:company_id, :auth_token)

protected
  def support_source_class
    SupportbeeSupportSource
  end

  def get_data_sources
    result = {}
    @support_sources.each do |source|
      key = [source.supportbee_company_id, source.supportbee_auth_token]
      result[key] ||= DataSource.new(source.supportbee_company_id,
        source.supportbee_auth_token)
    end
    result.values
  end

  def fetch_unanswered_external_tickets
    result = []
    @data_sources.each do |source|
      client = Supportbee::Client.new(company: source.company_id,
        auth_token: source.auth_token)
      result.concat(query_unanswered_tickets(client, assigned_user: 'none'))
      result.concat(query_unanswered_tickets(client, assigned_user: 'me'))
      result.concat(query_unanswered_tickets(client, assigned_group: 'mine'))
    end
    result
  end

  def id_for_external_ticket(external_ticket)
    external_ticket['id'].to_s
  end

  def title_for_external_ticket(external_ticket)
    external_ticket['subject']
  end

  def support_sources_eligible_for_external_ticket(external_ticket)
    assignee = external_ticket['current_assignee']
    if assignee
      if assignee['user']
        user_id = assignee['user']['id']
        @support_sources.find_all do |support_source|
          support_source.supportbee_user_id == user_id
        end
      else
        group_id = assignee['group']['id'].to_s
        @support_sources.find_all do |support_source|
          support_source.supportbee_group_ids.include?(group_id)
        end
      end
    else
      @support_sources
    end
  end

  def update_internal_ticket(internal_ticket, external_ticket)
    labels = external_ticket['labels'].map { |l| l['name'] }
    if labels.include?('overdue')
      new_status = 'overdue'
    elsif labels.include?('respond now')
      new_status = 'respond_now'
    else
      new_status = 'normal'
    end
    if internal_ticket.status != new_status
      internal_ticket.update_attribute(:status, new_status)
    end
  end

private
  def query_unanswered_tickets(client, options)
    client.tickets(options).find_all do |external_ticket|
      external_ticket['unanswered']
    end
  end
end
