# frozen_string_literal: true
require_relative './environment.rb'

describe SiteIdentifierHistory do
  it 'records previous usernames and account emails' do
    site = Fabricate :site, username: "history-#{SecureRandom.hex(4)}"
    previous_username = site.username
    previous_email = site.email
    changed_at = Time.now

    Timecop.freeze(changed_at) do
      site.username = "renamed-#{SecureRandom.hex(4)}"
      site.save_changes

      site.email = "changed-#{SecureRandom.hex(4)}@example.com"
      site.save_changes
    end

    username_history = SiteIdentifierHistory.where(
      site_id: site.id,
      identifier_type: SiteIdentifierHistory::USERNAME
    ).first
    email_history = SiteIdentifierHistory.where(
      site_id: site.id,
      identifier_type: SiteIdentifierHistory::EMAIL
    ).first

    _(username_history.identifier).must_equal previous_username
    _(username_history.changed_at.to_i).must_equal changed_at.to_i
    _(email_history.identifier).must_equal previous_email
    _(email_history.changed_at.to_i).must_equal changed_at.to_i
    _(Site.get_with_identifier(previous_username)).must_be_nil
    _(Site.get_with_email(previous_email)).must_be_nil
  end

  it 'records each completed change in order' do
    site = Fabricate :site, username: "first-#{SecureRandom.hex(4)}"
    first_username = site.username
    second_username = "second-#{SecureRandom.hex(4)}"
    third_username = "third-#{SecureRandom.hex(4)}"

    site.username = second_username
    site.save_changes
    site.username = third_username
    site.save_changes

    identifiers = SiteIdentifierHistory.
      where(site_id: site.id, identifier_type: SiteIdentifierHistory::USERNAME).
      order(:changed_at, :id).
      select_map(:identifier)

    _(identifiers).must_equal [first_username, second_username]
  end

  it 'does not record rejected or unchanged identifiers' do
    site = Fabricate :site

    site.username = site.username
    site.email = site.email
    site.save_changes

    site.username = '../invalid'
    _(proc { site.save_changes }).must_raise Sequel::ValidationFailed

    _(SiteIdentifierHistory.where(site_id: site.id).count).must_equal 0
  end

  it 'does not record email changes on child sites' do
    parent_site = Fabricate :site
    child_site = Fabricate :site, parent_site_id: parent_site.id

    child_site.email = "child-#{SecureRandom.hex(4)}@example.com"
    child_site.save_changes

    _(SiteIdentifierHistory.where(site_id: child_site.id).count).must_equal 0
  end
end
