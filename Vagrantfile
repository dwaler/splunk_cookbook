# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  config.vm.hostname = "sbpasplunk-sbp-berkshelf"
  config.vm.box = "CentOS-6.4-x86_64"
  config.vm.box_url = "http://developer.nrel.gov/downloads/vagrant-boxes/CentOS-6.4-x86_64-v20130731.box"
  config.vm.network :private_network, ip: "33.33.33.10"
  config.berkshelf.enabled = true
  config.vm.provision :chef_solo do |chef|
    chef.json = {
      :splunk => {
        :island => {
          :sbp    => {
            :custname      => 'Schuberg Philis',
            :indexer       => [ 'sbpasplunk-sbp-berkshelf' ],
            :searchhead    => [ 'sbpasplunk-sbp-berkshelf' ],
            :clustermaster => [ 'sbpasplunk-sbp-berkshelf' ],
            :licensemaster => [ 'sbpasplunk-sbp-berkshelf' ]
          }
        },
        :use_ssl  => 'true',
        :dedicated_search_head => 'true'
      }       
    }

    chef.run_list = [
        "recipe[splunk_cookbook::server]"
    ]
  end
end
