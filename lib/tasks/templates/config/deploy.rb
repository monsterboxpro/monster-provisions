set :application, 'prov'
set :deploy_via, :remote_cache
set :scm, :git
set :repo_url, ''
set :linked_dirs, %w(bin log tmp/pids tmp/cache tmp/sockets vendor/bundle public/system)
set :keep_releases, 2
set :ssh_keys, {
  person1: '',
  person2: ''
}

root_directory    = Pathname.new(File.join(File.dirname(__FILE__),'..'))
ruby_version_file = root_directory.join('.ruby-version')
ruby_version      = File.read(ruby_version_file).chomp
ruby_gemset_file  = root_directory.join('.ruby-gemset')
ruby_gemset       = File.read(ruby_gemset_file).chomp

set :rvm_type               , :system
set :rvm_ruby_without_gemset, ruby_version
set :rvm_ruby_version       , "#{ruby_version}@#{ruby_gemset}"
set :rvm_gemset             , ruby_gemset

set :pty, true

namespace :deploy do
  task :restart do
  end
  after :finishing, 'deploy:cleanup'
  after :finished , 'unicorn:restart'
end
