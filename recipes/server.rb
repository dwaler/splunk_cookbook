#
# Cookbook Name::splunk
# Recipe::server
#
# Copyright 2011-2012, BBY Solutions, Inc.
# Copyright 2011-2012, Opscode, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
me = node[:hostname]
customer = (me.split('-'))[1]
static_server_configs  = node[:splunk][:static_server_configs]
dynamic_server_configs = node[:splunk][:dynamic_server_configs]
dedicated_search_head  = node[:splunk][:dedicated_search_head]
dedicated_indexer      = node[:splunk][:dedicated_indexer]
search_master          = node[:splunk][:search_master]
license_master         = node[:splunk][:license_master]

service "splunk" do
  action [ :nothing ]
  supports  :status => true, :start => true, :stop => true, :restart => true
end

splunk_cmd = "#{node['splunk']['server_home']}/bin/splunk"
splunk_package_version = "splunk-#{node['splunk']['server_version']}-#{node['splunk']['server_build']}"

package "splunk" do
  action :install
end

if node['splunk']['distributed_search'] == true
  # Add the Distributed Search Template
  static_server_configs = [ static_server_configs, "distsearch" ]
   
  # We are a search head
  if dedicated_search_head == true
    search_indexers = node[:splunk][:island][customer].indexer
    # Add an outputs.conf.  Search Heads should not be doing any indexing
    static_server_configs = [ static_server_configs, "outputs" ]
  end

  # we are a dedicated indexer
  if dedicated_indexer == true
    # Find all search heads so we can move their trusted.pem files over
    search_heads = node[:splunk][:island][customer].searchhead
  end
end


template "#{node['splunk']['server_home']}/etc/splunk-launch.conf" do
    source "server/splunk-launch.conf.erb"
    mode "0640"
    owner "root"
    group "root"
end

if node['splunk']['use_ssl'] == true && dedicated_search_head == true
  directory "#{node['splunk']['server_home']}/ssl" do
    owner "root"
    group "root"
    mode "0755"
    action :create
    recursive true
  end

  cookbook_file "#{node['splunk']['server_home']}/ssl/#{node['splunk']['ssl_crt']}" do
    source "ssl/#{node['splunk']['ssl_crt']}"
    mode "0755"
    owner "root"
    group "root"
  end

  cookbook_file "#{node['splunk']['server_home']}/ssl/#{node['splunk']['ssl_key']}" do
    source "ssl/#{node['splunk']['ssl_key']}"
    mode "0755"
    owner "root"
    group "root"
  end

end

if node['splunk']['ssl_forwarding'] == true
  # Create the SSL Cert Directory for the Forwarders
  directory "#{node['splunk']['server_home']}/etc/auth/forwarders" do
    owner "root"
    group "root"
    action :create
    recursive true
  end

  # Copy over the SSL Certs
  [node['splunk']['ssl_forwarding_cacert'],node['splunk']['ssl_forwarding_servercert']].each do |cert|
    cookbook_file "#{cert}" do
      path "#{node['splunk']['server_home']}/etc/auth/forwarders/#{cert}"
      source "ssl/forwarders/#{cert}"
      owner "root"
      group "root"
      mode "0755"
      notifies :restart, resources(:service => "splunk")
    end
  end

  # SSL passwords are encrypted when splunk reads the file.  We need to save the password.
  # We need to save the password if it has changed so we don't keep restarting splunk.
  # Splunk encrypted passwords always start with $1$
  ruby_block "Saving Encrypted Password (inputs.conf/outputs.conf)" do
    block do
      inputsPass = `grep -m 1 "password = " #{node['splunk']['server_home']}/etc/system/local/inputs.conf | sed 's/password = //'`
      if inputsPass.match(/^\$1\$/) && inputsPass != node['splunk']['inputsSSLPass']
        node.default['splunk']['inputsSSLPass'] = inputsPass
        unless Chef::Config[:solo] 
          node.save
        end
      end

      if node['splunk']['distributed_search'] == true && dedicated_search_head == true 
        outputsPass = `grep -m 1 "sslPassword = " #{node['splunk']['server_home']}/etc/system/local/outputs.conf | sed 's/sslPassword = //'`
        
        if outputsPass.match(/^\$1\$/) && outputsPass != node['splunk']['outputsSSLPass']
          node.default['splunk']['outputsSSLPass'] = outputsPass
          unless Chef::Config[:solo]
            node.save
          end
        end
      end
    end
  end
end

# Read sslKeyPass from server.conf
ruby_block "Saving Encrypted Password (server.conf/inputs.conf/outputs.conf)" do
  block do
    sslKeyPass = `grep -m 1 "sslKeysfilePassword = " #{node['splunk']['server_home']}/etc/system/local/server.conf | sed 's/sslKeysfilePassword = //'`
    if sslKeyPass.match(/^\$1\$/) && sslKeyPass != node['splunk']['sslKeyPass']
      node.default['splunk']['sslKeyPass'] = sslKeyPass
      unless Chef::Config[:solo]
        node.save
      end
    elsif node['splunk']['sslKeyPass'].nil?
      node.default['splunk']['sslKeyPass'] = "password"       # Set default if empty
    end
  end
end

execute "#{splunk_cmd} enable boot-start --accept-license --answer-yes" do
  not_if do
    File.symlink?('/etc/rc3.d/S20splunk') ||
    File.symlink?('/etc/rc3.d/S90splunk')
  end
end

splunk_password = node['splunk']['auth'].split(':')[1]
execute "Changing Admin Password" do 
  command "#{splunk_cmd} edit user admin -password #{splunk_password} -roles admin -auth admin:changeme && echo true > /opt/splunk_setup_passwd"
  not_if do
    File.exists?("/opt/splunk_setup_passwd")
  end
end

static_server_configs.flatten.each do |cfg|
  template "#{node['splunk']['server_home']}/etc/system/local/#{cfg}.conf" do
   	source "server/#{cfg}.conf.erb"
   	owner "root"
   	group "root"
   	mode "0640"
    variables(
        :search_heads => search_heads,
        :search_indexers => search_indexers,
        :dedicated_search_head => dedicated_search_head,
        :dedicated_indexer => dedicated_indexer,
        :license_master => license_master,
        :customer => customer
      )
    notifies :restart, resources(:service => "splunk")
  end
end

dynamic_server_configs.flatten.each do |cfg|
  template "#{node['splunk']['server_home']}/etc/system/local/#{cfg}.conf" do
   	source "server/#{node['splunk']['server_config_folder']}/#{cfg}.conf.erb"
   	owner "root"
   	group "root"
   	mode "0640"
    notifies :restart, resources(:service => "splunk")
   end
end


template "/etc/init.d/splunk" do
    source "server/splunk.erb"
    mode "0755"
    owner "root"
    group "root"
end

directory "#{node['splunk']['server_home']}/etc/users/admin/search/local/data/ui/views" do
  owner "root"
  group "root"
  mode "0755"
  action :create
  recursive true
end

link "/var/log/splunk" do
  to "#{node['splunk']['server_home']}/var/log/splunk"
end

if node['splunk']['deploy_dashboards'] == true
  node['splunk']['dashboards_to_deploy'].each do |dashboard|
    cookbook_file "#{node['splunk']['server_home']}/etc/users/admin/search/local/data/ui/views/#{dashboard}.xml" do
      source "dashboards/#{dashboard}.xml"
    end
  end
end

if node['splunk']['distributed_search'] == true
  # If we are the license master we need the license file
  if license_master == true
    cookbook_file "Splunk.License.lic" do
       path "/opt/splunk/etc/licenses/enterprise/Splunk.License.lic"
       owner "splunk"
       group "splunk"
       mode  0600
       notifies :restart, "service[splunk]", :delayed
    end
  end

  if dedicated_search_head == true
    # We save this information so we can reference it on indexers.
    ruby_block "Splunk Server - Saving Info" do
      block do
        splunk_server_name = `grep -m 1 "serverName = " #{node['splunk']['server_home']}/etc/system/local/server.conf | sed 's/serverName = //'`
        splunk_server_name = splunk_server_name.strip
      
        if File.exists?("#{node['splunk']['server_home']}/etc/auth/distServerKeys/trusted.pem")
          trustedPem = IO.read("#{node['splunk']['server_home']}/etc/auth/distServerKeys/trusted.pem")
          if node['splunk']['trustedPem'] == nil || node['splunk']['trustedPem'] != trustedPem
            node.default['splunk']['trustedPem'] = trustedPem
            unless Chef::Config[:solo]
              node.save
            end
          end
        end

        if node['splunk']['splunkServerName'] == nil || node['splunk']['splunkServerName'] != splunk_server_name
          node.default['splunk']['splunkServerName'] = splunk_server_name
          unless Chef::Config[:solo]
            node.save
          end
        end
      end
    end
  end

  if dedicated_indexer == true
    # Create data disks
    cs_disk "splunk" do
      offering node[:splunk][:diskofferingid]
      device "/dev/xvde"
    end

    sbp_disk_manage "splunk" do
      device "/dev/xvde"
      mount_point node[:splunk][:db_directory]
      filesystem "ext4"
      mount_options "rw,barrier=1,errors=remount-ro"
      user "splunk"
      group "splunk"
      mode 00775
      action [:partition, :format, :mount]
    end

    search_heads.each do |server| 
      if server['splunk'] != nil && server['splunk']['trustedPem'] != nil && server['splunk']['splunkServerName'] != nil
        directory "#{node['splunk']['server_home']}/etc/auth/distServerKeys/#{server['splunk']['splunkServerName']}" do
          owner "root"
          group "root"
          action :create
        end

        file "#{node['splunk']['server_home']}/etc/auth/distServerKeys/#{server['splunk']['splunkServerName']}/trusted.pem" do
          owner "root"
          group "root"
          mode "0600"
          content server['splunk']['trustedPem'].strip
          action :create
          notifies :restart, resources(:service => "splunk")
        end
      end
    end
  end
end # End of distributed search

service "splunk" do
  action :start
end
