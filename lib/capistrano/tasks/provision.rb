def provision_template name
  root = Pathname.new(fetch(:local_root_directory))
  path = root.join('lib','capistrano','tasks','provision',"#{name}.erb")
  template = File.read path
  ERB.new(template)
end
namespace :provision do
  task :check_requirements do
    root = Pathname.new(fetch(:local_root_directory))
    ruby_version_file = root.join('.ruby-version')
    ruby_gem_file = root.join('.ruby-gemset')
    raise 'Missing .ruby-version file' unless File.exists?(ruby_version_file)
    raise 'Missing .ruby-gemset file' unless File.exists?(ruby_gem_file)
    env = fetch(:rails_env).to_s
    database_yml = File.read(root.join('config','database.yml'))
    database_config = YAML.load(database_yml)
    raise "Missing database config for #{env} environment" if database_config[env].nil?
    raise "Database must be PostgreSQL" unless database_config[env]['adapter'] == 'postgresql'
  end

  task :set_server_name do
    on roles(:all) do |host|
      server_name = host.properties.provision[:server_name]
      execute "sudo bash -c 'echo #{server_name} > /etc/hostname'"
      execute "sudo bash -c \"sed -i '/^127\.0\.[0-9]\.1/d' /etc/hosts\""
      execute "sudo bash -c 'echo \"127.0.0.1 localhost #{server_name}\" >> /etc/hosts'"
      execute "sudo /etc/init.d/hostname.sh start"
    end
  end

  task :set_prompt do
    on roles :all do
      prompt = "\\j:\\u@\\H \\w\\$ "
      execute "sudo bash -c 'echo \"PS1=\\\"#{prompt}\\\"\" >> /etc/bash.bashrc'"
    end
  end

  task :copy_ssh_keys do
    on roles :all do |host|
      ssh_keys = fetch(:ssh_keys).values
      user = host.user
      execute "sudo bash -c 'echo > /root/.ssh/authorized_keys'"
      execute "echo > /home/#{user}/.ssh/authorized_keys"
      ssh_keys.each do |key|
        execute "sudo bash -c \"echo '#{key}' >> /root/.ssh/authorized_keys\""
        execute "echo '#{key}' >> /home/#{user}/.ssh/authorized_keys"
      end
    end
  end

  task :create_deploy_user do
    on roles :all do |host|
      user = host.user
      server_name = host.properties.provision[:server_name]
      old_user = host.user
      old_password = host.password
      host.user = 'root'
      host.password = fetch(:root_password)
      begin
        info "Creating user #{user} on #{server_name}"
        execute "adduser --disabled-password --quiet --gecos '' #{user}"
        execute "apt-get update"
        execute "DEBIAN_FRONTEND=noninteractive apt-get -y install sudo lsb-release"
        execute "echo '#{user} ALL=(ALL:ALL) NOPASSWD: ALL, SETENV: ALL' >> /etc/sudoers"
        execute "rm /home/#{user}/.bashrc"

        ssh_keys = fetch(:ssh_keys).values
        execute "mkdir -p /root/.ssh"
        execute "mkdir -p /home/#{user}/.ssh"
        ssh_keys.each do |key|
          execute "echo '#{key}' >> /root/.ssh/authorized_keys"
          execute "echo '#{key}' >> /home/#{user}/.ssh/authorized_keys"
        end
        execute "chmod 0700 /root/.ssh"
        execute "chmod 0700 /home/#{user}/.ssh"
        execute "chmod 0600 /root/.ssh/authorized_keys"
        execute "chmod 0600 /home/#{user}/.ssh/authorized_keys"
        execute "chown -R #{user}:#{user} /home/#{user}"
      ensure
        host.user = old_user
        host.password = old_password
      end
    end
  end

  task :install_rvm do
    ruby_version = fetch(:rvm_ruby_without_gemset)
    ruby_gemset = fetch(:rvm_gemset)
    on roles :all do |host|
      execute "export DEBIAN_FRONTEND=noninteractive; sudo -E apt-get -y install curl"
      execute "\\curl -sSL https://get.rvm.io | sudo bash -s stable"
      execute "sudo usermod -a -G rvm #{host.user}"
      execute "sudo usermod -a -G rvm root"
    end
    invoke 'provision:configure_rvm'
  end

  task :configure_rvm do
    ruby_version = fetch(:rvm_ruby_without_gemset)
    ruby_gemset = fetch(:rvm_gemset)
    on roles :all do |host|
      execute "/usr/local/rvm/bin/rvm install #{ruby_version} > /dev/null"
      execute "/usr/local/rvm/bin/rvm #{ruby_version} gemset create #{ruby_gemset}"
      execute "/usr/local/rvm/bin/rvm alias create #{fetch(:application)} #{ruby_version}@#{ruby_gemset}"
      execute "/usr/local/rvm/bin/rvm wrapper #{fetch(:application)} bundle"
    end
  end

  task :install_postgresql do
    database_yml = File.read(File.join(File.dirname(__FILE__),'..','..','..','config','database.yml'))
    database_config = YAML.load(database_yml)[fetch(:rails_env).to_s]
    on roles :all do |host|
      release_name = capture('lsb_release -sc').chomp
      execute "sudo bash -c 'echo \"deb http://apt.postgresql.org/pub/repos/apt/ #{release_name}-pgdg main\" > /etc/apt/sources.list.d/pgdg.list'"
      execute "wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -"
      execute "sudo apt-get update"
      execute "export DEBIAN_FRONTEND=noninteractive; sudo -E apt-get -y install postgresql-9.3 postgresql-9.3-plv8"
      database = database_config['database']
      execute "echo 'CREATE EXTENSION plv8 schema pg_catalog;' | sudo su postgres -c 'psql template1'"
      execute "sudo su postgres -c 'createuser #{host.user}'"
      execute "sudo su postgres -c 'createdb #{database}'"
      execute "echo 'GRANT ALL PRIVILEGES ON DATABASE #{database} TO #{host.user};' | sudo su postgres -c 'psql template1'"
      execute "export DEBIAN_FRONTEND=noninteractive; sudo -E apt-get -y install libpq-dev"
      execute "sudo sed -i 's/local[ tab]\\+all[ tab]\\+all[ tab]\\+peer/local all all trust/' /etc/postgresql/9.3/main/pg_hba.conf"
      execute "sudo /etc/init.d/postgresql restart"
    end
  end

  task :create_deploy_directory do
    on roles :all do |host|
      execute "sudo mkdir -p /var/www"
      execute "sudo chown -R deploy:deploy /var/www"
    end
  end

  task :install_dependencies do
    on roles :all do
      deps = %w(git bzip2 gawk g++ gcc make libc6-dev libreadline6-dev zlib1g-dev libssl-dev libyaml-dev libsqlite3-dev sqlite3 autoconf libgdbm-dev libncurses5-dev automake libtool bison pkg-config libffi-dev ntp)
      execute "export DEBIAN_FRONTEND=noninteractive; sudo -E apt-get -y install #{deps.join(' ')}"
    end
  end

  task :install_nginx do
    on roles :all do |host|
      execute "export DEBIAN_FRONTEND=noninteractive; sudo -E apt-get -y install nginx"
      execute "sudo rm /etc/nginx/nginx.conf"
      execute "sudo ln -s #{current_path.join('etc',fetch(:rails_env).to_s,'nginx','nginx.conf')} /etc/nginx/nginx.conf"
    end
  end

  task :install_iptables do
    on roles :all do |host|
      execute "sudo ln -s #{current_path}/etc/#{fetch(:rails_env)}/iptables.conf /etc/iptables.conf"
      execute "sudo bash -c 'echo \"#!/bin/bash\n/sbin/iptables-restore < /etc/iptables.conf\" > /etc/network/if-pre-up.d/iptables'"
      execute "sudo chmod +x /etc/network/if-pre-up.d/iptables"
    end
  end

  task :install_upstart_conf do
    on roles :all do |host|
      content = provision_template(:unicorn_upstart).result(binding)
      upload!(StringIO.new(content),'/tmp/unicorn_tmp')
      execute "sudo mv -f /tmp/unicorn_tmp /etc/init.d/unicorn"
      execute "sudo chmod +x /etc/init.d/unicorn"
      execute "sudo update-rc.d unicorn defaults; true"
    end
  end

  task :install_imagemagick do
    on roles :all do |host|
      execute "export DEBIAN_FRONTEND=noninteractive; sudo -E apt-get -y install libmagickcore-dev libmagickwand-dev"
    end
  end
end

namespace :iptables do
  task :load do
    on roles :all do |host|
      execute "sudo iptables-restore < #{current_path}/etc/#{fetch(:rails_env)}/iptables.conf"
    end
  end
end

namespace :unicorn do
  desc "Zero-downtime restart of Unicorn"
  task :restart do
    invoke 'unicorn:start'
    on roles :app do
      execute "kill -s USR2 `cat #{fetch(:unicorn_pid_file)}`"
    end
  end

  desc "Start unicorn"
  task :start do
    on roles :app do
      within release_path do
        with rails_env: fetch(:rails_env), bundle_gemfile: "#{current_path}/Gemfile" do
          pid = "`cat #{fetch(:unicorn_pid_file)}`"
          if test("[ -e #{fetch(:unicorn_pid_file)} ] && kill -0 #{pid}")
            info "Unicorn is already running"
          else
            execute :bundle, 'exec unicorn', '-c', Pathname.new(current_path).join("config/unicorn/#{fetch(:rails_env)}.rb"), '-E', fetch(:rails_env), '-D'
          end
        end
      end
    end
  end

  desc "Stop unicorn"
  task :stop do
    on roles :app do
      within release_path do
        pid = "`cat #{fetch(:unicorn_pid_file)}`"
        if test("[ -e #{fetch(:unicorn_pid_file)} ]")
          if test("kill -0 #{pid}")
            info "Stopping unicorn."
            execute :kill, "-s QUIT", pid
          else
            info "Cleaning up dead unicorn pid."
            execute :rm, fetch(:unicorn_pid_file)
          end
        else
          info "Unicorn is not running."
        end
      end
    end
  end
end

#before 'unicorn:add_worker', 'rvm:hook'
#before 'unicorn:reload', 'rvm:hook'
#before 'unicorn:remove_worker', 'rvm:hook'
before 'unicorn:restart', 'rvm:hook'
before 'unicorn:start', 'rvm:hook'
before 'unicorn:stop', 'rvm:hook'


namespace :nginx do
  task :start do
    on roles :app do
      execute "sudo /etc/init.d/nginx start"
    end
  end
  task :stop do
    on roles :app do
      execute "sudo /etc/init.d/nginx stop"
    end
  end
  task :restart do
    on roles :app do
      execute "sudo /etc/init.d/nginx restart"
    end
  end
end

desc 'monsterboxify - Setups the server'
task :monsterboxify do
  ask :root_password, ''
  invoke 'provision:create_deploy_user'
  invoke 'provision:set_server_name'
  invoke 'provision:set_prompt'
  invoke 'provision:install_dependencies'
  invoke 'provision:install_rvm'
  invoke 'provision:install_postgresql'
  invoke 'provision:install_iptables'
  invoke 'provision:create_deploy_directory'
  invoke 'deploy:check'
  invoke 'provision:install_nginx'
  invoke 'provision:install_upstart_conf'
end
before 'provision:create_deploy_user', 'provision:check_requirements'

__END__

After changing iptables: iptables:load
After changing nginx config: nginx:restart
After changing ruby version or gemset: provision:configure_rvm
After first deploy:
  nginx:restart
  iptables:load
