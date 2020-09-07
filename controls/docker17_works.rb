title 'Tests to confirm docker works as expected'

plan_origin = ENV['HAB_ORIGIN']
plan_name = input('plan_name', value: 'docker')

control 'core-plans-docker-works' do
  impact 1.0
  title 'Ensure docker works as expected'
  desc '
  Verify docker by ensuring 
  (1) its installation directory exists and 
  (2) that it returns the expected version.  Note that as the CI uses docker
  to run the tests, it is expected for docker to return warning, which are 
  accounted for in the tests.  This will not normally happen in hab studio or
  a linux environment
  '
  
  plan_installation_directory = command("hab pkg path #{plan_origin}/#{plan_name}")
  describe plan_installation_directory do
    its('exit_status') { should eq 0 }
    its('stdout') { should_not be_empty }
    its('stderr') { should be_empty }
  end
  
  command_relative_path = input('command_relative_path', value: 'bin/docker')
  command_full_path = File.join(plan_installation_directory.stdout.strip, command_relative_path)
  plan_pkg_version = plan_installation_directory.stdout.split("/")[5]
  describe command("#{command_full_path} version") do
    its('exit_status') { should eq 0 }
    its('stdout') { should_not be_empty }
    its('stdout') { should match /Version:\s+(?<version>#{plan_pkg_version})/ }
    its('stderr') { should be_empty }
    # its('stderr') { should match /Cannot connect to the Docker daemon at unix:\/\/\/var\/run\/docker.sock/ }
  end

  full_suite = {
    "docker" => {
      command_suffix: "version",
      command_output_pattern: /Version:\s+(?<version>#{plan_pkg_version})/,
    },
    "docker-containerd" => {},
    "docker-containerd-ctr" => {},
    "docker-containerd-shim" => {
      io: "stderr",
      exit_pattern: /^[^0]{1}\d*$/, 
      command_output_pattern: /Usage of.*docker-containerd-shim/,
    },
    "docker-init" => {
      io: "stderr",
      exit_pattern: /^[^0]{1}\d*$/, 
    },
    "docker-proxy" => {
      io: "stderr",
      exit_pattern: /^[^0]{1}\d*$/, 
      command_output_pattern: /Usage of.*docker-proxy/,
    },
    "docker-runc" => {},
    "dockerd" => {},
  }

  # Use the following to pull out a subset of the above and test progressiveluy
  subset = full_suite.select { |key, value| key.to_s.match(/^.*$/) }

  # over-ride the defaults below with (command_suffix:, io:, etc)
  subset.each do |binary_name, value|
    # set default values if each binary doesn't define an over-ride
    command_prefix = value[:command_prefix] || "" 
    command_suffix = value[:command_suffix] || "--help"
    command_output_pattern = value[:command_output_pattern] || /usage:\s*#{binary_name}/i
    exit_pattern = value[:exit_pattern] || /^[0]$/ # use /^[^0]{1}\d*$/ for non-zero exit status
    io = value[:io] || "stdout"
    script = value[:script]

    # set default 'command_under_test' only adding a Tempfile if 'script' is defined
    command_full_path = File.join(plan_installation_directory.stdout.strip, "bin", binary_name)
    command_statement = "#{command_prefix} #{command_full_path} #{command_suffix}"
    command_under_test = nil
    if(script)
      Tempfile.open('foo') do |f|
        f << script
        command_under_test = command("#{command_statement} #{f.path}")
      end
    else
      command_under_test = command("#{command_statement}")
    end

    # verify output
    describe command_under_test do
      its('exit_status') { should cmp exit_pattern }
      its(io) { should match command_output_pattern }
    end
  end
end