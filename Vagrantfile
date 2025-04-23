VAGRANTFILE_API_VERSION = '2'

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
  config.vm.box = 'ubuntu/jammy64'
  config.vm.provision :shell, path: './vagrant/development.sh'
  config.vm.network :forwarded_port, guest: 9292, host: 9292

  config.vm.provider :virtualbox do |vb|
    vb.customize ['modifyvm', :id, '--memory', '8192']
    vb.name = 'neocities'
  end
end
