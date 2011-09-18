#
# Cookbook Name:: application
# Recipe:: rails
#
# Copyright 2009-2011, Opscode, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

app = node.run_state[:current_app]

# make the _default chef_environment look like the Rails production environment
rails_env = (node.chef_environment =~ /_default/ ? "production" : node.chef_environment)
node.run_state[:rails_env] = rails_env

###
# You really most likely don't want to run this recipe from here - let the
# default application recipe work it's mojo for you.
###

node.default[:apps][app['id']][node.chef_environment][:run_migrations] = false

## First, install any application specific packages
if app['packages']
  app['packages'].each do |pkg,ver|
    package pkg do
      action :install
      version ver if ver && ver.length > 0
    end
  end
end

## Next, install any application specific gems
if app['gems']
  app['gems'].each do |gem,ver|
    gem_package gem do
      action :install
      version ver if ver && ver.length > 0
    end
  end
end

directory app['deploy_to'] do
  owner app['owner']
  group app['group']
  mode '0755'
  recursive true
end

directory "#{app['deploy_to']}/shared" do
  owner app['owner']
  group app['group']
  mode '0755'
  recursive true
end

%w{ log pids system vendor_bundle }.each do |dir|
  directory "#{app['deploy_to']}/shared/#{dir}" do
    owner app['owner']
    group app['group']
    mode '0755'
    recursive true
  end

end

if app.has_key?("deploy_key")
  ruby_block "write_key" do
    block do
      f = ::File.open("#{app['deploy_to']}/id_deploy", "w")
      f.print(app["deploy_key"])
      f.close
    end
    not_if do ::File.exists?("#{app['deploy_to']}/id_deploy"); end
  end

  file "#{app['deploy_to']}/id_deploy" do
    owner app['owner']
    group app['group']
    mode '0600'
  end

  template "#{app['deploy_to']}/deploy-ssh-wrapper" do
    source "deploy-ssh-wrapper.erb"
    owner app['owner']
    group app['group']
    mode "0755"
    variables app.to_hash
  end
end

if app["database_master_role"]
  dbm = nil
  # If we are the database master
  if node.run_list.roles.include?(app["database_master_role"][0])
    dbm = node
  else
  # Find the database master
    results = search(:node, "role:#{app["database_master_role"][0]} AND chef_environment:#{node.chef_environment}", nil, 0, 1)
    rows = results[0]
    if rows.length == 1
      dbm = rows[0]
    end
  end

  unless dbm
    Chef::Log.warn("No node with role #{app["database_master_role"][0]}!")
  end
end

if !dbm && app["database_master_hosts"]
  dbm = Chef::Node.new
  dbm['ipaddress'] = app["database_master_hosts"][0]
end

# Assuming we have one...
if dbm
  template "#{app['deploy_to']}/shared/database.yml" do
    source "database.yml.erb"
    owner app["owner"]
    group app["group"]
    mode "644"
    variables(
      :host => (dbm.attribute?('cloud') ? dbm['cloud']['local_ipv4'] : dbm['ipaddress']),
      :databases => app['databases'],
      :rails_env => rails_env
    )
  end
else
  Chef::Log.warn("No database master found, database.yml not rendered!")
end

if app["memcached_role"]
  unless Chef::Config[:solo]
    memcached_nodes = search(:node, "role:#{app["memcached_role"][0]} AND chef_environment:#{node.chef_environment} NOT hostname:#{node[:hostname]}")
  else
    memcached_nodes = []
  end
  if memcached_nodes.length == 0
    if node.run_list.roles.include?(app["memcached_role"][0])
      memcached_nodes << node
    end
  end
end

if !memcached_nodes && app["memcached_hosts"]
  memcached_nodes = app["memcached_hosts"].collect do |server, port|
    cache_node = Chef::Node.new
    cache_node['ipaddress'] = server
    cache_node['memcached'] = {'port' => port}
    cache_node
  end
end

if memcached_nodes
  template "#{app['deploy_to']}/shared/memcached.yml" do
    source "memcached.yml.erb"
    owner app["owner"]
    group app["group"]
    mode "644"
    variables(
      :memcached_envs => app['memcached'],
      :hosts => memcached_nodes.sort_by { |r| r.name }
    )
  end
end

Opscode::Application::Callbacks.callback(:rails, :pre_deploy, app['id'], self)

## Then, deploy
deploy_revision app['id'] do
  revision app['revision'][node.chef_environment]
  repository app['repository']
  user app['owner']
  group app['group']
  deploy_to app['deploy_to']
  environment 'RAILS_ENV' => rails_env
  action app['force'][node.chef_environment] ? :force_deploy : :deploy
  ssh_wrapper "#{app['deploy_to']}/deploy-ssh-wrapper" if app['deploy_key']
  shallow_clone true
  before_migrate do
    if app['gems'].has_key?('bundler')
      link "#{release_path}/vendor/bundle" do
        to "#{app['deploy_to']}/shared/vendor_bundle"
      end
      common_groups = %w{development test cucumber staging production}
      if app.has_key? 'excluded_bundler_groups'
        common_groups += app['excluded_bundler_groups']
      end
      flag = File.exists?("#{app['deploy_to']}/Gemfile.lock") ? "--deployment": ""
      execute "bundle install #{flag} --without #{(common_groups -([rails_env])).join(' ')}" do
        ignore_failure false
        cwd release_path
      end
    elsif app['gems'].has_key?('bundler08')
      execute "gem bundle" do
        ignore_failure false
        cwd release_path
      end

    elsif node.chef_environment && app['databases'].has_key?(node.chef_environment)
      # chef runs before_migrate, then symlink_before_migrate symlinks, then migrations,
      # yet our before_migrate needs database.yml to exist (and must complete before
      # migrations).
      #
      # maybe worth doing run_symlinks_before_migrate before before_migrate callbacks,
      # or an add'l callback.
      execute "(ln -s ../../../shared/database.yml config/database.yml && rake gems:install); rm -f config/database.yml" do
        ignore_failure false
        cwd release_path
      end
    end
  end

  symlink_before_migrate({
    "database.yml" => "config/database.yml",
    "memcached.yml" => "config/memcached.yml"
  })

  if app['migrate'][node.chef_environment] && node[:apps][app['id']][node.chef_environment][:run_migrations]
    migrate true
    migration_command app['migration_command'] || "rake db:migrate"
  else
    migrate false
  end
  before_symlink do
    ruby_block "remove_run_migrations" do
      block do
        if node.role?("#{app['id']}_run_migrations")
          Chef::Log.info("Migrations were run, removing role[#{app['id']}_run_migrations]")
          node.run_list.remove("role[#{app['id']}_run_migrations]")
        end
      end
    end
  end

  Opscode::Application::Callbacks.callback(:rails, :deploy, app['id'], self)
end

Opscode::Application::Callbacks.callback(:rails, :post_deploy, app['id'], self)
