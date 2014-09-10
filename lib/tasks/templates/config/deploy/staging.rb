set :rails_env, :staging
set :deploy_to, "/var/www/#{fetch(:rails_env)}.#{fetch(:application)}"
set :stage, :staging
server '', user: 'deploy', roles: %w(web app db),
  provision: {
    server_name: "#{fetch(:rails_env)}.#{fetch(:application)}"
  }
set :unicorn_pid_file, "#{fetch(:deploy_to)}/shared/tmp/pids/unicorn.pid"
