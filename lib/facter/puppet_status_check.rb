# puppet_status_check fact aims to have all chunks reporting as true this indicates ideal state
# any individual chunk reporting false should be alerted on and checked against documentation for next steps
# Use shared logic from PuppetStatusCheck
Facter.add(:puppet_status_check, type: :aggregate) do
  confine { PuppetStatusCheck.enabled? }

  require 'puppet'
  require 'yaml'
  require_relative '../shared/puppet_status_check'

  chunk(:S0001) do
    next if PuppetStatusCheck.config('indicator_exclusions').include?('S0001')
    # Is the Agent Service Running and Enabled
    { S0001: PuppetStatusCheck.service_running_enabled('puppet') }
  end

  chunk(:S0003) do
    next if PuppetStatusCheck.config('indicator_exclusions').include?('S0003')
    # check for noop logic flip as false is the desired state
    { S0003: !Puppet.settings['noop'] }
  end

  chunk(:S0004) do
    next if PuppetStatusCheck.config('indicator_exclusions').include?('S0004')
    # Are All Services running
    next unless ['primary', 'compiler'].include?(PuppetStatusCheck.config('role'))

    response = PuppetStatusCheck.http_get('/status/v1/services', 8140)
    if response
      # In the reponse, keys are the names of the services and values are a hash of its properties
      # We can check that all are in 'running' state to see if all are ok
      all_running = response.values.all? do |service|
        service['state'] == 'running'
      end
      { S0004: all_running }
    else
      { S0004: false }
    end
  end

  chunk(:S0005) do
    next if PuppetStatusCheck.config('indicator_exclusions').include?('S0005')
    next unless ['primary'].include?(PuppetStatusCheck.config('role'))

    # Is the CA expiring in the next 90 days
    cacert = Puppet.settings[:cacert]
    next unless File.exist?(cacert)

    x509_cert = OpenSSL::X509::Certificate.new(File.read(cacert))
    { S0005: (x509_cert.not_after - Time.now) > 7_776_000 }
  end

  chunk(:S0007) do
    next if PuppetStatusCheck.config('indicator_exclusions').include?('S0007')
    next unless ['primary', 'postgres'].include?(PuppetStatusCheck.config('role'))

    begin
      # check postgres data mount has at least 20% free
      data_dir = PuppetStatusCheck.pg_data_dir

      { S0007: PuppetStatusCheck.filesystem_free(data_dir) >= 20 }
    rescue StandardError => e
      Facter.warn("Error in fact 'puppet_status_check.S0007' when checking postgres info: #{e.message}")
      Facter.debug(e.backtrace)
      { S0007: false }
    end
  end

  chunk(:S0008) do
    next if PuppetStatusCheck.config('indicator_exclusions').include?('S0008')
    next unless ['primary', 'compiler'].include?(PuppetStatusCheck.config('role'))

    # check codedir data mount has at least 20% free
    { S0008: PuppetStatusCheck.filesystem_free(Puppet.settings['codedir']) >= 20 }
  end

  chunk(:S0009) do
    next if PuppetStatusCheck.config('indicator_exclusions').include?('S0009')
    next unless ['primary', 'compiler'].include?(PuppetStatusCheck.config('role'))

    # Is the Pe-puppetsever Service Running and Enabled
    { S0009: PuppetStatusCheck.service_running_enabled('puppetserver') }
  end

  chunk(:S0010) do
    next if PuppetStatusCheck.config('indicator_exclusions').include?('S0010')
    next unless ['primary', 'compiler'].include?(PuppetStatusCheck.config('role'))

    # Is the pe-puppetdb Service Running and Enabled
    { S0010: PuppetStatusCheck.service_running_enabled('puppetdb') }
  end

  chunk(:S0011) do
    next if PuppetStatusCheck.config('indicator_exclusions').include?('S0011')
    next unless ['primary', 'postgres'].include?(PuppetStatusCheck.config('role'))

    # Is the pe-postgres Service Running and Enabled
    begin
      service_name = PuppetStatusCheck.postgres_service_name
      status = PuppetStatusCheck.service_running_enabled(service_name)
    rescue StandardError => e
      Facter.warn("Error in fact 'puppet_status_check.S0011' failed to get service name: #{e.message}")
      Facter.debug(e.backtrace)
    end

    { S0011: status ? true : false }
  end

  chunk(:S0012) do
    next if PuppetStatusCheck.config('indicator_exclusions').include?('S0012')
    summary_path = Puppet.settings['lastrunfile']
    next unless File.exist?(summary_path)

    # Did Puppet Produce a report in the last run interval
    lastrunfile = YAML.load_file(summary_path)
    time_lastrun = lastrunfile.dig('time', 'last_run')
    if time_lastrun.nil?
      { S0012: false }
    else
      since_lastrun = Time.now - time_lastrun
      { S0012: since_lastrun.to_i <= Puppet.settings['runinterval'] }
    end
  end

  chunk(:S0013) do
    next if PuppetStatusCheck.config('indicator_exclusions').include?('S0013')
    summary_path = Puppet.settings['lastrunfile']
    next unless File.exist?(summary_path)

    lastrunfile = YAML.load_file(summary_path)
    catalog_application = lastrunfile.dig('time', 'catalog_application')
    # Did catalog apply successfully on last puppet run
    { S0013: !catalog_application.nil? }
  end

  chunk(:S0014) do
    next if PuppetStatusCheck.config('indicator_exclusions').include?('S0014')
    next unless ['primary', 'postgres'].include?(PuppetStatusCheck.config('role'))

    time_now = Time.now - (Puppet.settings['runinterval'].to_i * 2)
    res = Dir.glob('/opt/puppetlabs/server/data/puppetdb/stockpile/cmd/q/*').find { |f| time_now.to_i > File.mtime(f).to_i }
    { S0014: res.nil? }
  end

  chunk(:S0016) do
    next if PuppetStatusCheck.config('indicator_exclusions').include?('S0016')
    # Puppetserver
    next unless ['primary', 'compiler'].include?(PuppetStatusCheck.config('role'))

    time_now = Time.now - Puppet.settings['runinterval']
    log_path = File.dirname(Puppet.settings['logdir'].to_s) + '/puppetserver/'
    error_pid_log = Dir.glob(log_path + '*_err_pid*.log').find { |f| time_now.to_i < File.mtime(f).to_i }
    if error_pid_log.nil?
      log_file = log_path + 'puppetserver.log'
      search_for_error = `tail -n 250 #{log_file} | grep 'java.lang.OutOfMemoryError'`
      { S0016: search_for_error.empty? }
    else
      { S0016: false }
    end
  end

  chunk(:S0017) do
    next if PuppetStatusCheck.config('indicator_exclusions').include?('S0017')
    # PuppetDB
    next unless ['primary', 'compiler'].include?(PuppetStatusCheck.config('role'))

    time_now = Time.now - Puppet.settings['runinterval']
    log_path = File.dirname(Puppet.settings['logdir'].to_s) + '/puppetdb/'
    error_pid_log = Dir.glob(log_path + '*_err_pid*.log').find { |f| time_now.to_i < File.mtime(f).to_i }
    if error_pid_log.nil?
      log_file = log_path + 'puppetdb.log'
      search_for_error = `tail -n 250 #{log_file} | grep 'java.lang.OutOfMemoryError'`
      { S0017: search_for_error.empty? }
    else
      { S0017: false }
    end
  end

  chunk(:S0019) do
    next if PuppetStatusCheck.config('indicator_exclusions').include?('S0019')
    next unless ['primary', 'compiler'].include?(PuppetStatusCheck.config('role'))

    response = PuppetStatusCheck.http_get('/status/v1/services/jruby-metrics?level=debug', 8140)
    if response
      free_jrubies = response.dig('status', 'experimental', 'metrics', 'average-free-jrubies')
      {
        S0019: if free_jrubies.nil?
                 false
               elsif free_jrubies.is_a?(String)
                 false
               else
                 free_jrubies.to_f >= 0.9
               end
      }
    else
      { S0019: false }
    end
  end

  chunk(:S0021) do
    next if PuppetStatusCheck.config('indicator_exclusions').include?('S0021')
    # Is there at least 9% memory available
    { S0021: Facter.value(:memory)['system']['capacity'].to_f <= 90 }
  end

  chunk(:S0023) do
    next if PuppetStatusCheck.config('indicator_exclusions').include?('S0023')
    # Is the CA_CRL expiring in the next 90 days
    next unless ['primary'].include?(PuppetStatusCheck.config('role'))
    cacrl = Puppet.settings[:cacrl]
    next unless File.exist?(cacrl)

    x509_cert = OpenSSL::X509::CRL.new(File.read(cacrl))
    { S0023: (x509_cert.next_update - Time.now) > 7_776_000 }
  end

  chunk(:S0024) do
    next if PuppetStatusCheck.config('indicator_exclusions').include?('S0024')
    next unless ['primary', 'compiler'].include?(PuppetStatusCheck.config('role'))

    # Check discard directory. Newest file should not be less than a run interval old.
    # Recent files indicate an issue that causes PuppetDB to reject incoming data.
    newestfile = Dir.glob('/opt/puppetlabs/server/data/puppetdb/stockpile/discard/*.*').max_by { |f| File.mtime(f) }
    # get the timestamp for the most recent file
    if newestfile
      newestfile_time = File.mtime(newestfile)
      #  Newest file should be older than 2 run intervals
      { S0024: newestfile_time <= (Time.now - (Puppet.settings['runinterval'] * 2)).utc }
      #  Should return true if the file is older than two runintervals, or folder is empty, and false if sooner than two run intervals
    else
      { S0024: true }
    end
  end

  chunk(:S0026) do
    next if PuppetStatusCheck.config('indicator_exclusions').include?('S0026')
    next unless ['primary', 'compiler'].include?(PuppetStatusCheck.config('role'))

    response = PuppetStatusCheck.http_get('/status/v1/services/status-service?level=debug', 8140)
    if response
      heap_max = response.dig('status', 'experimental', 'jvm-metrics', 'heap-memory', 'init')
      {
        S0026: if heap_max.nil?
                 false
               elsif heap_max.is_a?(String)
                 false
               else
                 ((heap_max > 33_285_996_544) && (heap_max < 51_539_607_552)) ? false : true
               end
      }
    else
      { S0026: false }
    end
  end

  chunk(:S0027) do
    next if PuppetStatusCheck.config('indicator_exclusions').include?('S0027')
    next unless ['primary', 'compiler'].include?(PuppetStatusCheck.config('role'))

    response = PuppetStatusCheck.http_get('/status/v1/services?level=debug', 8081)
    if response
      heap_max = response.dig('status-service', 'status', 'experimental', 'jvm-metrics', 'heap-memory', 'init')
      {
        S0027: if heap_max.nil?
                 false
               elsif heap_max.is_a?(String)
                 false
               else
                 ((heap_max > 33_285_996_544) && (heap_max < 51_539_607_552)) ? false : true
               end
      }
    else
      { S0027: false }
    end
  end

  chunk(:S0029) do
    next if PuppetStatusCheck.config('indicator_exclusions').include?('S0029')
    next unless ['primary', 'postgres'].include?(PuppetStatusCheck.config('role'))
    # check if concurrnet connections to Postgres approaching 90% defined

    begin
      maximum = PuppetStatusCheck.max_connections.to_i
      current = PuppetStatusCheck.cur_connections.to_i
      percent_used = (current / maximum.to_f) * 100

      { S0029: percent_used <= 90 }
    rescue ZeroDivisionError
      Facter.warn("Fact 'puppet_status_check.S0029' failed to get max_connections: #{e.message}")
      Facter.debug(e.backtrace)
      { S0029: false }
    rescue StandardError => e
      Facter.warn("Error in fact 'puppet_status_check.S0029' when querying postgres: #{e.message}")
      Facter.debug(e.backtrace)
      { S0029: false }
    end
  end

  chunk(:S0030) do
    next if PuppetStatusCheck.config('indicator_exclusions').include?('S0030')
    # check for use_cached_catalog logic flip as false is the desired state
    { S0030: !Puppet.settings['use_cached_catalog'] }
  end

  chunk(:S0033) do
    next if PuppetStatusCheck.config('indicator_exclusions').include?('S0033')
    next unless ['primary', 'compiler'].include?(PuppetStatusCheck.config('role'))
    hiera_config_path = Puppet.settings['hiera_config']
    if File.exist?(hiera_config_path)
      hiera_config_file = YAML.load_file(hiera_config_path)
    else
      { S0033: false }
    end

    if hiera_config_file.is_a?(Hash) && !hiera_config_file.empty?
      hiera_version = hiera_config_file.dig('version')
      if hiera_version.nil?
        { S0033: false }
      else
        { S0033: hiera_version.to_i == 5 }
      end
    else
      { S0033: false }
    end
  end

  chunk(:S0034) do
    next if PuppetStatusCheck.config('indicator_exclusions').include?('S0034')
    next unless ['primary'].include?(PuppetStatusCheck.config('role'))

    # Has not been upgraded / updated in 1 year
    # It was decided not to include infra components as this was deemed unnecessary as they should align with the primary.

    # gets the file for the most recent upgrade output
    last_upgrade_file = '/opt/puppetlabs/server/apps/puppetserver/bin/puppetserver'
    next unless File.exist?(last_upgrade_file)
    # get the timestamp for the most recent upgrade
    last_upgrade_time = File.mtime(last_upgrade_file)

    # last upgrade was sooner than 1 year ago
    { S0034: last_upgrade_time >= (Time.now - 31_536_000).utc }
  end

  chunk(:S0035) do
    next if PuppetStatusCheck.config('indicator_exclusions').include?('S0035')
    # restrict to primary/compiler
    next unless ['primary', 'compiler'].include?(PuppetStatusCheck.config('role'))
    # return false if any Warnings appear in the 'puppet module list...'
    { S0035: !`/opt/puppetlabs/bin/puppet module list --tree 2>&1`.encode('ASCII', 'UTF-8', undef: :replace).match?(%r{Warning:\s+}) }
  end

  chunk(:S0036) do
    next if PuppetStatusCheck.config('indicator_exclusions').include?('S0036')
    next unless ['primary', 'compiler'].include?(PuppetStatusCheck.config('role'))
    str = File.read('/etc/puppetlabs/puppetserver/conf.d/puppetserver.conf')
    max_queued_requests = str.match(%r{max-queued-requests: (\d+)})
    if max_queued_requests.nil?
      { S0036: true }
    else
      { S0036: max_queued_requests[1].to_i < 151 }
    end
  end

  chunk(:S0038) do
    next if PuppetStatusCheck.config('indicator_exclusions').include?('S0038')
    next unless ['primary', 'compiler'].include?(PuppetStatusCheck.config('role'))
    response = PuppetStatusCheck.http_get('/puppet/v3/environments', 8140)
    if response
      envs_count = response.dig('environments').length
      {
        S0038: if envs_count.nil?
                 true
               elsif envs_count.is_a?(String)
                 true
               else
                 (envs_count < 100)
               end
      }
    else
      { S0038: false }
    end
  end

  chunk(:S0039) do
    next if PuppetStatusCheck.config('indicator_exclusions').include?('S0039')
    # PuppetServer
    next unless ['primary', 'compiler'].include?(PuppetStatusCheck.config('role'))

    logfile = File.dirname(Puppet.settings['logdir'].to_s) + '/puppetserver/puppetserver-access.log'
    next unless File.exist?(logfile)
    apache_regex = %r{^(\S+) \S+ (\S+) (?<time>\[([^\]]+)\]) "([A-Z]+) ([^ "]+)? HTTP/[0-9.]+" (?<status>[0-9]{3})}

    has_503 = File.foreach(logfile).any? do |line|
      match = line.match(apache_regex)
      next unless match && match[:time] && match[:status]

      time = Time.strptime(match[:time], '[%d/%b/%Y:%H:%M:%S %Z]')
      since_lastrun = Time.now - time
      current = since_lastrun.to_i <= Puppet.settings['runinterval']

      match[:status] == '503' and current
    rescue StandardError => e
      Facter.warn("Error in fact 'puppet_status_check.S0039' when querying puppetserver access logs: #{e.message}")
      Facter.debug(e.backtrace)
      break
    end

    { S0039: !has_503 }
  end

  chunk(:S0045) do
    next if PuppetStatusCheck.config('indicator_exclusions').include?('S0045')
    next unless ['primary', 'compiler'].include?(PuppetStatusCheck.config('role'))
    begin
      response = PuppetStatusCheck.http_get('/status/v1/services/jruby-metrics?level=debug', 8140)

      if response
        num_jrubies = response.dig('status', 'experimental', 'metrics', 'num-jrubies')

        unless num_jrubies.nil?
          { S0045: false }
        end

        { S0045: num_jrubies <= 12 }
      else
        { S0045: false }
      end
    rescue StandardError => e
      Facter.warn("Error in fact 'puppet_status_check.S0045': #{e.message}")
      Facter.debug(e.backtrace)
      { S0045: false }
    end
  end

  chunk(:AS001) do
    next if PuppetStatusCheck.config('indicator_exclusions').include?('AS001')
    # Is the hostcert expiring within 90 days
    #
    next unless File.exist?(Puppet.settings['hostcert'])
    raw_hostcert = File.read(Puppet.settings['hostcert'])
    certificate = OpenSSL::X509::Certificate.new raw_hostcert
    result = certificate.not_after - Time.now

    { AS001: result > 7_776_000 }
  end

  chunk(:AS003) do
    next if PuppetStatusCheck.config('indicator_exclusions').include?('AS003')
    # certname is not configured in section other than [main]
    #
    { AS003: !Puppet.settings.set_in_section?(:certname, :agent) && !Puppet.settings.set_in_section?(:certname, :server) && !Puppet.settings.set_in_section?(:certname, :user) }
  end

  chunk(:AS004) do
    next if PuppetStatusCheck.config('indicator_exclusions').include?('AS004')
    # Is the host copy of the crl expiring in the next 90 days
    hostcrl = Puppet.settings[:hostcrl]
    next unless File.exist?(hostcrl)

    x509_cert = OpenSSL::X509::CRL.new(File.read(hostcrl))
    { AS004: (x509_cert.next_update - Time.now) > 7_776_000 }
  end
end
