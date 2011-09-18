#
# Cookbook Name:: application
# Recipe:: java_webapp
#
# Copyright 2010-2011, Opscode, Inc.
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

include Opscode::Application::Helpers

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

directory app['deploy_to'] do
  owner app['owner']
  group app['group']
  mode '0755'
  recursive true
end

directory "#{app['deploy_to']}/releases" do
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

%w{ log pids system }.each do |dir|

  directory "#{app['deploy_to']}/shared/#{dir}" do
    owner app['owner']
    group app['group']
    mode '0755'
    recursive true
  end

end

dbm = database_master(app, self)
if dbm
  template "#{app['deploy_to']}/shared/#{app['id']}.xml" do
    source "context.xml.erb"
    owner app["owner"]
    group app["group"]
    mode "644"
    variables(
      :host => (dbm.attribute?('cloud') ? dbm['cloud']['local_ipv4'] : dbm['ipaddress']),
      :app => app['id'],
      :database => app['databases'][node.chef_environment],
      :war => "#{app['deploy_to']}/releases/#{app['war'][node.chef_environment]['checksum']}.war"
    )
  end
else
  Chef::Log.warn("No database master found, context.xml not rendered!")
end

## Then, deploy
Opscode::Application::Callbacks.callback(:java_webapp, :pre_deploy, app['id'], self)
remote_file app['id'] do
  path "#{app['deploy_to']}/releases/#{app['war'][node.chef_environment]['checksum']}.war"
  source app['war'][node.chef_environment]['source']
  mode "0644"
  checksum app['war'][node.chef_environment]['checksum']

  Opscode::Application::Callbacks.callback(:java_webapp, :deploy, app['id'], self)
end
Opscode::Application::Callbacks.callback(:java_webapp, :post_deploy, app['id'], self)
