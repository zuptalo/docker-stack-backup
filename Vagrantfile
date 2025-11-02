# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  # Base box - Ubuntu 24.04 LTS
  config.vm.box = "ubuntu/jammy64"
  config.vm.box_version = "~> 20240701.0.0"
  
  # Disable automatic box update checking
  config.vm.box_check_update = false
  
  # Primary server (Docker Backup Manager) - Single VM setup
  config.vm.define "primary", primary: true do |primary|
    primary.vm.hostname = "primary-server"
    primary.vm.network "private_network", ip: "192.168.56.10"
    
    # Port forwarding for services
    primary.vm.network "forwarded_port", guest: 80, host: 80   # nginx-proxy-manager HTTP
    primary.vm.network "forwarded_port", guest: 443, host: 443 # nginx-proxy-manager HTTPS
    primary.vm.network "forwarded_port", guest: 81, host: 81  # nginx-proxy-manager admin
    primary.vm.network "forwarded_port", guest: 9000, host: 9000 # Portainer
    primary.vm.network "forwarded_port", guest: 22, host: 22, id: "ssh" # SSH for NAS testing
    
    # Mount project directly to vagrant user's home for instant access
    primary.vm.synced_folder ".", "/home/vagrant/docker-stack-backup", type: "virtualbox", owner: "vagrant", group: "vagrant"
    
    # VirtualBox specific settings
    primary.vm.provider "virtualbox" do |vb|
      vb.name = "docker-backup-primary"
      vb.memory = "3072"
      vb.cpus = 2
      vb.linked_clone = true
    end
    
    # Minimal provisioning - VM setup only
    primary.vm.provision "shell", inline: <<-SHELL
      set -e

      echo "=== Setting up Primary Server (VM infrastructure only) ==="

      # Configure passwordless sudo for vagrant user
      echo 'vagrant ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers.d/vagrant
      chmod 440 /etc/sudoers.d/vagrant

      # Set test environment flag for backup manager (enables unrestricted SSH for testing)
      echo 'export DOCKER_BACKUP_TEST=true' >> /home/vagrant/.bashrc
      echo 'export DOCKER_BACKUP_TEST=true' >> /root/.bashrc

      # Enable SSH server for NAS backup testing from host
      systemctl enable ssh
      systemctl start ssh

      echo "=== Primary server VM setup completed ==="
    SHELL
  end

  # NAS server (simulates remote NAS/backup server)
  config.vm.define "nas", autostart: false do |nas|
    nas.vm.hostname = "nas-server"
    nas.vm.network "private_network", ip: "192.168.56.20"

    # Mount project for access to generated scripts
    nas.vm.synced_folder ".", "/home/vagrant/docker-stack-backup", type: "virtualbox", owner: "vagrant", group: "vagrant"

    # VirtualBox specific settings
    nas.vm.provider "virtualbox" do |vb|
      vb.name = "docker-backup-nas"
      vb.memory = "1024"
      vb.cpus = 1
      vb.linked_clone = true
    end

    # NAS server setup - minimal requirements for rsync/ssh
    nas.vm.provision "shell", inline: <<-SHELL
      set -e

      echo "=== Setting up NAS Server ==="

      # Configure passwordless sudo for vagrant user
      echo 'vagrant ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers.d/vagrant
      chmod 440 /etc/sudoers.d/vagrant

      # Set test environment flag for backup manager
      echo 'export DOCKER_BACKUP_TEST=true' >> /home/vagrant/.bashrc

      # Install rsync and SSH server for backup synchronization
      apt-get update -qq
      apt-get install -y rsync openssh-server

      # Enable SSH server
      systemctl enable ssh
      systemctl start ssh

      # Create backup storage directory
      mkdir -p /mnt/nas-backup
      chown vagrant:vagrant /mnt/nas-backup
      chmod 755 /mnt/nas-backup

      echo "=== NAS server setup completed ==="
      echo "IP Address: 192.168.56.20"
      echo "Backup Directory: /mnt/nas-backup"
    SHELL
  end
end