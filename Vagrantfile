# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  # Base box - Ubuntu 24.04 LTS
  config.vm.box = "ubuntu/jammy64"
  config.vm.box_version = "~> 20240701.0.0"
  
  # Common configuration for both VMs
  config.vm.provider "virtualbox" do |vb|
    vb.memory = "2048"
    vb.cpus = 2
    vb.linked_clone = true
  end
  
  # Disable automatic box update checking
  config.vm.box_check_update = false
  
  # Primary server (Docker Backup Manager)
  config.vm.define "primary" do |primary|
    primary.vm.hostname = "primary-server"
    primary.vm.network "private_network", ip: "192.168.56.10"
    
    # Port forwarding for services (using different ports to avoid conflicts)
    primary.vm.network "forwarded_port", guest: 80, host: 8090   # nginx-proxy-manager HTTP
    primary.vm.network "forwarded_port", guest: 443, host: 8453 # nginx-proxy-manager HTTPS
    primary.vm.network "forwarded_port", guest: 81, host: 8091  # nginx-proxy-manager admin
    primary.vm.network "forwarded_port", guest: 9000, host: 9001 # Portainer
    
    # Mount project directly to vagrant user's home for instant access
    primary.vm.synced_folder ".", "/home/vagrant/docker-stack-backup", type: "virtualbox", owner: "vagrant", group: "vagrant"
    
    # VirtualBox specific settings
    primary.vm.provider "virtualbox" do |vb|
      vb.name = "docker-backup-primary"
      vb.memory = "3072"
      vb.cpus = 2
    end
    
    # Minimal provisioning - VM setup only
    primary.vm.provision "shell", inline: <<-SHELL
      set -e
      
      echo "=== Setting up Primary Server (VM infrastructure only) ==="
      
      # Configure passwordless sudo for vagrant user
      echo 'vagrant ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers.d/vagrant
      chmod 440 /etc/sudoers.d/vagrant
      
      echo "=== Primary server VM setup completed ==="
    SHELL
  end
  
  # Remote server (for backup sync testing)
  config.vm.define "remote" do |remote|
    remote.vm.hostname = "remote-server"
    remote.vm.network "private_network", ip: "192.168.56.11"
    
    # Port forwarding for SSH
    remote.vm.network "forwarded_port", guest: 22, host: 2223, id: "ssh"
    
    # Mount project directly to vagrant user's home for instant access
    remote.vm.synced_folder ".", "/home/vagrant/docker-stack-backup", type: "virtualbox", owner: "vagrant", group: "vagrant"
    
    # VirtualBox specific settings
    remote.vm.provider "virtualbox" do |vb|
      vb.name = "docker-backup-remote"
      vb.memory = "1024"
      vb.cpus = 1
    end
    
    # Minimal provisioning - VM setup only
    remote.vm.provision "shell", inline: <<-SHELL
      set -e
      
      echo "=== Setting up Remote Server (VM infrastructure only) ==="
      
      # Configure passwordless sudo for vagrant user
      echo 'vagrant ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers.d/vagrant
      chmod 440 /etc/sudoers.d/vagrant
      
      echo "=== Remote server VM setup completed ==="
    SHELL
  end
end