require 'spec_helper_acceptance'

test_name 'client -> 1 server without TLS'

describe 'rsyslog client -> 1 server without TLS' do
  let(:client){ only_host_with_role( hosts, 'client' ) }
  let(:server){ hosts_with_role( hosts, 'server' ).first }
  let(:client_fqdn){ fact_on( client, 'fqdn' ) }
  let(:server_fqdn){ fact_on( server, 'fqdn' ) }
  let(:client_manifest) {
    <<-EOS
      class { 'rsyslog':
        log_server_list    => ['server-1'],
        enable_logrotate     => true,
        enable_tls_logging => false,
        enable_pki         => false,
      }

      rsyslog::rule::remote { 'send_the_logs':
        rule => '*.*'
      }
    EOS
  }
  let(:server_manifest) {
    <<-EOS
      # Turns off firewalld in EL7.  Presumably this would already be done.
      include 'iptables'
      iptables::add_tcp_stateful_listen { 'ssh':
        dports      => '22',
        client_nets => 'any',
      }

      class { 'rsyslog':
        tcp_server         => true,
        enable_logrotate   => true,
        enable_tls_logging => false,
        enable_pki         => false,
        client_nets        => 'any',
      }

      class { 'rsyslog::server':
        enable_firewall    => true,
        enable_selinux     => false,
        enable_tcpwrappers => false,
      }

      # define a dynamic file with an rsyslog template
      # NOTE: puppet doesn't need to manage missing directories in this path;
      #       rsyslog will create them as needed.
      rsyslog::template::string { 'log_everything_by_host':
        string => '/var/log/hosts/%HOSTNAME%/everything.log',
      }

      # log all messages to the dynamic file we just defined ^^
      rsyslog::rule::local { 'all_the_logs':
       rule      => '*.*',
       dyna_file => 'log_everything_by_host',
      }
    EOS
  }

  context 'client -> 1 server without TLS' do
    it 'should configure server without errors' do
      apply_manifest_on(server, server_manifest, :catch_failures => true)
    end

    it 'should configure server idempotently' do
      apply_manifest_on(server, server_manifest, :catch_changes => true)
    end

    it 'should configure client without errors' do
      apply_manifest_on(client, client_manifest, :catch_failures => true)
    end

    it 'should configure client idempotently' do
      apply_manifest_on(client, client_manifest, :catch_changes => true)
    end

    it 'should successfully send log messages' do
      on client, 'logger -t FOO TEST-WITHOUT-TLS'
      remote_log = "/var/log/hosts/#{client_fqdn}/everything.log"
      on server, "test -f #{remote_log}"
      on server, "grep TEST-WITHOUT-TLS #{remote_log}"
    end
  end
end
