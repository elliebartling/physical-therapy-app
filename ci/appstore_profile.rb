#!/usr/bin/env ruby
# frozen_string_literal: true

# Gets the App Store provisioning profile for the app and installs it, so the
# ship workflow can sign manually with the distribution certificate it already
# has. Automatic signing would mint a new Apple Development certificate on
# every fresh runner, and the account runs out of them.
#
# Through the App Store Connect API, with the same key the upload uses:
#   1. enables any missing capabilities on the bundle ID (e.g. HEALTHKIT);
#   2. finds the distribution certificate by the serial of the one CI imported;
#   3. reuses an active profile with PROFILE_NAME for that bundle ID and
#      certificate, or deletes stale ones with that name and creates a new one;
#   4. installs it and writes `uuid=` to $GITHUB_OUTPUT.
#
# Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH, BUNDLE_ID, DIST_CERT_PEM_PATH,
#      PROFILE_NAME, CAPABILITIES (comma-separated, optional).
# Only Ruby's standard library, which every macOS runner has.

require 'fileutils'
require 'json'
require 'net/http'
require 'openssl'
require 'time'
require 'uri'

API = 'https://api.appstoreconnect.apple.com'

def env(name) = ENV.fetch(name) { abort "::error::#{name} is not set." }

KEY_ID = env('ASC_KEY_ID')
ISSUER_ID = env('ASC_ISSUER_ID')
KEY_PATH = env('ASC_KEY_PATH')
BUNDLE_ID = env('BUNDLE_ID')
CERT_PEM_PATH = env('DIST_CERT_PEM_PATH')
PROFILE_NAME = env('PROFILE_NAME')
CAPABILITIES = ENV.fetch('CAPABILITIES', '').split(',').map(&:strip).reject(&:empty?)

def base64url(bytes) = [bytes].pack('m0').tr('+/', '-_').delete('=')

# An ES256 token for the App Store Connect API (valid 15 minutes).
def token
  @token ||= begin
    now = Time.now.to_i
    header = { alg: 'ES256', kid: KEY_ID, typ: 'JWT' }
    claims = { iss: ISSUER_ID, iat: now, exp: now + (15 * 60), aud: 'appstoreconnect-v1' }
    input = "#{base64url(header.to_json)}.#{base64url(claims.to_json)}"
    der = OpenSSL::PKey.read(File.read(KEY_PATH)).sign(OpenSSL::Digest.new('SHA256'), input)
    # JWT wants the raw 64-byte r||s, not OpenSSL's DER sequence.
    r, s = OpenSSL::ASN1.decode(der).value.map { |n| n.value.to_s(2).rjust(32, "\0")[-32, 32] }
    "#{input}.#{base64url(r + s)}"
  end
end

def query(params) = URI.encode_www_form(params)

def api(method, path, body = nil)
  uri = URI(API + path)
  request = Net::HTTP.const_get(method.capitalize).new(uri)
  request['Authorization'] = "Bearer #{token}"
  request['Content-Type'] = 'application/json'
  request.body = body.to_json if body
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
  unless response.is_a?(Net::HTTPSuccess)
    abort "::error::App Store Connect #{method.upcase} #{uri.path} failed (#{response.code}): #{response.body}"
  end
  response.body.to_s.empty? ? {} : JSON.parse(response.body)
end

def hex_serial(value) = value.to_s.upcase.sub(/\A0+/, '')

# 1. The bundle ID and its capabilities.
bundle = api('get', "/v1/bundleIds?#{query('filter[identifier]' => BUNDLE_ID, 'limit' => 200)}")['data']
         .find { |b| b.dig('attributes', 'identifier') == BUNDLE_ID }
abort "::error::Bundle ID #{BUNDLE_ID} isn't registered in this account." unless bundle

enabled = api('get', "/v1/bundleIds/#{bundle['id']}/bundleIdCapabilities")['data']
          .map { |c| c.dig('attributes', 'capabilityType') }
added_capability = false
CAPABILITIES.each do |capability|
  next if enabled.include?(capability)

  api('post', '/v1/bundleIdCapabilities', {
    data: {
      type: 'bundleIdCapabilities',
      attributes: { capabilityType: capability },
      relationships: { bundleId: { data: { type: 'bundleIds', id: bundle['id'] } } }
    }
  })
  puts "Enabled #{capability} on #{BUNDLE_ID}."
  added_capability = true
end

# 2. The distribution certificate CI imported.
serial = hex_serial(OpenSSL::X509::Certificate.new(File.read(CERT_PEM_PATH)).serial.to_s(16))
certificates = api('get', "/v1/certificates?#{query('filter[certificateType]' => 'DISTRIBUTION,IOS_DISTRIBUTION',
                                                    'limit' => 200)}")['data']
certificate = certificates.find { |c| hex_serial(c.dig('attributes', 'serialNumber')) == serial }
unless certificate
  abort "::error::The distribution certificate in DIST_CERT_P12_BASE64 (serial #{serial}) " \
        "isn't an active certificate in this App Store Connect account."
end

# 3. Reuse a good profile, or replace stale ones.
existing = api('get', "/v1/profiles?#{query('filter[name]' => PROFILE_NAME, 'include' => 'bundleId,certificates',
                                             'limit' => 200)}")['data']
usable = lambda do |profile|
  attributes = profile['attributes']
  attributes['profileState'] == 'ACTIVE' &&
    attributes['profileType'] == 'IOS_APP_STORE' &&
    Time.parse(attributes['expirationDate']) > Time.now + (7 * 24 * 3600) &&
    profile.dig('relationships', 'bundleId', 'data', 'id') == bundle['id'] &&
    Array(profile.dig('relationships', 'certificates', 'data')).any? { |c| c['id'] == certificate['id'] }
end
# A capability change invalidates existing profiles, so make a new one then.
profile = added_capability ? nil : existing.find(&usable)

if profile
  puts "Reusing profile #{PROFILE_NAME} (#{profile.dig('attributes', 'uuid')})."
else
  existing.each do |stale|
    api('delete', "/v1/profiles/#{stale['id']}")
    puts "Deleted stale profile #{PROFILE_NAME} (#{stale.dig('attributes', 'uuid')})."
  end
  profile = api('post', '/v1/profiles', {
    data: {
      type: 'profiles',
      attributes: { name: PROFILE_NAME, profileType: 'IOS_APP_STORE' },
      relationships: {
        bundleId: { data: { type: 'bundleIds', id: bundle['id'] } },
        certificates: { data: [{ type: 'certificates', id: certificate['id'] }] }
      }
    }
  })['data']
  puts "Created profile #{PROFILE_NAME} (#{profile.dig('attributes', 'uuid')})."
end

# 4. Install it where Xcode looks.
uuid = profile.dig('attributes', 'uuid')
content = profile.dig('attributes', 'profileContent').to_s.unpack1('m')
abort '::error::App Store Connect returned an empty profile.' if uuid.to_s.empty? || content.empty?

["#{Dir.home}/Library/MobileDevice/Provisioning Profiles",
 "#{Dir.home}/Library/Developer/Xcode/UserData/Provisioning Profiles"].each do |dir|
  FileUtils.mkdir_p(dir)
  File.binwrite(File.join(dir, "#{uuid}.mobileprovision"), content)
end

File.open(ENV['GITHUB_OUTPUT'], 'a') { |f| f.puts "uuid=#{uuid}" } if ENV['GITHUB_OUTPUT']
puts "Installed profile #{uuid}."
