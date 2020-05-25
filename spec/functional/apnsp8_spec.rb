require 'functional_spec_helper'

describe 'APNsP8' do
  let(:fake_client) {
    double(
      prepare_request: fake_http2_request,
      close:           'ok',
      call_async:      'ok',
      join:            'ok',
      on:              'ok',
      stream_count:    1,
      remote_settings: { settings_max_concurrent_streams: 1 }
    )
  }
  let(:app) { create_app }
  let(:fake_device_token) { 'a' * 108 }
  let(:fake_http2_request) { double }
  let(:fake_http_resp_headers) {
    {
      ":status" => "200",
      "apns-id"=>"C6D65840-5E3F-785A-4D91-B97D305C12F6"
    }
  }
  let(:fake_http_resp_body) { '' }
  let(:notification_data) { nil }

  before do
    Rpush.config.push_poll = 0.5
    allow(NetHttp2::Client).
      to receive(:new).and_return(fake_client)
    allow(fake_http2_request).
      to receive(:on).with(:headers).
      and_yield(fake_http_resp_headers)
    allow(fake_http2_request).
      to receive(:on).with(:body_chunk).
      and_yield(fake_http_resp_body)
    allow(fake_http2_request).
      to receive(:on).with(:close).
      and_yield
  end

  def create_app
    app = Rpush::Apnsp8::App.new
    app.certificate = TEST_CERT
    app.apn_key = "-----BEGIN PRIVATE KEY-----
MIGTAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBHkwdwIBAQQgtS8saZzuW/QcZ4QA
9qKbgjyIMW4kRfB9utEcMGx4zlWgCgYIKoZIzj0DAQehRANCAASZw4wGN4pGCoN0
h/lkoo8E/PFoBF1lSeNRnTtFR+a7a15HfG+jeORguYH15YZ+qnFi3Ftk5xkDU4Lg
KwfcsEfw
-----END PRIVATE KEY-----"
    app.apn_key_id = 'test'
    app.team_id = 'test'
    app.bundle_id = 'test'
    app.name = 'test'
    app.environment = 'sandbox'
    app.save!
    app
  end

  def create_notification
    notification = Rpush::Apnsp8::Notification.new
    notification.app = app
    notification.alert = 'test'
    notification.device_token = 'a' * 108
    notification.save!
    notification
  end

  it 'delivers a notification successfully' do
    notification = create_notification

    thread = nil
    expect(fake_http2_request).
      to receive(:on).with(:close) { |&block|
        # imitate HTTP2 delay
        thread = Thread.new { sleep(0.01); block.call }
      }
    expect(fake_client).to receive(:join) { thread.join }

    expect(fake_client)
      .to receive(:prepare_request)
      .and_return(fake_http2_request)

    expect do
      Rpush.push
      notification.reload
    end.to change(notification, :delivered).to(true)
  end

  context 'when one of notifications requests timed out' do
    it 'delivers one notification successfully, and retries timed out one' do
      notification = create_notification

      expect(fake_client).to receive(:join) { raise(Timeout::Error) }
      expect(fake_http2_request).to receive(:on).with(:close)
        .exactly(1).times.and_return(nil)

      expect(fake_client)
        .to receive(:prepare_request)
        .and_return(fake_http2_request)

      expect(notification.delivered).to be_falsey

      Rpush.push

      expect(notification.reload.retries).to be > 0
    end
  end
end
