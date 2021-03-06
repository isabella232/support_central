require 'rails_helper'
require 'time'

describe SupportbeeAnalyzer do
  let(:time1_str) { '2012-01-18T15:17:33Z' }
  let(:time2_str) { '2012-01-18T16:17:33Z' }
  let(:time3_str) { '2012-01-18T17:17:33Z' }
  let(:time4_str) { '2012-01-18T18:17:33Z' }
  let(:time1) { Time.parse(time1_str) }
  let(:time2) { Time.parse(time2_str) }
  let(:time3) { Time.parse(time3_str) }
  let(:time4) { Time.parse(time4_str) }

  let(:traveling_ruby_team) { 4567 }
  let(:passenger_team) { 4568 }
  let(:docker_team) { 4569 }
  let(:union_station_team) { 4570 }

  def create_dependencies
    @user = create(:user)
    @supportbee = create(:supportbee, user: @user)
  end

  def stub_supportbee_request(assignment, body, auth_token = 1234)
    url = "https://phusion.supportbee.com/tickets.json?archived=false&" \
      "#{assignment}&auth_token=#{auth_token}&page=1&spam=false&trash=false"
    if !body.is_a?(String)
      body = body.to_json
    end
    stub_request(:get, url).
      to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
        body: body)
  end

  def ticket_as_json(ticket, answered)
    if !ticket.is_a?(Hash)
      ticket = {
        id: ticket.external_id.to_i,
        subject: ticket.title,
        labels: [],
        last_activity_at: time1_str
      }
    end
    if !ticket.key?(:unanswered)
      ticket[:unanswered] = !answered
    end
    ticket[:archived] = false
    ticket[:spam] = false
    ticket[:trash] = false
    ticket
  end

  def make_tickets_array(*tickets)
    tickets = tickets.flatten
    {
      'total' => tickets.size,
      'current_page' => 1,
      'per_page' => 50,
      'total_pages' => 1,
      'tickets' => tickets
    }
  end

  context 'when there is one user' do
    it 'deletes internal tickets for which the corresponding Supportbee ticket has already been answered' do
      create_dependencies
      @frequent_memory_warnings = create(:frequent_memory_warnings,
        support_source: @supportbee)
      @bundle_install_error = create(:bundle_install_error,
        support_source: @supportbee)
      @apt_repo_down = create(:apt_repo_down,
        support_source: @supportbee)
      @yum_repo_signature_error = create(:yum_repo_signature_error,
        support_source: @supportbee)
      @view_rolling_restart_status = create(:view_rolling_restart_status,
        support_source: @supportbee)

      stub1 = stub_supportbee_request('assigned_user=none&assigned_team=none',
        make_tickets_array(
          ticket_as_json(@frequent_memory_warnings, false),
          ticket_as_json(@bundle_install_error, true)
        )
      )
      stub2 = stub_supportbee_request('assigned_user=me',
        make_tickets_array(
          ticket_as_json(@apt_repo_down, true)
        )
      )
      stub3 = stub_supportbee_request('assigned_team=mine',
        make_tickets_array(
          ticket_as_json(@yum_repo_signature_error, true),
          ticket_as_json(@view_rolling_restart_status, false)
        )
      )

      SupportbeeAnalyzer.new.analyze

      assert_requested(stub1)
      assert_requested(stub2)
      assert_requested(stub3)
      expect(Ticket.count).to eq(2)
      expect(Ticket.exists?(@frequent_memory_warnings.id)).to be_truthy
      expect(Ticket.exists?(@bundle_install_error.id)).to be_falsey
      expect(Ticket.exists?(@apt_repo_down.id)).to be_falsey
      expect(Ticket.exists?(@yum_repo_signature_error.id)).to be_falsey
      expect(Ticket.exists?(@view_rolling_restart_status.id)).to be_truthy
    end

    it 'deletes internal tickets for which there is no corresponding Supportbee ticket' do
      create_dependencies
      @frequent_memory_warnings = create(:frequent_memory_warnings,
        support_source: @supportbee)
      @bundle_install_error = create(:bundle_install_error,
        support_source: @supportbee)
      @apt_repo_down = create(:apt_repo_down,
        support_source: @supportbee)

      stub1 = stub_supportbee_request('assigned_user=none&assigned_team=none',
        make_tickets_array(
          ticket_as_json(@bundle_install_error, true)
        )
      )
      stub2 = stub_supportbee_request('assigned_user=me',
        make_tickets_array(
          ticket_as_json(@apt_repo_down, false)
        )
      )
      stub3 = stub_supportbee_request('assigned_team=mine',
        make_tickets_array([]))

      SupportbeeAnalyzer.new.analyze

      assert_requested(stub1)
      assert_requested(stub2)
      assert_requested(stub3)
      expect(Ticket.count).to eq(1)
      expect(Ticket.exists?(@frequent_memory_warnings.id)).to be_falsey
      expect(Ticket.exists?(@bundle_install_error.id)).to be_falsey
      expect(Ticket.exists?(@apt_repo_down.id)).to be_truthy
    end

    it 'deletes internal tickets for which the corresponding Supportbee ticket has been reassigned ' \
      'to a team that the current user is not part of' \
    do
      create_dependencies
      @frequent_memory_warnings = create(:frequent_memory_warnings,
        support_source: @supportbee)
      @bundle_install_error = create(:bundle_install_error,
        support_source: @supportbee)
      @apt_repo_down = create(:apt_repo_down,
        support_source: @supportbee)
      @yum_repo_signature_error = create(:yum_repo_signature_error,
        support_source: @supportbee)
      @view_rolling_restart_status = create(:view_rolling_restart_status,
        support_source: @supportbee)

      stub1 = stub_supportbee_request('assigned_user=none&assigned_team=none',
        make_tickets_array(
          ticket_as_json(@frequent_memory_warnings, false),
          ticket_as_json(@bundle_install_error, true)
        )
      ).times(2)
      stub2 = stub_supportbee_request('assigned_user=me',
        make_tickets_array(
          ticket_as_json(@apt_repo_down, true)
        )
      ).times(2)
      stub3 = stub_supportbee_request('assigned_team=mine',
        make_tickets_array(
          ticket_as_json(@yum_repo_signature_error, true),
          ticket_as_json(@view_rolling_restart_status, false)
        )
      ).then.to_return(
        status: 200,
        headers: { 'Content-Type' => 'application/json' },
        body: make_tickets_array(
          ticket_as_json(@yum_repo_signature_error, true)
        ).to_json
      )

      SupportbeeAnalyzer.new.analyze
      SupportbeeAnalyzer.new.analyze

      assert_requested(stub1, times: 2)
      assert_requested(stub2, times: 2)
      assert_requested(stub3, times: 2)
      expect(Ticket.count).to eq(1)
      expect(Ticket.exists?(@frequent_memory_warnings.id)).to be_truthy
      expect(Ticket.exists?(@bundle_install_error.id)).to be_falsey
      expect(Ticket.exists?(@apt_repo_down.id)).to be_falsey
      expect(Ticket.exists?(@yum_repo_signature_error.id)).to be_falsey
      expect(Ticket.exists?(@view_rolling_restart_status.id)).to be_falsey
    end

    it 'deletes all internal tickets if there are no unanswered Supportbee tickets' do
      create_dependencies
      @frequent_memory_warnings = create(:frequent_memory_warnings,
        support_source: @supportbee)
      @bundle_install_error = create(:bundle_install_error,
        support_source: @supportbee)
      @apt_repo_down = create(:apt_repo_down,
        support_source: @supportbee)
      @yum_repo_signature_error = create(:yum_repo_signature_error,
        support_source: @supportbee)

      stub1 = stub_supportbee_request('assigned_user=none&assigned_team=none',
        make_tickets_array([]))
      stub2 = stub_supportbee_request('assigned_user=me',
        make_tickets_array([]))
      stub3 = stub_supportbee_request('assigned_team=mine',
        make_tickets_array([]))

      SupportbeeAnalyzer.new.analyze

      assert_requested(stub1)
      assert_requested(stub2)
      assert_requested(stub3)
      expect(Ticket.count).to eq(0)
    end

    it 'creates internal tickets for not-seen-before unanswered Supportbee tickets' do
      create_dependencies
      @frequent_memory_warnings = create(:frequent_memory_warnings,
        support_source: @supportbee)

      stubbed_body = make_tickets_array(
        ticket_as_json(@frequent_memory_warnings, false),
        ticket_as_json({
          id: 1,
          number: 1,
          subject: 'New ticket 1',
          labels: [ { name: 'foo' } ],
          last_activity_at: time2_str
        }, false),
        ticket_as_json({
          id: 2,
          number: 2,
          subject: 'New ticket 2',
          labels: [ { name: 'bar' } ],
          last_activity_at: time3_str
        }, false),
        ticket_as_json({
          id: 3,
          number: 3,
          subject: 'New ticket 3',
          labels: [ { name: 'baz' } ],
          last_activity_at: time4_str
        }, true)
      )
      stub1 = stub_supportbee_request('assigned_user=none&assigned_team=none',
        stubbed_body)
      stub2 = stub_supportbee_request('assigned_user=me',
        make_tickets_array([]))
      stub3 = stub_supportbee_request('assigned_team=mine',
        make_tickets_array([]))

      SupportbeeAnalyzer.new.analyze

      assert_requested(stub1)
      assert_requested(stub2)
      assert_requested(stub3)

      expect(Ticket.count).to eq(3)
      expect(Ticket.exists?(@frequent_memory_warnings.id)).to be_truthy

      ticket1 = Ticket.where(external_id: '1').first
      expect(ticket1.title).to eq('New ticket 1')
      expect(ticket1.labels).to eq(['foo'])
      expect(ticket1.display_id).to eq('1')
      expect(ticket1.external_id).to eq('1')
      expect(ticket1.external_last_update_time).to eq(time2)

      ticket2 = Ticket.where(external_id: '2').first
      expect(ticket2.title).to eq('New ticket 2')
      expect(ticket2.labels).to eq(['bar'])
      expect(ticket2.display_id).to eq('2')
      expect(ticket2.external_id).to eq('2')
      expect(ticket2.external_last_update_time).to eq(time3)
    end

    it 'does not touch existing tickets for unanswered Supportbee tickets' do
      create_dependencies
      @frequent_memory_warnings = create(:frequent_memory_warnings,
        support_source: @supportbee)
      @bundle_install_error = create(:bundle_install_error,
        support_source: @supportbee)
      @apt_repo_down = create(:apt_repo_down,
        support_source: @supportbee)
      @yum_repo_signature_error = create(:yum_repo_signature_error,
        support_source: @supportbee)

      stubbed_body = make_tickets_array(
        ticket_as_json(@frequent_memory_warnings, false),
        ticket_as_json(@bundle_install_error, false),
        ticket_as_json(@apt_repo_down, false),
        ticket_as_json(@yum_repo_signature_error, false)
      )
      stub1 = stub_supportbee_request('assigned_user=none&assigned_team=none',
        stubbed_body)
      stub2 = stub_supportbee_request('assigned_user=me',
        make_tickets_array([]))
      stub3 = stub_supportbee_request('assigned_team=mine',
        make_tickets_array([]))

      SupportbeeAnalyzer.new.analyze

      assert_requested(stub1)
      assert_requested(stub2)
      assert_requested(stub3)
      expect(Ticket.count).to eq(4)
      expect(Ticket.exists?(@frequent_memory_warnings.id)).to be_truthy
      expect(Ticket.exists?(@bundle_install_error.id)).to be_truthy
      expect(Ticket.exists?(@apt_repo_down.id)).to be_truthy
      expect(Ticket.exists?(@yum_repo_signature_error.id)).to be_truthy
    end

    it 'does not touch tickets not belonging to SupportbeeSupportSource' do
      create_dependencies
      @github = create(:github_passenger, user: @user)
      @frequent_memory_warnings = create(:frequent_memory_warnings,
        support_source: @github)
      @bundle_install_error = create(:bundle_install_error,
        support_source: @supportbee)
      @apt_repo_down = create(:apt_repo_down,
        support_source: @github)
      @yum_repo_signature_error = create(:yum_repo_signature_error,
        support_source: @supportbee)

      stub1 = stub_supportbee_request('assigned_user=none&assigned_team=none',
        make_tickets_array([]))
      stub2 = stub_supportbee_request('assigned_user=me',
        make_tickets_array([]))
      stub3 = stub_supportbee_request('assigned_team=mine',
        make_tickets_array([]))

      SupportbeeAnalyzer.new.analyze

      assert_requested(stub1)
      assert_requested(stub2)
      assert_requested(stub3)
      expect(Ticket.count).to eq(2)
      expect(Ticket.exists?(@frequent_memory_warnings.id)).to be_truthy
      expect(Ticket.exists?(@bundle_install_error.id)).to be_falsey
      expect(Ticket.exists?(@apt_repo_down.id)).to be_truthy
      expect(Ticket.exists?(@yum_repo_signature_error.id)).to be_falsey
    end

    it "sets a ticket's status to 'respond_now' if the corresponding " \
       "Supportbee ticket has the 'respond now' label" \
    do
      create_dependencies
      @frequent_memory_warnings = create(:frequent_memory_warnings,
        support_source: @supportbee)

      json = ticket_as_json(@frequent_memory_warnings, false)
      json[:labels] = [ { name: 'respond now' } ]
      stub1 = stub_supportbee_request('assigned_user=none&assigned_team=none',
        make_tickets_array(json))
      stub2 = stub_supportbee_request('assigned_user=me',
        make_tickets_array([]))
      stub3 = stub_supportbee_request('assigned_team=mine',
        make_tickets_array([]))

      SupportbeeAnalyzer.new.analyze

      assert_requested(stub1)
      assert_requested(stub2)
      assert_requested(stub3)
      @frequent_memory_warnings.reload
      expect(@frequent_memory_warnings.status).to eq('respond_now')
    end

    it "sets a ticket's status to 'overdue' if the corresponding " \
       "Supportbee ticket has the 'overdue' label" \
    do
      create_dependencies
      @frequent_memory_warnings = create(:frequent_memory_warnings,
        support_source: @supportbee)

      json = ticket_as_json(@frequent_memory_warnings, false)
      json[:labels] = [ { name: 'overdue' } ]
      stub1 = stub_supportbee_request('assigned_user=none&assigned_team=none',
        make_tickets_array(json))
      stub2 = stub_supportbee_request('assigned_user=me',
        make_tickets_array([]))
      stub3 = stub_supportbee_request('assigned_team=mine',
        make_tickets_array([]))

      SupportbeeAnalyzer.new.analyze

      assert_requested(stub1)
      assert_requested(stub2)
      assert_requested(stub3)
      @frequent_memory_warnings.reload
      expect(@frequent_memory_warnings.status).to eq('overdue')
    end

    it "sets a ticket's status to 'overdue' if the corresponding " \
       "Supportbee ticket has both the 'respond now' and 'overdue' labels" \
    do
      create_dependencies
      @frequent_memory_warnings = create(:frequent_memory_warnings,
        support_source: @supportbee)

      json = ticket_as_json(@frequent_memory_warnings, false)
      json[:labels] = [ { name: 'respond now' }, { name: 'overdue' } ]
      stub1 = stub_supportbee_request('assigned_user=none&assigned_team=none',
        make_tickets_array(json))
      stub2 = stub_supportbee_request('assigned_user=me',
        make_tickets_array([]))
      stub3 = stub_supportbee_request('assigned_team=mine',
        make_tickets_array([]))

      SupportbeeAnalyzer.new.analyze

      assert_requested(stub1)
      assert_requested(stub2)
      assert_requested(stub3)
      @frequent_memory_warnings.reload
      expect(@frequent_memory_warnings.status).to eq('overdue')
    end

    it "sets a ticket's status to 'normal' if the corresponding " \
       "Supportbee ticket has neither the 'respond now' nor the 'overdue' label" \
    do
      create_dependencies
      @frequent_memory_warnings = create(:frequent_memory_warnings,
        status: 'overdue',
        support_source: @supportbee)

      json = ticket_as_json(@frequent_memory_warnings, false)
      stub1 = stub_supportbee_request('assigned_user=none&assigned_team=none',
        make_tickets_array(json))
      stub2 = stub_supportbee_request('assigned_user=me',
        make_tickets_array([]))
      stub3 = stub_supportbee_request('assigned_team=mine',
        make_tickets_array([]))

      SupportbeeAnalyzer.new.analyze

      assert_requested(stub1)
      assert_requested(stub2)
      assert_requested(stub3)
      @frequent_memory_warnings.reload
      expect(@frequent_memory_warnings.status).to eq('normal')
    end

    it "saves the Supportbee's ticket's labels except for 'respond now' and 'overdue'" do
      create_dependencies
      @frequent_memory_warnings = create(:frequent_memory_warnings,
        support_source: @supportbee)

      json = ticket_as_json(@frequent_memory_warnings, false)
      json[:labels] = [
        { name: 'silver' },
        { name: 'passenger' },
        { name: 'overdue' },
        { name: 'respond now' }
      ]
      stub1 = stub_supportbee_request('assigned_user=none&assigned_team=none',
        make_tickets_array(json))
      stub2 = stub_supportbee_request('assigned_user=me',
        make_tickets_array([]))
      stub3 = stub_supportbee_request('assigned_team=mine',
        make_tickets_array([]))

      SupportbeeAnalyzer.new.analyze

      assert_requested(stub1)
      assert_requested(stub2)
      assert_requested(stub3)
      @frequent_memory_warnings.reload
      expect(@frequent_memory_warnings.labels).to eq(['silver', 'passenger'])
    end
  end

  context 'given two support sources with both distinct and overlapping teams' do
    before :each do
      @user = create(:user)
      @supportbee_hongli = create(:supportbee,
        name: 'Supportbee Hongli',
        supportbee_auth_token: 'hongli',
        supportbee_user_id: 1234,
        supportbee_group_ids: [traveling_ruby_team, passenger_team, docker_team],
        user: @user)
      @supportbee_tinco = create(:supportbee,
        name: 'Supportbee Tinco',
        supportbee_auth_token: 'tinco',
        supportbee_user_id: 1235,
        supportbee_group_ids: [passenger_team, docker_team, union_station_team],
        user: @user)
    end

    context 'given not-seen-before unanswered Supportbee tickets' do
      it 'creates corresponding internal tickets for support sources ' \
         'matching the assigned user' \
      do
        # API requests for Hongli
        stub1 = stub_supportbee_request('assigned_user=none&assigned_team=none',
          make_tickets_array([]),
          @supportbee_hongli.supportbee_auth_token)
        stubbed_body = make_tickets_array(
          ticket_as_json({
            id: 600,
            subject: 'Frequent memory warnings',
            labels: [],
            last_activity_at: time1_str,
            current_team_assignee: { user: {
              id: @supportbee_hongli.supportbee_user_id
            } }
          }, false),
          ticket_as_json({
            id: 601,
            subject: 'Bundle install error',
            labels: [],
            last_activity_at: time2_str,
            current_team_assignee: { user: {
              id: @supportbee_hongli.supportbee_user_id
            } }
          }, false)
        )
        stub2 = stub_supportbee_request('assigned_user=me',
          stubbed_body,
          @supportbee_hongli.supportbee_auth_token)
        stub3 = stub_supportbee_request('assigned_team=mine',
          make_tickets_array([]),
          @supportbee_hongli.supportbee_auth_token)

        # API requests for Tinco
        stub4 = stub_supportbee_request('assigned_user=none&assigned_team=none',
          make_tickets_array([]),
          @supportbee_tinco.supportbee_auth_token)
        stubbed_body = make_tickets_array(
          ticket_as_json({
            id: 610,
            subject: 'Metrics frontend crashes',
            labels: [],
            last_activity_at: time1_str,
            current_team_assignee: { user: {
              id: @supportbee_tinco.supportbee_user_id
            } }
          }, false),
          ticket_as_json({
            id: 611,
            subject: 'Indexer protocol change',
            labels: [],
            last_activity_at: time2_str,
            current_team_assignee: { user: {
              id: @supportbee_tinco.supportbee_user_id
            } }
          }, false)
        )
        stub4 = stub_supportbee_request('assigned_user=me',
          stubbed_body,
          @supportbee_tinco.supportbee_auth_token)
        stub5 = stub_supportbee_request('assigned_team=mine',
          make_tickets_array([]),
          @supportbee_tinco.supportbee_auth_token)

        SupportbeeAnalyzer.new.analyze

        assert_requested(stub1)
        assert_requested(stub2)
        assert_requested(stub3)
        assert_requested(stub4)
        assert_requested(stub5)

        expect(Ticket.count).to eq(4)
        expect(Ticket.where(title: 'Frequent memory warnings').count).to eq(1)
        expect(Ticket.where(title: 'Bundle install error').count).to eq(1)
        expect(Ticket.where(title: 'Metrics frontend crashes').count).to eq(1)
        expect(Ticket.where(title: 'Indexer protocol change').count).to eq(1)

        expect(Ticket.where(title: 'Frequent memory warnings').first.
          support_source.id).to eq(@supportbee_hongli.id)
        expect(Ticket.where(title: 'Bundle install error').first.
          support_source.id).to eq(@supportbee_hongli.id)
        expect(Ticket.where(title: 'Metrics frontend crashes').first.
          support_source.id).to eq(@supportbee_tinco.id)
        expect(Ticket.where(title: 'Indexer protocol change').first.
          support_source.id).to eq(@supportbee_tinco.id)
      end

      it 'creates corresponding internal tickets for support sources ' \
         'matching the assigned team' \
      do
        # API requests for Hongli
        stub1 = stub_supportbee_request('assigned_user=none&assigned_team=none',
          make_tickets_array([]),
          @supportbee_hongli.supportbee_auth_token)
        stub2 = stub_supportbee_request('assigned_user=me',
          make_tickets_array([]),
          @supportbee_hongli.supportbee_auth_token)
        stubbed_body = make_tickets_array(
          ticket_as_json({
            id: 600,
            subject: 'Frequent memory warnings',
            labels: [],
            last_activity_at: time1_str,
            current_team_assignee: { team: {
              id: passenger_team
            } }
          }, false),
          ticket_as_json({
            id: 601,
            subject: 'Bundle install error',
            labels: [],
            last_activity_at: time2_str,
            current_team_assignee: { team: {
              id: passenger_team
            } }
          }, false)
        )
        stub3 = stub_supportbee_request('assigned_team=mine',
          stubbed_body,
          @supportbee_hongli.supportbee_auth_token)

        # API requests for Tinco
        stub4 = stub_supportbee_request('assigned_user=none&assigned_team=none',
          make_tickets_array([]),
          @supportbee_tinco.supportbee_auth_token)
        stub5 = stub_supportbee_request('assigned_user=me',
          make_tickets_array([]),
          @supportbee_tinco.supportbee_auth_token)
        stubbed_body = make_tickets_array(
          ticket_as_json({
            id: 610,
            subject: 'Metrics frontend crashes',
            labels: [],
            last_activity_at: time1_str,
            current_team_assignee: { team: {
              id: union_station_team
            } }
          }, false),
          ticket_as_json({
            id: 611,
            subject: 'Indexer protocol change',
            labels: [],
            last_activity_at: time2_str,
            current_team_assignee: { team: {
              id: union_station_team
            } }
          }, false)
        )
        stub6 = stub_supportbee_request('assigned_team=mine',
          stubbed_body,
          @supportbee_tinco.supportbee_auth_token)

        SupportbeeAnalyzer.new.analyze
        assert_requested(stub1)
        assert_requested(stub2)
        assert_requested(stub3)
        assert_requested(stub4)
        assert_requested(stub5)
        assert_requested(stub6)
        expect(Ticket.count).to eq(6)
        expect(Ticket.where(title: 'Frequent memory warnings').count).to eq(2)
        expect(Ticket.where(title: 'Bundle install error').count).to eq(2)
        expect(Ticket.where(title: 'Metrics frontend crashes').count).to eq(1)
        expect(Ticket.where(title: 'Indexer protocol change').count).to eq(1)

        frequent_memory_warnings = Ticket.where(title: 'Frequent memory warnings').all
        bundle_install_error = Ticket.where(title: 'Bundle install error').all
        expect(frequent_memory_warnings.map { |t| t.support_source.id }.sort).to \
          eq([@supportbee_hongli.id, @supportbee_tinco.id].sort)
        expect(bundle_install_error.map { |t| t.support_source.id }.sort).to \
          eq([@supportbee_hongli.id, @supportbee_tinco.id].sort)

        expect(Ticket.where(title: 'Metrics frontend crashes').first.
          support_source.id).to eq(@supportbee_tinco.id)
        expect(Ticket.where(title: 'Indexer protocol change').first.
          support_source.id).to eq(@supportbee_tinco.id)
      end

      it 'creates corresponding internal tickets for all support sources ' \
         'if the Supportbee ticket is not assigned' \
      do
        # API requests for Hongli
        stubbed_body = make_tickets_array(
          ticket_as_json({
            id: 600,
            subject: 'Frequent memory warnings',
            labels: [],
            last_activity_at: time1_str
          }, false),
          ticket_as_json({
            id: 601,
            subject: 'Bundle install error',
            labels: [],
            last_activity_at: time2_str
          }, false)
        )
        stub1 = stub_supportbee_request('assigned_user=none&assigned_team=none',
          stubbed_body,
          @supportbee_hongli.supportbee_auth_token)
        stub2 = stub_supportbee_request('assigned_user=me',
          make_tickets_array([]),
          @supportbee_hongli.supportbee_auth_token)
        stub3 = stub_supportbee_request('assigned_team=mine',
          make_tickets_array([]),
          @supportbee_hongli.supportbee_auth_token)

        # API requests for Tinco
        stubbed_body = make_tickets_array(
          ticket_as_json({
            id: 610,
            subject: 'Metrics frontend crashes',
            labels: [],
            last_activity_at: time1_str
          }, false),
          ticket_as_json({
            id: 611,
            subject: 'Indexer protocol change',
            labels: [],
            last_activity_at: time2_str
          }, false)
        )
        stub4 = stub_supportbee_request('assigned_user=none&assigned_team=none',
          stubbed_body,
          @supportbee_tinco.supportbee_auth_token)
        stub5 = stub_supportbee_request('assigned_user=me',
          make_tickets_array([]),
          @supportbee_tinco.supportbee_auth_token)
        stub6 = stub_supportbee_request('assigned_team=mine',
          make_tickets_array([]),
          @supportbee_tinco.supportbee_auth_token)

        SupportbeeAnalyzer.new.analyze

        assert_requested(stub1)
        assert_requested(stub2)
        assert_requested(stub3)
        assert_requested(stub4)
        assert_requested(stub5)
        assert_requested(stub6)

        expect(Ticket.count).to eq(8)
        expect(Ticket.where(title: 'Frequent memory warnings').count).to eq(2)
        expect(Ticket.where(title: 'Bundle install error').count).to eq(2)
        expect(Ticket.where(title: 'Metrics frontend crashes').count).to eq(2)
        expect(Ticket.where(title: 'Indexer protocol change').count).to eq(2)

        frequent_memory_warnings = Ticket.where(title: 'Frequent memory warnings').all
        bundle_install_error = Ticket.where(title: 'Bundle install error').all
        metrics_frontend_crashes = Ticket.where(title: 'Metrics frontend crashes').all
        indexer_protocol_change = Ticket.where(title: 'Indexer protocol change').all

        expect(frequent_memory_warnings.map { |t| t.support_source.id }.sort).to \
          eq([@supportbee_hongli.id, @supportbee_tinco.id].sort)
        expect(bundle_install_error.map { |t| t.support_source.id }.sort).to \
          eq([@supportbee_hongli.id, @supportbee_tinco.id].sort)
        expect(metrics_frontend_crashes.map { |t| t.support_source.id }.sort).to \
          eq([@supportbee_hongli.id, @supportbee_tinco.id].sort)
        expect(indexer_protocol_change.map { |t| t.support_source.id }.sort).to \
          eq([@supportbee_hongli.id, @supportbee_tinco.id].sort)
      end
    end

    context 'given unanswered Supportbee tickets that have been reassigned to another team' do
      it 'deletes internal tickets corresponding to external tickets that a support resource no longer sees' do
        # API requests for Hongli
        stub1 = stub_supportbee_request('assigned_user=none&assigned_team=none',
          make_tickets_array([]),
          @supportbee_hongli.supportbee_auth_token
        ).times(2)
        stub2 = stub_supportbee_request('assigned_user=me',
          make_tickets_array([]),
          @supportbee_hongli.supportbee_auth_token
        ).times(2)
        stub3 = stub_supportbee_request('assigned_team=mine',
          make_tickets_array([
            ticket_as_json({
              id: 600,
              subject: 'Frequent memory warnings',
              labels: [],
              last_activity_at: time1_str,
              current_team_assignee: { team: {
                id: passenger_team
              } }
            }, false),
          ]),
          @supportbee_hongli.supportbee_auth_token
        ).then.to_return(
          status: 200,
          headers: { 'Content-Type' => 'application/json' },
          body: make_tickets_array([]).to_json
        )

        # API requests for Tinco
        stub4 = stub_supportbee_request('assigned_user=none&assigned_team=none',
          make_tickets_array([]),
          @supportbee_tinco.supportbee_auth_token
        ).times(2)
        stub5 = stub_supportbee_request('assigned_user=me',
          make_tickets_array([]),
          @supportbee_tinco.supportbee_auth_token
        ).times(2)
        stub6 = stub_supportbee_request('assigned_team=mine',
          make_tickets_array([]),
          @supportbee_tinco.supportbee_auth_token
        ).then.to_return(
          status: 200,
          headers: { 'Content-Type' => 'application/json' },
          body: make_tickets_array([
            ticket_as_json({
              id: 600,
              subject: 'Frequent memory warnings',
              labels: [],
              last_activity_at: time1_str,
              current_team_assignee: { team: {
                id: union_station_team
              } }
            }, false)
          ]).to_json
        )

        SupportbeeAnalyzer.new.analyze

        assert_requested(stub1)
        assert_requested(stub2)
        assert_requested(stub3)
        assert_requested(stub4)
        assert_requested(stub5)
        assert_requested(stub6)

        expect(@supportbee_hongli.tickets.count).to eq(1)
        expect(@supportbee_tinco.tickets.count).to eq(1)

        SupportbeeAnalyzer.new.analyze

        assert_requested(stub1, times: 2)
        assert_requested(stub2, times: 2)
        assert_requested(stub3, times: 2)
        assert_requested(stub4, times: 2)
        assert_requested(stub5, times: 2)
        assert_requested(stub6, times: 2)

        expect(@supportbee_hongli.tickets.count).to eq(0)
        expect(@supportbee_tinco.tickets.count).to eq(1)
      end
    end
  end

  context 'given two support sources, one with and one without internal tickets' do
    before :each do
      @user = create(:user)
      @supportbee_hongli = create(:supportbee,
        name: 'Supportbee Hongli',
        supportbee_auth_token: 'hongli',
        supportbee_user_id: 1234,
        supportbee_group_ids: [traveling_ruby_team, passenger_team, docker_team],
        user: @user)
      @supportbee_tinco = create(:supportbee,
        name: 'Supportbee Tinco',
        supportbee_auth_token: 'tinco',
        supportbee_user_id: 1235,
        supportbee_group_ids: [passenger_team, docker_team, union_station_team],
        user: @user)
    end

    specify 'if there are unanswered external tickets, it creates internal tickets ' \
            'in the support source that did not have any' \
    do
      @frequent_memory_warnings = create(:frequent_memory_warnings,
        support_source: @supportbee_hongli)

      # API requests by Hongli
      stub1 = stub_supportbee_request('assigned_user=none&assigned_team=none',
        make_tickets_array([]),
        @supportbee_hongli.supportbee_auth_token)
      stub2 = stub_supportbee_request('assigned_user=me',
        make_tickets_array([]),
        @supportbee_hongli.supportbee_auth_token)
      stub3 = stub_supportbee_request('assigned_team=mine',
        make_tickets_array([ticket_as_json(@frequent_memory_warnings, false)]),
        @supportbee_hongli.supportbee_auth_token)

      # API requests by Tinco
      stub4 = stub_supportbee_request('assigned_user=none&assigned_team=none',
        make_tickets_array([]),
        @supportbee_tinco.supportbee_auth_token)
      stub5 = stub_supportbee_request('assigned_user=me',
        make_tickets_array([]),
        @supportbee_tinco.supportbee_auth_token)
      stub6 = stub_supportbee_request('assigned_team=mine',
        make_tickets_array([ticket_as_json(@frequent_memory_warnings, false)]),
        @supportbee_tinco.supportbee_auth_token)

      SupportbeeAnalyzer.new.analyze

      assert_requested(stub1)
      assert_requested(stub2)
      assert_requested(stub3)
      assert_requested(stub4)
      assert_requested(stub5)
      assert_requested(stub6)
      expect(Ticket.count).to eq(2)
    end
  end
end
